 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


 // hw8_VulnerableEscrow.sol - Find and fix the vulnerabilities
contract hw8_VulnerableEscrow {
    address public buyer;
    address public seller;
    address public arbiter;
    uint public amount;
    uint public releasedAmount;
    bool public isDeposited;
    bool public fundsDisbursed;
    bool public isRefunded;
    
    modifier onlyBuyer() {
        require(msg.sender == buyer, "Only buyer");
        _;
    }
    
    modifier onlySeller() {
        require(msg.sender == seller, "Only seller");
        _;
    }
    
    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Only arbitrator");
        _;
    }

    event Deposited(address indexed buyer, uint amount);
    event SellerRefundBuyer(address indexed seller, uint amount);
    event ArbiterRefundBuyer(address indexed arbiter, uint amount);
    event DeliveryConfirmed(address indexed confirmer, uint amount);
    event FundsReleasedToSeller(address indexed seller, uint amount);
    event PartialRelease(uint256 released, uint256 remaining);

    modifier onlyBuyerOrArbiter() {
        require(msg.sender == buyer || msg.sender == arbiter, "caller must be the buyer or the arbiter");
        _;
    }

    modifier onlySellerOrArbiter(){
        require(msg.sender == seller || msg.sender == arbiter, "caller must be the seller or the arbiter");
        _;
    }
    
    constructor(address _buyer, address _seller, address _arbiter, uint256 _amount) {
        buyer = _buyer;
        seller = _seller;
        arbiter = _arbiter;
        amount = _amount;
        isRefunded = false;
    }

    // Vulnerability 1: No access control
    function deposit() public payable onlyBuyer { 
        require(msg.value == amount, "Incorrect deposit amount"); 
        isDeposited = true; 
    } 
    // Vulnerability 2: No balance check
    function withdraw() public onlyBuyer { 
        require(address(this).balance >= amount, "Insufficient balance"); payable(msg.sender).transfer(amount); 
        isDeposited = false; 
    } 
    // Vulnerability 3: No state management
    function release() public onlyBuyer { 
        require(isDeposited, "Funds have not been deposited"); payable(seller).transfer(amount); 
        isDeposited = false; 
    } 


    // Partial refund functionality
    function releasePartial(uint256 amountToRelease) external onlyBuyer {
        require(isDeposited, "Buyer must have deposted funds");
        require(!fundsDisbursed, "Funds have already been disbursed");
        require (!isRefunded, "Funcds have already refunded");
        require(amountToRelease > 0 && amountToRelease <= amount, "Invalid amount");
        releasedAmount = amountToRelease;
        amount = amount - amountToRelease; // update state first to prevent amount staying the same while partial already released
        if (amount == 0){
            fundsDisbursed = true;
        }
        payable(seller).transfer(amountToRelease);
        emit PartialRelease(amountToRelease, amount);
    }

    // Dispute resolution mechanism
     function confirmDelivery() external onlyArbiter{
        // require(msg.sender == buyer || msg.sender == arbiter, "Only the buyer or the arbiter can release funds.");
        require(isDeposited, "Buyer must have deposted funds");
        require(!fundsDisbursed, "Funds have already been disbursed");
        require (!isRefunded, "Funcds have already refunded");
        fundsDisbursed = true; //updating the state first
        payable(seller).transfer(amount);

        emit DeliveryConfirmed(msg.sender, amount);
        emit FundsReleasedToSeller(seller, amount);
    }
    // Dispute resolution mechanism
    function refundBuyer() external onlySellerOrArbiter{

        require (isDeposited, "Buyer must have deposited funds");
        require (!fundsDisbursed, "Funds have already been disbursed");
        require (!isRefunded, "Funcds have already refunded");
        isRefunded = true;
        payable(buyer).transfer(amount);
        if (msg.sender == seller){
            emit SellerRefundBuyer(msg.sender, amount);
        } else {
            emit ArbiterRefundBuyer(msg.sender, amount);
        }
    }
}
