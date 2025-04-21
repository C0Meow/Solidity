 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
 // Snapshot feature implemented manually (custom Snapshot struct used)
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

 /// @title VotingToken - Custom ERC20 Token with Snapshot-based voting support
contract VotingToken is ERC20, Ownable {
    /// @dev Snapshot structure to store block number and balances
    struct Snapshot {
        uint256 blockNumber;
        mapping(address => uint256) balances;
    }

    mapping(uint256 => Snapshot) public snapshots;  // snapshotId → Snapshot
    uint256 public currentSnapshotId;

    mapping(address => bool) public isTokenHolder; // To track unique holders
    address[] public tokenHolders;

    event TokensDistributed(address indexed to, uint256 amount);
    event SnapshotCreated(uint256 indexed snapshotId, uint256 blockNumber);

    constructor(uint256 initialSupply) ERC20("DAO Voting Token", "DVT") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);  //_mint(to, amount) is an internal function that comes from OpenZeppelin's ERC20 base contract implementation
        _addTokenHolder(msg.sender);
    }

    /// @dev Add address to list of token holders if not yet recorded
    function _addTokenHolder(address account) internal {
        if (!isTokenHolder[account] && account != address(0)) { //Checks if this address is NOT already a token holder
        //and Checks if this is a valid address (not the zero address)
            isTokenHolder[account] = true;
            tokenHolders.push(account);
        }
    }

    /// @notice Mint tokens and track holder
    function distributeTokens(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be positive");
        _mint(to, amount);
        _addTokenHolder(to);
        emit TokensDistributed(to, amount);
    }

    // Override transfer to track new token holders
    // Direct transfer - I'm sending my own tokens
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transfer(to, amount); //calling the parent contract's (ERC20) transfer function using super and storing the result in a success boolean.
        if (success) {
            _addTokenHolder(to);
        }
        return success;
    }

    // Approved transfer - I'm moving someone else's tokens
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (success) {
            _addTokenHolder(to);
        }
        return success;
    }

    /// @notice Create a snapshot of token balances at the current block
    function takeSnapshot() public returns (uint256) {
        currentSnapshotId++;
        snapshots[currentSnapshotId].blockNumber = block.number;

        //creating a snapshot of all token holder balances at a specific point in time.
        for (uint i = 0; i < tokenHolders.length; i++) { // Loop through all token holders
            address holder = tokenHolders[i];           // Get each holder's address
            uint256 balance = balanceOf(holder);        // Check their balance
            if (balance > 0) {
                snapshots[currentSnapshotId].balances[holder] = balance; // Record their balance
            }
        }

        emit SnapshotCreated(currentSnapshotId, block.number);
        return currentSnapshotId;
    }

    /// @notice Get historical balance from a snapshot
    function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        require(snapshotId > 0 && snapshotId <= currentSnapshotId, "Invalid snapshot id");
        return snapshots[snapshotId].balances[account];
    }

    /// @notice Return full list of token holders
    function getTokenHolders() public view returns (address[] memory) {
        return tokenHolders;
    }
}

/// @title cw11_DAOVoting - DAO Voting Smart Contract with Snapshot Voting and Delegation
contract cw11_DAOVoting is ReentrancyGuard { // Now you can use nonReentrant modifier
    VotingToken public votingToken;
    address public chairperson;

    uint256 public proposalCount;

    // Constants
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 10; //10% of total token holders need to participate in a vote for it to be considered valid.
    uint256 public constant MAJORITY_PERCENTAGE = 50;
    uint256 public constant MIN_TOKEN_REQUIREMENT = 1; // 1% of total supply to create a proposal

    /// @dev Proposal structure with snapshot ID for time-based vote accuracy
    struct Proposal {
        string description;
        uint256 voteCount; // Total aggregate votes received
        bool executed;
        uint256 deadline;
        uint256 snapshotId;
        mapping(address => uint256) votes; // voter → weight.  Shows who voted and how much
        bool exists; // whether a proposal has been properly created/initialized
    }

    /// @dev Voter structure with optional delegation
    struct Voter {
        bool voted;
        address delegate;
        uint256 proposalVoted;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(address => Voter) public voters;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed proposalId, string description, uint256 deadline);
    event Voted(address indexed voter, uint256 indexed proposalId, uint256 weight);
    event DelegatedVote(address indexed delegator, address indexed delegate);
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event DelegationRevoked(address indexed delegator);

    constructor(address _votingToken) {
        chairperson = msg.sender;
        votingToken = VotingToken(_votingToken); //"treat this address as a VotingToken contract.
    }

    modifier onlyChairperson() {
        require(msg.sender == chairperson, "Only chairperson allowed");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposals[proposalId].exists, "Proposal does not exist");
        _;
    }

    modifier proposalActive(uint256 proposalId) {
        require(block.timestamp < proposals[proposalId].deadline, "Voting period ended");
        _;
    }

    /// @notice Create a new proposal (only chairperson)
    function createProposal(string memory description) external onlyChairperson returns (uint256) {
        uint256 minTokens = (votingToken.totalSupply() * MIN_TOKEN_REQUIREMENT) / 100; //calculating the minimum number of tokens needed to create a proposal, expressed as a percentage of total token supply.
        require(votingToken.balanceOf(msg.sender) >= minTokens, "Insufficient tokens to create proposal");

        uint256 snapshotId = votingToken.takeSnapshot();

        proposalCount++;
        Proposal storage proposal = proposals[proposalCount];
        proposal.description = description;
        proposal.deadline = block.timestamp + VOTING_PERIOD;
        proposal.executed = false;
        proposal.exists = true;
        proposal.snapshotId = snapshotId;

        emit ProposalCreated(proposalCount, description, proposal.deadline);
        return proposalCount;
    }

    /// @notice Delegate voting power to another address
    function delegate(address to) external {
        Voter storage sender = voters[msg.sender]; //creating a reference to the voter's data structure in storage for the person calling the function.
        require(!sender.voted, "You already voted");
        require(to != msg.sender, "Self-delegation is not allowed");

        // Detect delegation loops
        address currentDelegate = to;
        while (voters[currentDelegate].delegate != address(0)) { //checking for delegation chains - it keeps looking up delegations until it finds someone who hasn't delegated their vote to anyone else.
            //address(0) is used as a default/null value to indicate "no delegation" 
            currentDelegate = voters[currentDelegate].delegate; //is updating who we're looking at in the delegation chain - moving to the next person in line.
            require(currentDelegate != msg.sender, "Found loop in delegation");
        }

        sender.delegate = to;
        emit DelegatedVote(msg.sender, to);
    }

    /// @notice Cast a vote (includes delegated votes at snapshot)
    function vote(uint256 proposalId, bool support) external 
        proposalExists(proposalId)  //modifier
        proposalActive(proposalId)  // modifier
        nonReentrant 
    {
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        Proposal storage proposal = proposals[proposalId];

        //checking how many tokens the voter had at the time the proposal was created (using a snapshot), 
        // not their current balance.
        uint256 directPower = votingToken.balanceOfAt(msg.sender, proposal.snapshotId);

        // Count delegated power (snapshot-based)
        uint256 delegatedPower = 0;
        for (uint i = 0; i < votingToken.getTokenHolders().length; i++) {
            address holder = votingToken.getTokenHolders()[i];
            if (voters[holder].delegate == msg.sender) {
                delegatedPower += votingToken.balanceOfAt(holder, proposal.snapshotId);
            }
        }

        // calculates a voter's total voting power by combining their own tokens (directPower) 
        // with any voting power delegated to them by others (delegatedPower).
        uint256 totalVotingPower = directPower + delegatedPower;        
        require(totalVotingPower > 0, "No voting power");

        if (support) {
            proposal.voteCount += totalVotingPower;
        }

        proposal.votes[msg.sender] = totalVotingPower;
        hasVoted[proposalId][msg.sender] = true;
        voters[msg.sender].voted = true;
        voters[msg.sender].proposalVoted = proposalId;

        emit Voted(msg.sender, proposalId, totalVotingPower);
    }

    /// @dev Internal: Pseudo-random selection from tied proposals
    function selectWinningProposal(uint256[] memory tiedProposals) internal view returns (uint256) {
        require(tiedProposals.length > 0, "No proposals provided");

        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            block.number,
            tiedProposals
        ))) % tiedProposals.length; //to adjust to the correct range of the random result

        return tiedProposals[randomIndex];
    }

    /// @notice Get list of proposals tied with highest votes and meet requirements
    function getTiedProposals() public view returns (uint256[] memory) {
        uint256 highestVotes = 0;
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].exists &&
                !proposals[i].executed &&
                block.timestamp > proposals[i].deadline &&
                hasQuorum(i) &&
                hasMajority(i)
            ) {
                if (proposals[i].voteCount > highestVotes) {
                    highestVotes = proposals[i].voteCount;
                }
            }
        }

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].exists &&
                !proposals[i].executed &&
                block.timestamp > proposals[i].deadline &&
                hasQuorum(i) &&
                hasMajority(i) &&
                proposals[i].voteCount == highestVotes
            ) {
                count++;
            }
        }

        uint256[] memory tiedProposals = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= proposalCount; i++) {
            if (
                proposals[i].exists &&
                !proposals[i].executed &&
                block.timestamp > proposals[i].deadline &&
                hasQuorum(i) &&
                hasMajority(i) &&
                proposals[i].voteCount == highestVotes
            ) {
                tiedProposals[index++] = i;
            }
        }

        return tiedProposals;
    }

    /// @notice Resolve tie by randomly selecting a winner
    function resolveTiedProposals() external onlyChairperson returns (uint256) {
        uint256[] memory tiedProposals = getTiedProposals();
        require(tiedProposals.length > 1, "No tie to resolve");

        uint256 winningProposal = selectWinningProposal(tiedProposals);

        for (uint256 i = 0; i < tiedProposals.length; i++) {
            if (tiedProposals[i] != winningProposal) {
                proposals[tiedProposals[i]].executed = false;
            }
        }

        return winningProposal;
    }

    /// @notice Execute a proposal if it meets quorum and majority after deadline
    function executeProposal(uint256 proposalId) external proposalExists(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(block.timestamp > proposal.deadline, "Voting still active");

        uint256 totalSupply = votingToken.totalSupply();
        uint256 quorumVotes = (totalSupply * QUORUM_PERCENTAGE) / 100;
        uint256 majorityVotes = (totalSupply * MAJORITY_PERCENTAGE) / 100;

        bool quorumReached = proposal.voteCount >= quorumVotes;
        bool majorityAchieved = proposal.voteCount >= majorityVotes;

        if (quorumReached && majorityAchieved) {
            proposal.executed = true;
            emit ProposalExecuted(proposalId, true);
        } else {
            emit ProposalExecuted(proposalId, false);
        }
    }

    // ---------------- Read Functions ----------------

    function getProposal(uint256 proposalId) external view proposalExists(proposalId)
        returns (string memory description, uint256 voteCount, bool executed, uint256 deadline, uint256 snapshotId) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.description,
            proposal.voteCount,
            proposal.executed,
            proposal.deadline,
            proposal.snapshotId
        );
    }

    function getVoter(address voterAddress) external view returns (bool voted, address delegateAddress, uint256 proposalVoted) {
        Voter storage voter = voters[voterAddress];
        return (voter.voted, voter.delegate, voter.proposalVoted);
    }

    function hasQuorum(uint256 proposalId) public view proposalExists(proposalId) returns (bool) {
        uint256 quorumVotes = (votingToken.totalSupply() * QUORUM_PERCENTAGE) / 100;
        return proposals[proposalId].voteCount >= quorumVotes;
    }

    function hasMajority(uint256 proposalId) public view proposalExists(proposalId) returns (bool) {
        uint256 majorityVotes = (votingToken.totalSupply() * MAJORITY_PERCENTAGE) / 100;
        return proposals[proposalId].voteCount >= majorityVotes;
    }

    /// @notice Get the delegation chain of a user (up to 10 levels)
    function getDelegationChain(address user) public view returns (address[] memory) {
        address[] memory chain = new address[](10); // Preallocate with max depth
        address current = user;
        uint j = 0;

        while (voters[current].delegate != address(0) && j < 10) {
            current = voters[current].delegate;
            chain[j] = current;
            j++;
        }

        // Resize to actual length
        address[] memory result = new address[](j);
        for (uint i = 0; i < j; i++) {
            result[i] = chain[i];
        }

        return result;
    }

    function revokeDelegation() public {
        require(voters[msg.sender].delegate != address(0), "No active delegation to revoke");
        require(!voters[msg.sender].voted, "Cannot revoke after voting");

        voters[msg.sender].delegate = address(0);
        emit DelegationRevoked(msg.sender);
    }


}
