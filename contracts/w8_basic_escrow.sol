 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Escrow {
    // State variables
    address public buyer;
    address payable public seller;
    address public arbiter;
    uint public amount;
    bool public buyerDeposited;
    bool public fundsDisbursed;

    event Deposited(address indexed buyer, uint amount);
    event SellerRefundBuyer(address indexed seller, uint amount);
    event ArbiterRefundBuyer(address indexed arbiter, uint amount);
    event DeliveryConfirmed(address indexed confirmer, uint amount);
    event FundsReleasedToSeller(address indexed seller, uint amount);

    modifier onlyBuyerOrArbiter() {
        require(msg.sender == buyer || msg.sender == arbiter, "caller must be the buyer or the arbiter");
        _;
    }

    modifier onlySellerOrArbiter(){
        require(msg.sender == seller || msg.sender == arbiter, "caller must be the seller or the arbiter");
        _;
    }


    // Initialize the contract with the buyer, seller, and arbiter information
    constructor(address _buyer, address payable _seller, address _arbiter) {
        buyer = _buyer;
        seller = _seller;
        arbiter = _arbiter;
    }

    // The buyer deposits funds into the escrow. This function should be payable.
    function deposit() external payable {
        require(msg.sender == buyer, "Only the buyer can deposit.");
        require(!buyerDeposited, "Buyer has already deposited the funds.");
        amount = msg.value;
        buyerDeposited = true;
        emit Deposited(msg.sender, msg.value);
    }

    // The buyer confirms that they have received the item and releases funds to the seller.
    function confirmDelivery() external {
        // require(msg.sender == buyer || msg.sender == arbiter, "Only the buyer or the arbiter can release funds.");
        require(buyerDeposited, "Buyer must have deposted funds");
        require(fundsDisbursed, "Funds have already been disbursed");
    
        seller.transfer(amount);
        fundsDisbursed = true;

        emit DeliveryConfirmed(msg.sender, amount);
        emit FundsReleasedToSeller(seller, amount);
   
    }

    function refundBuyer() external onlySellerOrArbiter{

        require (buyerDeposited, "Buyer must have deposited funds");
        require (!fundsDisbursed, "Funds have already been disbursed");
        payable(buyer).transfer(amount);
        if (msg.sender == seller){
            emit SellerRefundBuyer(msg.sender, amount);
        } else {
            emit ArbiterRefundBuyer(msg.sender, amount);
        }
    }


    // Utility function to check the balance held in escrow.
    function getBalance() external view returns (uint) {
        return address(this).balance;
    }
}