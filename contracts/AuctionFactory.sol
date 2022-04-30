// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract AuctionFactory is ReentrancyGuard {
    using Counters for Counters.Counter;
    //static
    Counters.Counter private _auctionIds;

    IERC721 public immutable nft;
    enum State {Created, Started, Canceled, Resolved}

    struct Auction {
        uint32 duration;
        uint32 startAt;
        uint32 expiresAt;
        address payable seller;
        address highestBidder;
        uint96 auctionId;
        uint96 reservePrice;
        uint96 tokenId;
        uint8 bidIncrement;
        State state;
    }

    mapping(uint96 => Auction) public auctions;
    mapping(uint96 => mapping(address => uint96)) public balanceOf;

    event AuctionCreated(
        uint indexed auctionId,
        address payable indexed seller,
        uint indexed tokenId,
        uint duration,
        uint reservePrice,
        uint bidIncrement
    );
    event AuctionStarted(uint auctionId);
    event AuctionResolved(uint auctionId);
    event AuctionCanceled(uint auctionId);
    event Bid(uint auctionId, address bidder, uint bid);

    constructor(address _nft) {
        nft = IERC721(_nft);
    }

    function create(
        uint96 _tokenId,
        uint32 _duration,
        uint96 _reservePrice,
        uint8 _bidIncrement
    ) external payable nonReentrant {
        require(nft.ownerOf(_tokenId) == msg.sender, "You have no this token.");
        _auctionIds.increment();
        uint96 auctionId = uint96(_auctionIds.current());

        Auction storage auction = auctions[auctionId];
        auction.auctionId = auctionId;
        auction.seller = payable(msg.sender);
        auction.tokenId = _tokenId;
        auction.duration = _duration;
        auction.reservePrice = _reservePrice;
        auction.bidIncrement = _bidIncrement;
        //for the first time to compare with highestBid
        balanceOf[auctionId][address(0)] = _reservePrice;

        emit AuctionCreated(
            auctionId,
            payable(msg.sender),
            _tokenId,
            _duration,
            _reservePrice,
            _bidIncrement
        );
    }

    function withdraw(uint96 _auctionId) external nonReentrant {
        Auction memory auction = auctions[_auctionId];
        require(msg.sender != auction.highestBidder, "Your funds are locked!");

        uint amount = balanceOf[_auctionId][msg.sender];
        if (amount > 0) {
            balanceOf[_auctionId][msg.sender] = 0;
            payable(msg.sender).transfer(amount);
        }
    }

    function bid(uint96 _auctionId) external payable nonReentrant returns (bool success)
    {
        Auction storage auction = auctions[_auctionId];
        require(auction.state != State.Canceled);
        require(auction.seller != payable(msg.sender));
        uint96 newBid = balanceOf[_auctionId][msg.sender] + uint96(msg.value);
        uint96 highestBid = balanceOf[_auctionId][auction.highestBidder];
        uint32 timestamp = uint32(block.timestamp);

        if (auction.state == State.Created) {
            auction.state = State.Started;
            emit AuctionStarted(_auctionId);

            auction.startAt = timestamp;
            auction.expiresAt = timestamp + auction.duration;

            //lock seller's NFT until it's finished or cancelled.
            IERC721(nft).transferFrom(auction.seller, address(this), auction.tokenId);

            //First bid starts without bidIncrement
            highestBid -= (highestBid * auction.bidIncrement) / 100;
        }

        // If the bid is not higher, send the
        // money back (the revert statement
        // will revert all changes in this
        // function execution including
        // it having received the money).
        require(newBid >= highestBid + (highestBid * auction.bidIncrement) / 100, "Insufficient fund");
        require(auction.startAt <= timestamp && timestamp <= auction.expiresAt);

        balanceOf[_auctionId][msg.sender] = newBid;
        if (msg.sender != auction.highestBidder) {
            auction.highestBidder = msg.sender;
        }
        emit Bid(_auctionId, msg.sender, newBid);
        return true;
    }

    function resolve(uint96 _auctionId) external nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(auction.state == State.Started && block.timestamp >= auction.expiresAt, "Auction was not started.");

        // transfer tokens to highest bidder
        nft.transferFrom(address(this), auction.highestBidder, auction.tokenId);

        // transfer ether balance to seller
        balanceOf[_auctionId][auction.seller] += balanceOf[_auctionId][auction.highestBidder];
        balanceOf[_auctionId][auction.highestBidder] = 0;

        auction.highestBidder = address(0);
        auction.state = State.Resolved;
        emit AuctionResolved(_auctionId);
    }

    function cancel(uint96 _auctionId) external returns (bool success)
    {
        Auction storage auction = auctions[_auctionId];
        require(payable(msg.sender) == auction.seller, "You are not a seller.");
        require(auction.state == State.Created, "You can't cancel this auction.");
        auction.state = State.Canceled;
        emit AuctionCanceled(_auctionId);
        return true;
    }

    /* Returns only auctions that a user has created */
    function fetch(address _seller) external view returns (Auction[] memory) {
        uint totalAuctionCount = _auctionIds.current();
        uint auctionCount = 0;
        uint currentIndex = 0;

        for (uint96 i = 0; i < totalAuctionCount; i++) {
            if (_seller == address(0) || auctions[i + 1].seller == payable(_seller)) {
                auctionCount += 1;
            }
        }

        Auction[] memory _auctions = new Auction[](auctionCount);
        for (uint96 i = 0; i < totalAuctionCount; i++) {
            if (_seller == address(0) || auctions[i + 1].seller == payable(_seller)) {
                Auction storage currentAuction = auctions[i + 1];
                _auctions[currentIndex] = currentAuction;
                currentIndex += 1;
            }
        }
        return _auctions;
    }
}