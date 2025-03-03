// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SupplyChainContract{
    //Contrat owner
    address public owner;
    //Product Count
    uint256 public productCount;
    //Batch Count
    uint256 public batchCount;
    //Mapping authorized Participants
    mapping(address => bool) public authorizedParticipants;
    //Mapping for products
    mapping(uint256 => Product) public products;
    mapping(uint256 => Batch) public batches;  

    struct Product{
        uint256 id;
        string name;
        string description;
        address currentOwner;
        uint256 timestamp;
        bool isRecalled;
    }

    struct Batch{
        uint256[] id;
        string[] name;
        string[] description;
        address currentOwner;
        uint256 timestamp;
        bool isRecalled;
        uint256 batchId;
        string operation;
    }
    

    event ProdustRegistered(uint256 indexed productId, string name, address indexed owner);
    event OwnershipTransferred(uint256 indexed productID, address indexed previousowner, address indexed newOwner);
    event ParticipantAuthorized(address indexed participant);
    event ProductRecalled(uint256 indexed  productID, string reasons);
    event BatchCreation(uint256 indexed batchId, string operation);
    event BatchProcessed(uint256 indexed batchId, string operation);
    event BatchRecalled(uint256 indexed  batchId, string reasons);
    error UnauthorizedAccess(address caller);
    error InvalidProductId(uint256 productId);
    error InvalidOwnershipTransfer(uint256 productId, address from, address to);
    error InvalidAddress();
    error ProductAlreadyExists(uint256 productId);
    error EmptyParameter(string paramName);
    error ProductDoesntExists();
    error AlreadyRecalled();

    //Constructor only happen during deployment
    constructor(){
        owner = msg.sender;
        productCount = 0;
        batchCount = 0;
        authorizedParticipants[msg.sender] = true;
        emit ParticipantAuthorized(msg.sender);
    }

    modifier onlyOwner(){
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyAuthorized(){
        require(authorizedParticipants[msg.sender], "Not authorized");
        _;
    }

    function addParticipant(address participant) public onlyOwner{
        authorizedParticipants[participant] = true;
    }

    function authorizeParticipant(address participant) public onlyOwner{
        require(participant != address(0), "Invalid address");
        require(!authorizedParticipants[participant], "Participant already authorized");
        authorizedParticipants[participant] = true;
        emit ParticipantAuthorized(participant);
    }

    function registerProduct(string memory name, string memory description) public onlyAuthorized{
        
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(description).length > 0, "Description cannot be empty");
        
        productCount++;
        uint256 productID = productCount;
        products[productID] = Product({
            id: productID,
            name: name,
            description: description,
            currentOwner: msg.sender,
            timestamp: block.timestamp,
            isRecalled: false //Recall status initiated at false
        });
    }

    function transferProductOwnership(uint256 productId, address newOwner) public onlyAuthorized{
        require(productId > 0 && productId <= productCount, "Invalid product ID");
        require(!products[productId].isRecalled, "Recalled products cannot be transferred"); //Cannot transfer recalled products, Proper error messages when attempted
        require(newOwner != address(0), "Invalid new owner address");
        require(authorizedParticipants[newOwner], "New owner is not authorized");
        require(products[productId].currentOwner == msg.sender, "Only current owner can transfer");
        address previousOwner = products[productId].currentOwner;
        products[productId].currentOwner = newOwner;
        products[productId].timestamp = block.timestamp;
        emit OwnershipTransferred( productId, previousOwner, newOwner);
    }

    function productExists(uint256 productId) public view returns (bool) {
        for (uint i = 0; i < productCount; i++) {
            if (productId == products[i].id){
                return true;
            }
        }
        return false;
    }

    function batchExists(uint256 batchId) public view returns (bool) {
        if (batches[batchId].batchId !=0){
            return true;
        }
        return false;
    }

    // Marks a product as recalled
    function recallBatch(uint256 batchId, string memory reasons) public onlyAuthorized { //Verify caller authorization done
        //Check if batchId exists
        require(batchExists(batchId), "Batch doesnt exists"); //Check product exists done

        // Check if batchId is not already recalled
        require(!batches[batchId].isRecalled, "Batch already recalled"); //Cannot recall already recalled products
        
        // Mark product as recalled
        batches[batchId].isRecalled = true; //Set recall status done
        
        // Emit recall event
        emit BatchRecalled(batchId, reasons); //event emission with relevant details, Clear tracking of recall reason
    }

    function recallProduct(uint256 productId, string memory reasons) public onlyAuthorized { //Verify caller authorization done
        //Check if product exists
        require(productExists(productId), "Product doesnt exists"); //Check product exists done

        // Check if product is not already recalled
        require(!products[productId].isRecalled, "Already recalled"); //Cannot recall already recalled products
        
        // Mark product as recalled
        products[productId].isRecalled = true; //Set recall status done
        
        // Emit recall event
        emit ProductRecalled(productId, reasons); //event emission with relevant details, Clear tracking of recall reason
    }

    function getProduct(uint256 productId) public view returns (
        uint256 id,
        string memory name,
        address currentOwner,
        uint256 timestamp,
        bool isRecalled
    ) {
        // Get product from storage
        Product memory product = products[productId];
        
        // Return all product fields
        return (
            product.id,
            product.name,
            product.currentOwner,
            product.timestamp,
            product.isRecalled
        );
    }

    function getBatch(uint256 batchIndex) public view returns (
        uint256[] memory id,
        string[] memory name,
        string[] memory description,
        address currentOwner,
        uint256 timestamp,
        bool isRecalled,
        uint256 batchId,
        string memory operation
    ) {
        // Get product from storage
        Batch memory batch = batches[batchIndex];
        
        // Return all product fields
        return (
            batch.id,
            batch.name,
            batch.description,
            batch.currentOwner,
            batch.timestamp,
            batch.isRecalled,
            batch.batchId,
            batch.operation
        );
    }

    function stateRecalled(uint256 productId) public view returns (bool){
        require(productExists(productId), "It doesnt exists");
        Product memory product = products[productId];
        // Return all product fields
        return (
            product.isRecalled
        );
    }

    function operationConvert(uint256 x) public pure returns (string memory y){
        if (x == 1) return "resgisterBatch";
        else if (x == 2) return "transferBatch";
        else if (x == 3) return "recallBatch";
    }



    // struct Batch{
    //     uint256[] id;
    //     string[] name;
    //     string[] description;
    //     address currentOwner;
    //     uint256 timestamp;
    //     bool isRecalled;
    //     uint256 batchId;
    //     uint256 operationIndex;
    // }

    function createBatch(uint256[] memory lst_id , string[] memory lst_name, string[] memory lst_description, string memory operation) public onlyAuthorized{
        require(lst_id.length > 0, "ID list cannot be empty");
        require(lst_name.length > 0, "Name cannot be empty");
        require(lst_description.length > 0, "Description cannot be empty");
        // require(operationInt > 0, "operation cannot be less than 1 or larger than 3");
        // require(operationInt < 4, "operation cannot be less than 1 or larger than 3");
        batchCount++;
        uint256 BatchId = batchCount;
        batches[BatchId] = Batch({
            id: lst_id,
            name: lst_name,
            description: lst_description,
            currentOwner: owner,
            timestamp: block.timestamp,
            isRecalled: false,
            batchId: BatchId,
            operation: operation
        });
        emit BatchCreation(BatchId,operation);
    }
        function processBatch(uint256 batchId, address newOwner, uint256 operationIndex, string memory reasons) public onlyAuthorized {
            require(batches[batchId].batchId != 0, "Batch doesnt exist"); //validate batch
            // TODO: Implement batch processing logic
            // 1. Validate input array done during creating

            // 2. Check authorization done

            // 3. Process each product (use the operation index to identify)
            if (operationIndex == 1) { // registerBatch
                require(batches[batchId].isRecalled == false, "Batch Recalled, operation cant be done"); //validate batch
                for (uint i = 0; i < batches[batchId].id.length; i++) {
                    //Product memory product = products[batches[batchId].id[i]];
                    registerProduct(batches[batchId].name[i], batches[batchId].description[i]);
                }
            } else if (operationIndex == 2) { // transferBatch
                require(batches[batchId].isRecalled == false, "Batch Recalled, operation cant be done"); //validate batch
                for (uint i = 0; i < batches[batchId].id.length; i++) {
                    transferProductOwnership(batches[batchId].id[i], newOwner);
                }
            } else if (operationIndex == 3) { // recallBatch
                require(batches[batchId].isRecalled == false, "Batch already recalled"); //validate batch
                for (uint i = 0; i < batches[batchId].id.length; i++) {
                    recallProduct(batches[batchId].id[i], reasons); //Set recall status done
                }
                recallBatch(batchId, reasons);
            } else {
                revert("Invalid operation");
            }
            // 4. Optimize gas usage
            // 5. Emit batch event
        emit BatchProcessed(batchId, batches[batchId].operation);
    }
}
