// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IGameSwapDAO {
    function distributeFees() external payable;
}

contract GameSwapMarketplace is ReentrancyGuard, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    
    // Order status
    enum OrderStatus { Active, Canceled, Filled }
    
    // Order structure
    struct Order {
        uint256 id;
        address seller;
        uint256 tokenId;
        uint256 price;
        OrderStatus status;
        uint256 createdAt;
        string gameId;
        string itemType;
    }
    
    // Transaction structure
    struct Transaction {
        uint256 id;
        uint256 orderId;
        address buyer;
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 timestamp;
    }
    
    // Contract state variables
    IERC20 public immutable paymentToken;
    IERC721 public immutable nftContract;
    IGameSwapDAO public daoContract;
    
    uint256 public FEE_PERCENTAGE = 250; // 2.5% in basis points (100 = 1%)
    uint256 public orderCount;
    uint256 public transactionCount;
    uint256 public cumulativeFees;
    
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Transaction) public transactions;
    mapping(address => uint256[]) public sellerOrders;
    mapping(uint256 => uint256) public tokenIdToOrderId;
    
    // Events
    event OrderCreated(uint256 indexed orderId, address indexed seller, uint256 tokenId, uint256 price, string gameId, string itemType);
    event OrderCanceled(uint256 indexed orderId, address indexed seller);
    event OrderFilled(uint256 indexed orderId, address indexed buyer, address indexed seller, uint256 tokenId, uint256 price);
    event FeesCollected(uint256 amount);
    event DAOAddressUpdated(address newDaoAddress);
    event FeePercentageUpdated(uint256 newFeePercentage);
    
    constructor(
        address _paymentTokenAddress,
        address _nftContractAddress,
        address _daoAddress
    ) {
        require(_paymentTokenAddress != address(0), "GameSwapMarketplace: payment token cannot be zero address");
        require(_nftContractAddress != address(0), "GameSwapMarketplace: NFT contract cannot be zero address");
        require(_daoAddress != address(0), "GameSwapMarketplace: DAO address cannot be zero address");
        
        paymentToken = IERC20(_paymentTokenAddress);
        nftContract = IERC721(_nftContractAddress);
        daoContract = IGameSwapDAO(_daoAddress);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(DAO_ROLE, _daoAddress);
    }
    
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "GameSwapMarketplace: caller is not an operator");
        _;
    }
    
    modifier onlyDAO() {
        require(hasRole(DAO_ROLE, msg.sender), "GameSwapMarketplace: caller is not the DAO");
        _;
    }
    
    function createOrder(
        uint256 tokenId,
        uint256 price,
        string memory gameId,
        string memory itemType
    ) external nonReentrant returns (uint256) {
        require(price > 0, "GameSwapMarketplace: price must be greater than 0");
        require(nftContract.ownerOf(tokenId) == msg.sender, "GameSwapMarketplace: caller is not the token owner");
        require(tokenIdToOrderId[tokenId] == 0, "GameSwapMarketplace: token already has an active order");
        
        // Transfer NFT to marketplace
        nftContract.transferFrom(msg.sender, address(this), tokenId);
        
        // Create order
        orderCount++;
        uint256 orderId = orderCount;
        
        orders[orderId] = Order({
            id: orderId,
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            status: OrderStatus.Active,
            createdAt: block.timestamp,
            gameId: gameId,
            itemType: itemType
        });
        
        sellerOrders[msg.sender].push(orderId);
        tokenIdToOrderId[tokenId] = orderId;
        
        emit OrderCreated(orderId, msg.sender, tokenId, price, gameId, itemType);
        
        return orderId;
    }
    
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        
        require(order.id != 0, "GameSwapMarketplace: order does not exist");
        require(order.seller == msg.sender, "GameSwapMarketplace: caller is not the seller");
        require(order.status == OrderStatus.Active, "GameSwapMarketplace: order is not active");
        
        // Update order status
        order.status = OrderStatus.Canceled;
        
        // Return NFT to seller
        nftContract.transferFrom(address(this), msg.sender, order.tokenId);
        
        // Clear token to order mapping
        tokenIdToOrderId[order.tokenId] = 0;
        
        emit OrderCanceled(orderId, msg.sender);
    }
    
    function fillOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        
        require(order.id != 0, "GameSwapMarketplace: order does not exist");
        require(order.status == OrderStatus.Active, "GameSwapMarketplace: order is not active");
        require(order.seller != msg.sender, "GameSwapMarketplace: seller cannot buy their own order");
        
        // Calculate fee amount
        uint256 feeAmount = (order.price * FEE_PERCENTAGE) / 10000;
        uint256 sellerAmount = order.price - feeAmount;
        
        // Transfer payment token from buyer to seller and collect fees
        paymentToken.transferFrom(msg.sender, order.seller, sellerAmount);
        paymentToken.transferFrom(msg.sender, address(this), feeAmount);
        
        // Transfer NFT from marketplace to buyer
        nftContract.transferFrom(address(this), msg.sender, order.tokenId);
        
        // Update order status
        order.status = OrderStatus.Filled;
        
        // Clear token to order mapping
        tokenIdToOrderId[order.tokenId] = 0;
        
        // Track transaction
        transactionCount++;
        transactions[transactionCount] = Transaction({
            id: transactionCount,
            orderId: orderId,
            buyer: msg.sender,
            seller: order.seller,
            tokenId: order.tokenId,
            price: order.price,
            timestamp: block.timestamp
        });
        
        // Update fees collected
        cumulativeFees += feeAmount;
        
        emit OrderFilled(orderId, msg.sender, order.seller, order.tokenId, order.price);
        
        // Emit fee collection event
        emit FeesCollected(feeAmount);
    }
    
    function getOrder(uint256 orderId) external view returns (Order memory) {
        require(orders[orderId].id != 0, "GameSwapMarketplace: order does not exist");
        return orders[orderId];
    }
    
    function getTransaction(uint256 transactionId) external view returns (Transaction memory) {
        require(transactions[transactionId].id != 0, "GameSwapMarketplace: transaction does not exist");
        return transactions[transactionId];
    }
    
    function getSellerOrders(address seller) external view returns (uint256[] memory) {
        return sellerOrders[seller];
    }
    
    function getOrderByTokenId(uint256 tokenId) external view returns (Order memory) {
        uint256 orderId = tokenIdToOrderId[tokenId];
        require(orderId != 0, "GameSwapMarketplace: no active order for this token");
        return orders[orderId];
    }
    
    function distributeFees() external onlyOperator nonReentrant {
        uint256 balance = paymentToken.balanceOf(address(this)); //get how much we can distribute
        require(balance > 0, "GameSwapMarketplace: no fees to distribute"); //cant distribute without balance
        
        // Transfer fees to DAO using transferFrom 
        // First approve the funds
        paymentToken.approve(address(daoContract), balance); 
        
        // Transfer tokens to DAO
        bool success = paymentToken.transfer(address(daoContract), balance);
        require(success, "GameSwapMarketplace: token transfer failed");
        
        // Call DAO to distribute fees
        daoContract.distributeFees();
        
        emit FeesCollected(balance);
    }
    
    function setFeePercentage(uint256 newFeePercentage) external onlyDAO {
        require(newFeePercentage <= 1000, "GameSwapMarketplace: fee percentage too high");
        FEE_PERCENTAGE = newFeePercentage;
        emit FeePercentageUpdated(newFeePercentage);
    }
    
    function setDAOAddress(address newDaoAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newDaoAddress != address(0), "GameSwapMarketplace: DAO address cannot be zero address");
        
        // Revoke old role and grant new role
        revokeRole(DAO_ROLE, address(daoContract));
        grantRole(DAO_ROLE, newDaoAddress);
        
        // Update DAO contract
        daoContract = IGameSwapDAO(newDaoAddress);
        
        emit DAOAddressUpdated(newDaoAddress);
    }
} 

