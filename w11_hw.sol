// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract week11_auction {

    address public owner;
    address public creator;
    uint256 public endTime;
    uint256 public minIncrement; // Minimum bid increment
    uint256 public highestBid;
    address public highestBidder;
    uint256 public soldCount;
    bool public ended;
    uint256 public royaltyRate = 5; // 5%
    mapping(address => uint256) public pendingReturns; //store bidders amount 
    
    event NewBid(address indexed bidder, uint256 amount);
    event bidRefund(address indexed lastBidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event RoyaltyPaid(address indexed creator, uint256 amount);
    event Resale(address indexed bidder, uint256 amount);
    
    
    modifier onlyAfterEnd() {
        require(block.timestamp >= endTime, "Auction not ended");
        _;
    }
    
    modifier onlyNotEnded() {
        require(!ended, "Auction already ended");
        _;
    }

    modifier onlyEnded() {
        require(ended, "Cant overlap with ongoing auction");
        _;
    }


    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _creator,
        uint256 _duration,
        uint256 _minIncrement
    ) {
        owner = msg.sender;
        creator = _creator;
        endTime = block.timestamp + _duration;
        minIncrement = _minIncrement;
        soldCount = 0;
    }
    
    function bid() external payable onlyNotEnded {
        require(msg.value >= highestBid + minIncrement, "Too low");
        require(msg.sender != owner, "Owner cant be the bidder");
        
        if (highestBid > 0) {
            address lastHighestBidder = highestBidder;
            uint256 amount = pendingReturns[lastHighestBidder];
            highestBidder = msg.sender;
            highestBid = msg.value;
            pendingReturns[highestBidder] = highestBid;
            pendingReturns[lastHighestBidder] = 0; //effect
            (bool success, ) = lastHighestBidder.call{value: amount}("");//interact, refunding to last highest bidder
            require(success, "refunds failed");
            emit bidRefund(lastHighestBidder, amount);
        }else{      
            highestBidder = msg.sender;
            highestBid = msg.value;
            pendingReturns[highestBidder] = highestBid;
            emit NewBid(msg.sender, msg.value);
        }
    }
    
    // Withdraw refunded amount
    function withdraw() external {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "No funds to withdraw"); //check
        
        pendingReturns[msg.sender] = 0; //effect
        (bool success, ) = msg.sender.call{value: amount}("");//interact
        require(success, "Withdrawal failed");
    }
    
    function endAuction() external onlyAfterEnd onlyOwner{
        ended = true;
        
        if (highestBid == 0) {
            emit AuctionEnded(address(0), 0);
            return;
        }
        
        uint256 royaltyAmount = (highestBid * royaltyRate) / 100; //5% royalties
        uint256 sellerProceeds = highestBid - royaltyAmount; //95%
        
        (bool royaltySuccess, ) = creator.call{value: royaltyAmount}(""); //sending money back to art creator
        require(royaltySuccess, "Royalty transfer failed");
        emit RoyaltyPaid(creator, royaltyAmount);
        
        (bool sellerSuccess, ) = owner.call{value: sellerProceeds}(""); //owner get money
        require(sellerSuccess, "Seller transfer failed");

        soldCount += 1;
        owner = highestBidder; //updating new owner
        highestBid=0; //resetting highest bid after auction
        
        emit AuctionEnded(highestBidder, highestBid);
    }
    
    //new owner reselling 
    function resaleWithRoyalty(uint256 newDuration, uint256 newMinIncrement) external payable onlyEnded onlyOwner{
        require(soldCount > 0, "You cant resell before the first auction");

        minIncrement = newMinIncrement;
        endTime = block.timestamp + newDuration;
        ended = false;
    }
    
    function getAuctionStatus() external view returns (
        address currentHighestBidder,
        uint256 currentHighestBid,
        uint256 timeRemaining,
        bool isEnded
    ) {
        uint256 timeLeft;
        if (block.timestamp >= endTime){
            timeLeft = 0;
        }else{
            timeLeft = endTime - block.timestamp;
        }
        return (highestBidder, highestBid, timeLeft, ended);
    }
}