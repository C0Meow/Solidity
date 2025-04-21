// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GameItemsNFT is ERC721URIStorage, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    struct GameItem {
        string gameId;
        string itemType;
        uint256 rarity;
        uint256 level;
        bool isCrossGame;
    }
    
    uint256 private _tokenIds;
    mapping(uint256 => GameItem) public gameItems;
    mapping(string => bool) public gameSupported;
    
    event ItemMinted(address indexed to, uint256 indexed tokenId, string gameId, string itemType);
    event BatchMinted(address indexed to, uint256[] tokenIds);
    event GameAdded(string gameId);
    event ItemUpdated(uint256 indexed tokenId, string gameId, string itemType);
    
    constructor() ERC721("GameSwap Items", "GSI") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "GameItemsNFT: caller is not a minter");
        _;
    }
    
    modifier onlyOracle() {
        require(hasRole(ORACLE_ROLE, msg.sender), "GameItemsNFT: caller is not an oracle");
        _;
    }
    
    function mintItem(
        address to,
        string memory gameId,
        string memory itemType,
        uint256 rarity,
        uint256 level,
        bool isCrossGame,
        string memory tokenURI
    ) public onlyMinter nonReentrant returns (uint256) {
        require(gameSupported[gameId], "GameItemsNFT: game not supported");
        
        return _mintItem(to, gameId, itemType, rarity, level, isCrossGame, tokenURI);
    }
    
    function _mintItem(
        address to,
        string memory gameId, 
        string memory itemType,
        uint256 rarity,
        uint256 level,
        bool isCrossGame,
        string memory tokenURI
    ) internal returns (uint256) {
        _tokenIds++;
        uint256 newItemId = _tokenIds;
        
        _mint(to, newItemId);
        _setTokenURI(newItemId, tokenURI);
        
        gameItems[newItemId] = GameItem({
            gameId: gameId,
            itemType: itemType,
            rarity: rarity,
            level: level,
            isCrossGame: isCrossGame
        });
        
        emit ItemMinted(to, newItemId, gameId, itemType);
        return newItemId;
    }
    
    function batchMintItems(
        address to,
        string[] memory gameIds,
        string[] memory itemTypes,
        uint256[] memory rarities,
        uint256[] memory levels,
        bool[] memory isCrossGames,
        string[] memory tokenURIs
    ) external onlyMinter nonReentrant returns (uint256[] memory) {
        require(
            gameIds.length == itemTypes.length &&
            itemTypes.length == rarities.length &&
            rarities.length == levels.length &&
            levels.length == isCrossGames.length &&
            isCrossGames.length == tokenURIs.length,
            "GameItemsNFT: array lengths mismatch"
        );
        
        uint256[] memory newItemIds = new uint256[](gameIds.length);
        
        for (uint256 i = 0; i < gameIds.length; i++) {
            require(gameSupported[gameIds[i]], "GameItemsNFT: game not supported");
            newItemIds[i] = _mintItem(
                to,
                gameIds[i],
                itemTypes[i],
                rarities[i],
                levels[i],
                isCrossGames[i],
                tokenURIs[i]
            );
        }
        
        emit BatchMinted(to, newItemIds);
        return newItemIds;
    }
    
    function addSupportedGame(string memory gameId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!gameSupported[gameId], "GameItemsNFT: game already supported");
        gameSupported[gameId] = true;
        emit GameAdded(gameId);
    }
    
    function updateItem(
        uint256 tokenId,
        string memory gameId,
        string memory itemType,
        uint256 rarity,
        uint256 level,
        bool isCrossGame
    ) external onlyOracle {
        require(ownerOf(tokenId) != address(0), "GameItemsNFT: item does not exist");
        require(gameSupported[gameId], "GameItemsNFT: game not supported");
        
        gameItems[tokenId] = GameItem({
            gameId: gameId,
            itemType: itemType,
            rarity: rarity,
            level: level,
            isCrossGame: isCrossGame
        });
        
        emit ItemUpdated(tokenId, gameId, itemType);
    }
    
    function getItem(uint256 tokenId) external view returns (GameItem memory) {
        require(ownerOf(tokenId) != address(0), "GameItemsNFT: item does not exist");
        return gameItems[tokenId];
    }
    
    function getItemProperties(uint256 tokenId) external view returns (string memory, string memory, uint256, uint256, bool) {
        require(ownerOf(tokenId) != address(0), "GameItemsNFT: item does not exist");
        GameItem memory item = gameItems[tokenId];
        return (item.gameId, item.itemType, item.rarity, item.level, item.isCrossGame);
    }
} 


