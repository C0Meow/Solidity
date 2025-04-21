// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IGameSwapToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function stakedBalances(address account) external view returns (uint256);
    function burn(uint256 amount) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function STAKER_ROLE() external view returns (bytes32);
    function totalSupply() external view returns (uint256);
}

contract GameSwapDAO is AccessControl, ReentrancyGuard {
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
    
    IGameSwapToken public gameToken;
    
    // Proposal Management
    uint256 public proposalCount;
    uint256 public minimumQuorum; // Percentage of total staked tokens needed for quorum (in basis points)
    uint256 public proposalThreshold; // Percentage of total token supply needed to create proposal (in basis points)
    uint256 public votingPeriod; // Duration in blocks
    uint256 public timeLock; // Time in seconds that must pass before a proposal can be executed
    
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        uint256 executionTimestamp;
        bytes callData;
        address target;
        mapping(address => bool) hasVoted;
        bool canceled;
    }
    
    mapping(uint256 => Proposal) public proposals;
    
    // Fee Distribution
    mapping(address => uint256) public lastDistribution;
    uint256 public totalDistributed;
    mapping(address => uint256) public pendingRewards;
    
    // Events
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, uint256 startBlock, uint256 endBlock);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, address executer);
    event ProposalCanceled(uint256 indexed proposalId);
    event FeesDistributed(uint256 amount, uint256 totalStakers);
    event RewardClaimed(address indexed staker, uint256 amount);
    event EmergencyAction(address indexed caller, string action, uint256 amount);
    event ProposalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event MinimumQuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event TimeLockUpdated(uint256 oldTimeLock, uint256 newTimeLock);
    
    constructor(
        address _gameTokenAddress,
        uint256 _minimumQuorum,
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        uint256 _timeLock
    ) {
        require(_gameTokenAddress != address(0), "GameSwapDAO: token address cannot be zero"); //0 address prevention
        require(_minimumQuorum > 0 && _minimumQuorum <= 10000, "GameSwapDAO: quorum must be between 1 and 10000 basis points"); 
        require(_proposalThreshold > 0 && _proposalThreshold <= 10000, "GameSwapDAO: threshold must be between 1 and 10000 basis points");
        
        gameToken = IGameSwapToken(_gameTokenAddress);
        minimumQuorum = _minimumQuorum; // e.g., 3000 for 30%
        proposalThreshold = _proposalThreshold; // e.g., 100 for 1%
        votingPeriod = _votingPeriod; // e.g., 7200 blocks (approx. 1 day)
        timeLock = _timeLock; // e.g., 86400 seconds (1 day)
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    function createProposal(//proposal for changes
        string memory description,
        bytes memory callData,
        address target
    ) external nonReentrant returns (uint256) {
        uint256 senderBalance = gameToken.balanceOf(msg.sender);
        uint256 totalSupply = gameToken.totalSupply();
        
        // Check if sender has enough tokens to create a proposal
        require(senderBalance * 10000 / totalSupply >= proposalThreshold, 
                "GameSwapDAO: insufficient tokens to create proposal");
        
        proposalCount++;
        uint256 proposalId = proposalCount; //auto increment Id
        
        Proposal storage newProposal = proposals[proposalId]; //creating a new proposal with auto increment Id
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.description = description;
        newProposal.startBlock = block.number;
        newProposal.endBlock = block.number + votingPeriod;
        newProposal.callData = callData;
        newProposal.target = target;
        
        emit ProposalCreated(proposalId, msg.sender, description, block.number, block.number + votingPeriod);
        
        return proposalId;
    }
    
    function castVote(uint256 proposalId, bool support) external nonReentrant {//let stakeholders to cast votes onto proposal
        Proposal storage proposal = proposals[proposalId];
        
        require(block.number >= proposal.startBlock, "GameSwapDAO: voting not started"); //cant vote before start
        require(block.number <= proposal.endBlock, "GameSwapDAO: voting ended"); //cant vote after ended
        require(!proposal.executed, "GameSwapDAO: proposal already executed"); //cant vote if proposal was already executed
        require(!proposal.canceled, "GameSwapDAO: proposal canceled"); //cant vote if proposal already canceled
        require(!proposal.hasVoted[msg.sender], "GameSwapDAO: already voted"); //cant double vote
        
        // Only stakers can vote
        require(gameToken.hasRole(gameToken.STAKER_ROLE(), msg.sender), "GameSwapDAO: only stakers can vote"); //require has the role staker (having stakes)
        
        uint256 votes = gameToken.stakedBalances(msg.sender); //amount of votes accords to the staked balance
        require(votes > 0, "GameSwapDAO: no staked tokens"); //cant vote with no votes
        
        if (support) {
            proposal.forVotes += votes; //upvotes
        } else {
            proposal.againstVotes += votes; //downvotes 
        }
        
        proposal.hasVoted[msg.sender] = true; //update users vote status
        
        _grantRole(VOTER_ROLE, msg.sender); //grant voter role after voted (for further upate and vote control)
        
        emit VoteCast(proposalId, msg.sender, support, votes);
    }
    
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(block.number > proposal.endBlock, "GameSwapDAO: voting period not ended"); //cant execute before vote end
        require(!proposal.executed, "GameSwapDAO: already executed"); //cant execute the same proposal twice
        require(!proposal.canceled, "GameSwapDAO: proposal canceled"); //cant execute a canceled peoposal
        
        // Calculate the total staked tokens - get this from the token contract
        uint256 totalStakedSupply = gameToken.balanceOf(address(this));
        require(totalStakedSupply > 0, "GameSwapDAO: no tokens staked");
        
        // Check if quorum is reached
        require((proposal.forVotes + proposal.againstVotes) * 10000 / totalStakedSupply >= minimumQuorum, 
                "GameSwapDAO: quorum not reached");
        
        // Check if proposal passed
        require(proposal.forVotes > proposal.againstVotes, "GameSwapDAO: proposal rejected");
        
        // Check if timelock has passed
        if (proposal.executionTimestamp == 0) {
            proposal.executionTimestamp = block.timestamp;
            return; // Start the timelock
        }
        
        require(block.timestamp >= proposal.executionTimestamp + timeLock, 
                "GameSwapDAO: timelock not satisfied");
        
        // Execute the proposal
        proposal.executed = true;
        
        (bool success, ) = proposal.target.call(proposal.callData); //execute the callData 
        require(success, "GameSwapDAO: execution failed");
        
        emit ProposalExecuted(proposalId, msg.sender);
    }
    
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.proposer == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
                "GameSwapDAO: only proposer or admin can cancel"); //role limitation, cant cancel the proposal if not the proposer or admin
        require(!proposal.executed, "GameSwapDAO: already executed"); //cant cancel an executed proposal   
        require(!proposal.canceled, "GameSwapDAO: already canceled"); //cant double cancel a proposal
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId);
    }
    
    function distributeFees() external nonReentrant {
        require(hasRole(MARKETPLACE_ROLE, msg.sender), "GameSwapDAO: caller is not marketplace");
        
        // Logic to distribute fees to stakers
        // For simplicity, let's assume a proportional distribution based on staked amounts
        
        // Count how many tokens we have to distribute
        uint256 feeAmount = gameToken.balanceOf(address(this));
        
        // Track the distributed amount
        totalDistributed += feeAmount;
        
        emit FeesDistributed(feeAmount, 0); // Replace 0 with actual count of stakers
    }
    
    function emergencyWithdraw(uint256 amount) external nonReentrant {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        require(amount <= address(this).balance, "GameSwapDAO: insufficient balance");
        
        payable(msg.sender).transfer(amount);
        
        emit EmergencyAction(msg.sender, "emergencyWithdraw", amount);
    }
    
    function emergencyBurn(uint256 amount) external nonReentrant {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        
        gameToken.burn(amount);
        
        emit EmergencyAction(msg.sender, "emergencyBurn", amount);
    }
    
    function setProposalThreshold(uint256 _proposalThreshold) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        require(_proposalThreshold > 0 && _proposalThreshold <= 10000, "GameSwapDAO: invalid threshold");
        
        uint256 oldThreshold = proposalThreshold;
        proposalThreshold = _proposalThreshold;
        
        emit ProposalThresholdUpdated(oldThreshold, _proposalThreshold);
    }
    
    function setMinimumQuorum(uint256 _minimumQuorum) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        require(_minimumQuorum > 0 && _minimumQuorum <= 10000, "GameSwapDAO: invalid quorum");
        
        uint256 oldQuorum = minimumQuorum;
        minimumQuorum = _minimumQuorum;
        
        emit MinimumQuorumUpdated(oldQuorum, _minimumQuorum);
    }
    
    function setVotingPeriod(uint256 _votingPeriod) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        require(_votingPeriod > 0, "GameSwapDAO: invalid voting period");
        
        uint256 oldPeriod = votingPeriod;
        votingPeriod = _votingPeriod;
        
        emit VotingPeriodUpdated(oldPeriod, _votingPeriod);
    }
    
    function setTimeLock(uint256 _timeLock) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GameSwapDAO: caller is not admin");
        
        uint256 oldTimeLock = timeLock;
        timeLock = _timeLock;
        
        emit TimeLockUpdated(oldTimeLock, _timeLock);
    }
    
    // Add receive function to accept ETH
    receive() external payable {}
    
    // Add fallback function as well for safety
    fallback() external payable {}
} 
