// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Auction is ReentrancyGuard {
    //static
    address payable public immutable seller;
    IERC721 public immutable nft;
    uint public immutable nftId;
    uint private immutable duration;
    uint public immutable reservePrice;
    uint public immutable bidIncrement;
    uint public startAt;
    uint public expiresAt;

    //state
    bool public started;
    bool public canceled;
    address public highestBidder;
    mapping(address => uint256) public balanceOf;

    event Bid(address bidder, uint bid);
    event Canceled();

    constructor(
        address _nft,
        uint _nftId,
        uint _duration,
        uint _reservePrice,
        uint _bidIncrement
    ) {
        seller = payable(msg.sender);
        nft = IERC721(_nft);
        nftId = _nftId;
        duration = _duration;
        reservePrice = _reservePrice;
        bidIncrement = _bidIncrement;

        //for the first time to compare with highestBid
        balanceOf[address(0)] = _reservePrice;
    }

    function withdraw() public {
        require(msg.sender != highestBidder, "Your funds are locked!");

        uint amount = balanceOf[msg.sender];
        if (amount > 0) {
            balanceOf[msg.sender] = 0;
            payable(msg.sender).transfer(amount);
        }
    }

    function bid() public
    payable
    onlyNotCanceled
    onlyNotSeller
    returns (bool success)
    {
        uint newBid = balanceOf[msg.sender] + msg.value;
        uint highestBid = balanceOf[highestBidder];

        if (!started) {
            started = true;

            startAt = block.timestamp;
            expiresAt = block.timestamp + duration;

            //lock seller's NFT until it's finished or cancelled.
            IERC721(nft).transferFrom(seller, address(this), nftId);

            //First bid starts without bidIncrement
            highestBid -= (highestBid * bidIncrement) / 100;
        }

        // If the bid is not higher, send the
        // money back (the revert statement
        // will revert all changes in this
        // function execution including
        // it having received the money).
        require(newBid >= highestBid + (highestBid * bidIncrement) / 100, "Insufficient fund");


        require(startAt <= block.timestamp && block.timestamp <= expiresAt);

        balanceOf[msg.sender] = newBid;
        if (msg.sender != highestBidder) {
            highestBidder = msg.sender;
        }
        emit Bid(msg.sender, newBid);
        return true;
    }

    function resolve() public onlyEnded {
        // transfer tokens to highest bidder
        nft.transferFrom(address(this), highestBidder, nftId);

        // transfer ether balance to seller
        balanceOf[seller] += balanceOf[highestBidder];
        balanceOf[highestBidder] = 0;

        highestBidder = address(0);
    }

    function cancelAuction() public
    onlySeller
    onlyNotStarted
    onlyNotCanceled
    returns (bool success)
    {
        canceled = true;
        emit Canceled();
        return true;
    }

    modifier onlySeller {
        require(payable(msg.sender) == seller);
        _;
    }

    modifier onlyNotSeller {
        require(payable(msg.sender) != seller);
        _;
    }

    modifier onlyNotStarted{
        require(!started);
        _;
    }

    modifier onlyNotCanceled {
        require(!canceled);
        _;
    }

    modifier onlyEnded {
        require(started && block.timestamp >= expiresAt, "Auction was not started.");
        _;
    }
}