 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

 // Importing ERC721URIStorage and Ownable contracts from OpenZeppelin for NFT functionality and access control
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
 // Importing Counters utility from OpenZeppelin to use for token ID incrementing
import "@openzeppelin/contracts/utils/Counters.sol";

 // The Ticket contract inherits from ERC721URIStorage for NFT functionality and Ownable for access control
contract Cw7_NFT_Ticket is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;  // Using the Counters library for the Counter type
    Counters.Counter private tokenIdCounter;  // A counter to keep track of token IDs

    // A struct to store information about each ticket
    struct TicketInfo {
        uint256 tokenId;
        uint256 totalTickets;
        uint256 ticketsSold;
        uint256 ticketPrice;
        uint256 ticketStartDate;
        uint256 ticketEndDate;
        address creator;
        bool ticketSold;
    }

    // A struct to store purchase information for a ticket
    struct PurchaseInfo {
        address buyer;
        uint256 ticketsBought;
        uint256 totalPrice;
        uint256 ticketId;
        uint256 purchaseId;
        uint256 purchaseTimestamp;
    }

    // Variables to store the fee percentages for creating and purchasing a ticket
    uint256 public creationFeePercentage;
    uint256 public purchaseFeePercentage;

    // Mappings to store ticket information and purchases
    mapping(uint256 => TicketInfo) public tickets;  // Mapping from token ID to TicketInfo
    mapping(address => uint256[]) public userTickets;  // Mapping from user address to list of owned ticket IDs
    mapping(uint256 => PurchaseInfo[]) public ticketPurchases;  // Mapping from token ID to list of PurchaseInfo

    // Events to log the creation and purchase of tickets
    event TicketCreated(
        uint256 indexed tokenId,
        uint256 totalTickets,
        uint256 ticketPrice,
        uint256 ticketStartDate,
        uint256 ticketEndDate
    );

    event TicketPurchased(
        uint256 indexed tokenId,
        address buyer,
        uint256 ticketsBought
    );

    // Constructor to initialize the NFT contract with a name, symbol, and fee percentages
    constructor(string memory name, string memory symbol, uint256 _creationFeePercentage, uint256 _purchaseFeePercentage) 
        ERC721(name, symbol)  // Initialize the inherited ERC721 contract with the provided name and symbol
        Ownable(msg.sender) {  // Set the deployer of the contract as the initial owner
        creationFeePercentage = _creationFeePercentage;  // Set the creation fee percentage
        purchaseFeePercentage = _purchaseFeePercentage;  // Set the purchase fee percentage
    }

    // A function to create a new ticket with specified properties
    function createTicket(
        string calldata tokenURI,  // The URI for the token metadata
        uint256 _totalTickets,  // The total number of tickets available for sale
        uint256 _ticketPrice,  // The price per ticket
        uint256 _ticketEndDate  // The date when ticket sales end
    ) external payable {  // The function is payable to accept Ether for the creation fee
        // Validate inputs
        require(_totalTickets > 0, "Total tickets must be greater than 0");
        require(_ticketPrice > 0, "Ticket price must be greater than 0");
        require(_ticketEndDate > block.timestamp, "Ticket end date must be in the future");

        // Get the current token ID and increment the counter for the next token
        uint256 currentID = tokenIdCounter.current();
        tokenIdCounter.increment();

        // Mint a new token to the sender and set its metadata URI
        _safeMint(msg.sender, currentID);
        _setTokenURI(currentID, tokenURI);

        // Record the current time as the ticket start date
        uint256 ticketStartDate = block.timestamp;

        // Create a TicketInfo object and store it in the tickets mapping
        tickets[currentID] = TicketInfo({
            tokenId: currentID,
            totalTickets: _totalTickets,
            ticketsSold: 0,
            ticketPrice: _ticketPrice,
            ticketStartDate: ticketStartDate,
            ticketEndDate: _ticketEndDate,
            creator: msg.sender,
            ticketSold: false
        });


        //uint256 creationFee = creationFeePercentage;

        // creationFeePercentage is 1 ETH (1000000000000000000 Wei)
        uint256 creationFee = 1 ether; //Covert to Wei explicityly

        // Ensure the correct creation fee is paid
        require(msg.value == creationFee, "Incorrect creation fee sent");

        // Transfer the creation fee to the contract owner
        payable(owner()).transfer(creationFee);

        // Emit an event to log theIt seems there has been a misunderstanding; the previous message provided code with comments explaining each line. If you need further assistance or have specific questions about the code, please let me know, and I'll be happy to help!
        // Emit an event to log the creation of the new ticket
        emit TicketCreated(
            currentID,
            _totalTickets,
            _ticketPrice,
            ticketStartDate,
            _ticketEndDate
        );
    }

    // A function to purchase tickets for a given token ID
    function purchaseTicket(uint256 _tokenId, uint256 _ticketsToPurchase) external payable {
        // Validate inputs and state
        require(_ticketsToPurchase > 0, "Must purchase at least one ticket");
        require(tickets[_tokenId].ticketEndDate > block.timestamp, "Ticket sales ended");
        require(tickets[_tokenId].ticketsSold + _ticketsToPurchase <= tickets[_tokenId].totalTickets, "Not enough tickets left");


        // Calculate the total price for the requested tickets
        uint256 totalPrice = _ticketsToPurchase * tickets[_tokenId].ticketPrice;

        // Add 1 ETH as purchase fee
        uint256 totalPriceWithFee = totalPrice + 1 ether; // Changed this line

        // Calculate the purchase fee based on the provided percentage (it is fix Amount, not in %)
        //uint256 totalPriceWithFee = totalPrice + purchaseFeePercentage;
    

        // Ensure the correct amount of Ether is sent to purchase the tickets
        require(msg.value == totalPriceWithFee, "Incorrect amount of Ether sent");

        // Update the tickets sold count in the TicketInfo
        tickets[_tokenId].ticketsSold += _ticketsToPurchase;


        // Transfer the purchase fee (1 ETH) to the contract owner
        payable(owner()).transfer(1 ether); // Changed this line
        // Transfer the remaining amount to the ticket creator
        payable(tickets[_tokenId].creator).transfer(totalPrice); // Changed this line - removed fee subtraction

        // Calculate the purchase fee based on the provided percentage
        //uint256 purchaseFee = (purchaseFeePercentage * totalPrice) / 100;
        // Transfer the purchase fee to the contract owner
        //payable(owner()).transfer(purchaseFeePercentage);
        // Transfer the remaining amount to the ticket creator
        //payable(tickets[_tokenId].creator).transfer(totalPrice - purchaseFeePercentage);

        // Record the purchase information in the ticketPurchases mapping
        PurchaseInfo memory purchase = PurchaseInfo({
            buyer: msg.sender,
            ticketsBought: _ticketsToPurchase,
            totalPrice: totalPrice,
            ticketId: _tokenId,
            purchaseId: ticketPurchases[_tokenId].length,
            purchaseTimestamp: block.timestamp
        });
        ticketPurchases[_tokenId].push(purchase);

        // Add the token ID to the list of tickets owned by the buyer
        userTickets[msg.sender].push(_tokenId);

        // Emit an event to log the purchase of the tickets
        emit TicketPurchased(_tokenId, msg.sender, _ticketsToPurchase);
    }

    // Additional functions (e.g., for managing tickets, updating fees, etc.) would go here

    // ...
}