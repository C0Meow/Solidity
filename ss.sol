 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

 /**
 * @title KYC Registry Contract
 * @dev A simple KYC (Know Your Customer) registry system on blockchain
 * Allows authorized verifiers to update customer KYC status and details
 */
contract KYCRegistry {
    // Structure to store customer KYC information
    struct Customer {
        bool kycStatus;      // Current KYC verification status
        RiskLevel kycLevel;    // Level of KYC verification (can represent different tiers)
        uint256 lastUpdated; // Timestamp of last KYC update
        address verifier;    // Address of the verifier who last updated the KYC
        uint256 riskScore;
        uint256 lastReviewDate;
        bool isActive; //Profil status
        //mapping(string => bool) documents;
    }

    enum RiskLevel {
        LOW,        
        MEDIUM,     
        HIGH       
    }
    
    // Mapping to store customer KYC details, indexed by customer address
    mapping(address => Customer) public customers;
    // Mapping to track authorized verifiers
    mapping(address => bool) public verifiers;
    // user's address -> document hash -> isVerified
    mapping(address => mapping(string => bool)) public verifiedDocuments;

    // Contract owner address
    address public owner;
    
    // Events to log important contract actions

    event KYCUpdated(address indexed customer, bool status, RiskLevel level, uint256 riskScore, bool isActive);
    event KYCCreated(address indexed Customer, uint256 riskScore);
    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);
    event DocumentVerified(address indexed customer, string documentHash);
    event RiskScoreUpdated(address indexed customer, uint256 newRiskScore, uint256 updateTime);
    event ProfileStatusChanged(address indexed customer, bool boolean);
    event ReviewsRequired(address indexed customer, RiskLevel r);
    
    // Modifier to restrict functions to contract owner only
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    // Modifier to restrict functions to authorized verifiers only
    modifier onlyVerifier() {
        require(verifiers[msg.sender], "Only authorized verifiers can perform this action");
        _;
    }
    
    /**
     * @dev Constructor sets the contract deployer as owner
     */
    constructor() {
        owner = msg.sender; //Owner address automatically set to deployer
    }
    
    /**
     * @dev Adds a new authorized verifier
     * @param _verifier Address of the verifier to be added
     */
    function addVerifier(address _verifier) public onlyOwner {
        verifiers[_verifier] = true;
        emit VerifierAdded(_verifier);
    }
    
    /**
     * @dev Removes an authorized verifier
     * @param _verifier Address of the verifier to be removed
     */
    function removeVerifier(address _verifier) public onlyOwner {
        verifiers[_verifier] = false;
        emit VerifierRemoved(_verifier);
    }
    
    /**
     * @dev Updates KYC status and details for a customer
     * @param _customer Address of the customer
     */
    function createKYC(address _customer, uint256 _riskScore) public onlyVerifier {
        
        customers[_customer] = Customer({
            kycStatus: false,
            kycLevel: getRiskLevel(_customer),
            lastUpdated: block.timestamp,
            verifier: msg.sender,
            riskScore:_riskScore,
            isActive: false,
            lastReviewDate: block.timestamp
        });

        emit KYCCreated(_customer, _riskScore);
    }

    /**
     * @dev Updates KYC status and details for a customer
     * @param _customer Address of the customer
     */
    function updateKYC(address _customer, bool _status, bool _isActive) public onlyVerifier {
        
        customers[_customer] = Customer({
            kycStatus: _status,
            kycLevel: getRiskLevel(_customer),
            lastUpdated: block.timestamp,
            verifier: msg.sender,
            riskScore: customers[_customer].riskScore,
            isActive: _isActive,
            lastReviewDate: block.timestamp
        });

        emit KYCUpdated(_customer, _status, getRiskLevel(_customer), customers[_customer].riskScore, _isActive);
    }
    
    /**
     * @dev Retrieves KYC information for a customer
     * @param _customer Address of the customer
     * @return Customer's KYC status, level, last update timestamp, and verifier address
     */
    function getCustomerKYC(address _customer) public view returns (bool, RiskLevel, uint256, address, uint256, bool, uint256) {
        Customer memory customer = customers[_customer];
        return (
            customer.kycStatus,
            customer.kycLevel,
            customer.lastUpdated,
            customer.verifier,
            customer.riskScore,
            customer.isActive,
            customer.lastReviewDate
        );
    }
    

    function isDocumentVerified(address _customer, string memory _documentType) public view returns (bool) {
        return verifiedDocuments[_customer][_documentType];
    }

    function verifyDocument(address _customer, string memory _documentType) public onlyVerifier {
        verifiedDocuments[_customer][_documentType] = true;
        emit DocumentVerified(_customer, _documentType);
    }

    function updateRiskScore(address a, uint256 _riskScore) public onlyVerifier { //Risk score implementation
        require(customerExists(a), "Customer doesnt exists.");
        require(_riskScore <= 100, "Risk score must be between 0 and 100");
        require(_riskScore > 0, "Risk score must be between 0 and 100");
        Customer storage customer = customers[a];
        customer.riskScore = _riskScore;
        customer.lastReviewDate = block.timestamp;
        customer.kycLevel = getRiskLevel(a);
        emit RiskScoreUpdated(a, _riskScore, block.timestamp);
    }

    function getRiskLevel(address _customer) public view returns (RiskLevel) { //Risk level 
        uint256 score = customers[_customer].riskScore;
        if (score < 30) {
            return RiskLevel.LOW;
        } else if (score <= 70) {
            return RiskLevel.MEDIUM;
        } else {
            return RiskLevel.HIGH;
        }
    }

    function customerExists(address a) public onlyVerifier view returns (bool)  {
        return customers[a].lastUpdated != 0;
    }

    function setProfileStatus(address a, bool b) public onlyVerifier {
        customers[a].isActive = b;
        emit ProfileStatusChanged(a, b);
    }

    function requiresReview(address a) public onlyVerifier returns (bool){
        if (getRiskLevel(a) == RiskLevel.LOW){
            return false;
        }
        else if (getRiskLevel(a) == RiskLevel.MEDIUM){
            emit ReviewsRequired(a, getRiskLevel(a));
            return true;
        }
        else {
            emit ReviewsRequired(a, getRiskLevel(a));
            return true;
        }
    }
}