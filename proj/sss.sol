// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GameSwapToken is ERC20, AccessControl, ReentrancyGuard {
    //Role identifier for DAO access
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    //Role identifier for token stakers
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    // Token constants
    //Initial token supply (100 million)
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18; // 100 million tokens
    //Minimum tokens required to create a proposal (1% of supply)
    uint256 public constant PROPOSAL_THRESHOLD = 1000000 * 10**18; // 1 million tokens

    // Staking data
    //Mapping of user addresses to their staked token amounts
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public stakingTimestamp;

    // Events
    //Emitted when tokens are staked
    event Staked(address indexed user, uint256 amount);
    //Emitted when tokens are unstaked
    event Unstaked(address indexed user, uint256 amount);
    //Emitted when tokens are burned
    event Burned(address indexed from, uint256 amount);

    address public owner;

    constructor() ERC20("GameSwap Token", "GST") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DAO_ROLE, msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
        owner = msg.sender;
    }

    //Restricts function access to DAO contract
    modifier onlyDAO() {
        require(hasRole(DAO_ROLE, msg.sender), "GameSwapToken: caller is not the DAO");
        _;
    }
    
    function stake(uint256 amount) external nonReentrant { //stake the token, get the staker role for create proposal and cast votes
        require(amount > 0, "GameSwapToken: amount must be greater than 0"); //0 amount prevention
        require(balanceOf(msg.sender) >= amount, "GameSwapToken: insufficient balance"); //cant stake more than user's maximum balance

        _transfer(msg.sender, address(this), amount); //interact
        stakedBalances[msg.sender] += amount; //updating status: staking
        stakingTimestamp[msg.sender] = block.timestamp; //update staking time
        
        _grantRole(STAKER_ROLE, msg.sender); //grant the staker role for later casting vote and proposal creation
        
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "GameSwapToken: amount must be greater than 0");
        require(stakedBalances[msg.sender] >= amount, "GameSwapToken: insufficient staked balance");

        stakedBalances[msg.sender] -= amount; //update status: remove staking balance
        _transfer(address(this), msg.sender, amount); //interact
        
        if (stakedBalances[msg.sender] == 0) {
            _revokeRole(STAKER_ROLE, msg.sender); //if no more staking, remove staker role
        }
        
        emit Unstaked(msg.sender, amount);
    }

    function burn(uint256 amount) external nonReentrant {
        require(amount > 0, "GameSwapToken: amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "GameSwapToken: insufficient balance");

        _burn(msg.sender, amount); //burn tokens to keep the coin stable
        emit Burned(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyDAO nonReentrant {
        require(amount > 0, "GameSwapToken: amount must be greater than 0"); //0 amount prevention
        require(balanceOf(account) >= amount, "GameSwapToken: insufficient balance"); //cant burn more than what the account have

        _burn(account, amount);
        emit Burned(account, amount);
    }

    function getStakedBalance(address account) external view returns (uint256) {
        return stakedBalances[account];
    }

    function getStakingTimestamp(address account) external view returns (uint256) {
        return stakingTimestamp[account];
    }

    function hasProposalThreshold(address account) external view returns (bool) {
        return balanceOf(account) >= PROPOSAL_THRESHOLD;
    }
} 


//(part 1 start) GameSwapToken: Transfer token
//Transfer to acc2 (NFT owner): 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 10000000000000000000000000
//                                    acc2 address                        , 10mil token
//Transfer to acc3(NFT buyer): 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db, 12000000000000000000000000
//                                    acc3 address                        , 12mil token
//(part 1 finished)

//(part 2 start) GameSwapToken: Stake token (for creating proposal and castVotes)
//Stake (acc2): 2000000000000000000000000
//                 stake balance
//check balanceOf acc2: 8000000000000000000000000 8mil from (10-2)mil
//Stake (acc3): 2000000000000000000000000
//                 stake balance
//(part 2 finished)

//(part 3 start) GameItemsNFT: Mint NFT
//addsupportedgames : CryptoQuest
//minter role : 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
//to account1: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
//mint to account2 from account1: 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, CryptoQuest, Sword, 8, 10, true, https://gameswap.com/metadata/sword.json
//OwnerOf(1): should be acc2 (0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2)
//(part 3 finished)

//(part 4 start) GameSwapMarketPlace: Create and execute orders
//GameItemsNFT.setApprovalForAll(GameSwapMarketplace.address, true)  
//create orders (acc2)item owner: 1, 100000000000000000000, CryptoQuest, Sword
//                                id,         price       , gameId     , item type 
//(acc3) GameSwapToken.approve(GameSwapMarketplace.address, "100000000000000000000") → move token to market place
//(acc3) fillOrder:    1
//           orderid
//go to GameItemsNFT
//Check OwnerOf item id 1 and balanceOf marketplace (should be acc3 and 0 coz collected)
//(part 4 finsihed) 

//(part 5 start) GameSwapDao: Create Proposal of changeing percentage of marketplace order transaction fee
//(acc2, a staker) createProposal: Increase fees to 5, 0x37a0f0f800000000000000000000000000000000000000000000000000000000000001f4, 0x50227021f746AFEc12b167a7c520a1Fe1938dAff
//                                      description,              Calldata of setFeePercentage(500)                              ,    MarketPlace address
//(part 5 finished) Stay

//(part 6 start) GameSwapDao: Execute proposal
//(acc3, also a staker) castVote:      1    , true
//                                proposalId, upvote
//(part 6 finished)

//(part 7 start) GameSwapDao: Distribute fee to DAO
//(acc1)grantRole: 0x0ea61da3a8a09ad801432653699f8c1860b1ae9d2ea4a141fadfd63227717bc8, 0xaE7A2AB9883E1A4add3900c910F95eB90D31a323
//                            marketplaceRole                                  ,    marketplace address
//(acc1) GameSwapToken.transfer to transfer 5000000000000000000 token to marketplace address
//Go to GameSwapMarketPlace
//GameSwapMarketPlace.distributeFees()
//GameSwapToken.balanceOf(GameSwapDAO.address) Should return "5000000000000000000", 0x5171e2d76B3D114e06712320D5c1534cB0107455
//(part 7 finished)
