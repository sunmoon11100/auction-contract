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
        uint auctionId;
        address payable seller;
        uint tokenId;
        uint duration;
        uint reservePrice;
        uint bidIncrement;
        State state;
        uint startAt;
        uint expiresAt;
        address highestBidder;
    }

    mapping(uint => Auction) public auctions;
    mapping(uint => mapping(address => uint)) public balanceOf;

    event AuctionCreated(
        uint auctionId,
        address payable seller,
        uint tokenId,
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

    function createAuction(
        uint _tokenId,
        uint _duration,
        uint _reservePrice,
        uint _bidIncrement
    ) public payable nonReentrant {
        require(nft.ownerOf(_tokenId)==msg.sender, "You have no this token.");
        _auctionIds.increment();
        uint auctionId = _auctionIds.current();

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

    function withdraw(uint _auctionId) public nonReentrant{
        Auction storage auction = auctions[_auctionId];
        require(msg.sender != auction.highestBidder, "Your funds are locked!");

        uint amount = balanceOf[_auctionId][msg.sender];
        if (amount > 0) {
            balanceOf[_auctionId][msg.sender] = 0;
            payable(msg.sender).transfer(amount);
        }
    }

    function bid(uint _auctionId) public
    payable
    nonReentrant
    returns (bool success)
    {
        Auction storage auction = auctions[_auctionId];
        require(auction.state != State.Canceled);
        require(auction.seller != payable(msg.sender));
        uint newBid = balanceOf[_auctionId][msg.sender] + msg.value;
        uint highestBid = balanceOf[_auctionId][auction.highestBidder];

        if (auction.state == State.Created) {
            auction.state = State.Started;
            emit AuctionStarted(_auctionId);

            auction.startAt = block.timestamp;
            auction.expiresAt = block.timestamp + auction.duration;

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
        require(auction.startAt <= block.timestamp && block.timestamp <= auction.expiresAt);

        balanceOf[_auctionId][msg.sender] = newBid;
        if (msg.sender != auction.highestBidder) {
            auction.highestBidder = msg.sender;
        }
        emit Bid(_auctionId, msg.sender, newBid);
        return true;
    }

    function resolve(uint _auctionId) public nonReentrant{
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

    function cancelAuction(uint _auctionId) public
    returns (bool success)
    {
        Auction storage auction = auctions[_auctionId];
        require(payable(msg.sender) == auction.seller, "You are not a seller.");
        require(auction.state == State.Created, "You can't cancel this auction.");
        auction.state = State.Canceled;
        emit AuctionCanceled(_auctionId);
        return true;
    }

    /* Returns only auctions that a user has created */
    function fetchAuctions(address _seller) public view returns (Auction[] memory) {
        uint totalAuctionCount = _auctionIds.current();
        uint auctionCount = 0;
        uint currentIndex = 0;

        for (uint i = 0; i < totalAuctionCount; i++) {
            if (_seller == address(0) || auctions[i + 1].seller == payable(_seller)) {
                auctionCount += 1;
            }
        }

        Auction[] memory _auctions = new Auction[](auctionCount);
        for (uint i = 0; i < totalAuctionCount; i++) {
            if (_seller == address(0) || auctions[i + 1].seller == payable(_seller)) {
                Auction storage currentAuction = auctions[i + 1];
                _auctions[currentIndex] = currentAuction;
                currentIndex += 1;
            }
        }
        return _auctions;
    }
}