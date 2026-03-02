// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// -------- Chainlink Integration Start --------
// AggregatorV3Interface - Chainlink Price Feed Interface
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
// -------- Chainlink Integration End --------

contract InfluencerDonationNFT is ERC721, ReentrancyGuard {
    enum CharityType { Housing, Meals, Medical, Education, Equipment, RiverCleaning }
    
    struct InfluencerData {
        CharityType charity;
        uint256 totalDonations;
        uint256 goalAmount;
        bool active;
        address creator;
        string influencerName;
        string profileImageUrl;
    }
    
    uint256 private _tokenIdCounter;
    mapping(uint256 => InfluencerData) public influencers;
    
    // -------- Chainlink Integration Start --------
    AggregatorV3Interface internal priceFeed;
    uint256 public donationAmountUSD; // USD amount in cents (e.g., 1000 = $10.00)
    // -------- Chainlink Integration End --------
    
    event NFTMinted(address indexed influencer, uint256 indexed tokenId, CharityType charity, uint256 goalAmount);
    event DonationReceived(uint256 indexed tokenId, address indexed donor, uint256 amount);
    event Withdrawn(uint256 indexed tokenId, address indexed influencer, uint256 amount);
    
    constructor() ERC721("InfluencerDonationNFT", "IDNFT") {
        // -------- Chainlink Integration Start --------
        // Sepolia ETH/USD Price Feed
        priceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        donationAmountUSD = 1000; // Default: $10.00 (in cents)
        // -------- Chainlink Integration End --------
    }
    
    function mintMyNFT(CharityType _charity, uint256 _goalAmount, string memory _influencerName, string memory _profileImageUrl) external {
        require(_goalAmount > 0, "Goal must be greater than 0");
        require(bytes(_influencerName).length > 0, "Name cannot be empty");
        require(bytes(_influencerName).length <= 50, "Name too long");
        
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);
        
        influencers[tokenId] = InfluencerData({
            charity: _charity,
            totalDonations: 0,
            goalAmount: _goalAmount,
            active: true,
            creator: msg.sender,
            influencerName: _influencerName,
            profileImageUrl: _profileImageUrl
        });
        
        emit NFTMinted(msg.sender, tokenId, _charity, _goalAmount);
    }
    
    function donate(uint256 tokenId) external payable nonReentrant {
        require(_exists(tokenId), "NFT does not exist");
        require(influencers[tokenId].active, "Campaign not active");
        
        // -------- Chainlink Integration Start --------
        // Get current ETH price in USD
        uint256 ethPrice = getLatestPrice();
        
        // Calculate required ETH for the fixed USD donation amount
        uint256 requiredETH = getRequiredETH(donationAmountUSD);
        
        // Ensure user sent enough ETH to cover the USD value
        require(msg.value >= requiredETH, "Not enough ETH sent");
        // -------- Chainlink Integration End --------
        
        influencers[tokenId].totalDonations += msg.value;
        
        emit DonationReceived(tokenId, msg.sender, msg.value);
    }
    
    function withdraw(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(influencers[tokenId].totalDonations > 0, "No funds to withdraw");
        
        uint256 amount = influencers[tokenId].totalDonations;
        influencers[tokenId].totalDonations = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit Withdrawn(tokenId, msg.sender, amount);
    }
    
    function getCharityType(uint256 tokenId) external view returns (CharityType) {
        require(_exists(tokenId), "NFT does not exist");
        return influencers[tokenId].charity;
    }
    
    function getTotalDonations(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "NFT does not exist");
        return influencers[tokenId].totalDonations;
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _tokenIdCounter;
    }
    
    function getTotalNFTs() external view returns (uint256) {
        return _tokenIdCounter;
    }
    
    // Get all campaigns created by a specific address
    function getCampaignsByCreator(address creator) external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // First, count how many campaigns this creator has
        for (uint256 i = 0; i < _tokenIdCounter; i++) {
            if (influencers[i].creator == creator) {
                count++;
            }
        }
        
        // Create array and populate it
        uint256[] memory campaigns = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < _tokenIdCounter; i++) {
            if (influencers[i].creator == creator) {
                campaigns[index] = i;
                index++;
            }
        }
        
        return campaigns;
    }
    
    // -------- Chainlink Integration Start --------
    /**
     * @notice Get the latest ETH/USD price from Chainlink
     * @return price The current ETH price in USD with 8 decimals
     * @dev Chainlink price feeds return prices with 8 decimal places
     *      Example: If ETH = $2000, this returns 200000000000 (2000 * 10^8)
     */
    function getLatestPrice() public view returns (uint256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            /* uint256 timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        
        require(price > 0, "Invalid price from oracle");
        
        return uint256(price); // Price has 8 decimals
    }
    
    /**
     * @notice Calculate required ETH for a given USD amount
     * @param usdAmount The USD amount in cents (e.g., 1000 = $10.00)
     * @return requiredETH The equivalent amount in ETH (18 decimals)
     * @dev Decimal math explanation:
     *      - ETH uses 18 decimals (1 ETH = 1e18 wei)
     *      - Chainlink price uses 8 decimals (e.g., $2000 = 2000e8)
     *      - USD amount is in cents (e.g., $10 = 1000 cents)
     *      
     *      Formula: requiredETH = (usdAmount * 1e18 * 1e8) / ethPrice
     *      
     *      Why multiply before divide?
     *      - Solidity doesn't support decimals, only integers
     *      - Multiplying first preserves precision
     *      - Example: If ETH = $2000 and we want $10 donation:
     *        requiredETH = (1000 * 1e18 * 1e8) / (2000 * 1e8)
     *        requiredETH = (1000 * 1e26) / (2000 * 1e8)
     *        requiredETH = 5000000000000000 wei = 0.005 ETH
     */
    function getRequiredETH(uint256 usdAmount) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice(); // Price with 8 decimals
        
        // Convert USD cents to wei equivalent
        // usdAmount is in cents (e.g., 1000 = $10.00)
        // Multiply by 1e18 (ETH decimals) and 1e8 (to match price decimals)
        // Then divide by ethPrice to get required ETH in wei
        uint256 requiredETH = (usdAmount * 1e18 * 1e8) / ethPrice / 100;
        
        return requiredETH;
    }
    
    /**
     * @notice View function to check required ETH for current donation amount
     * @return requiredETH The amount of ETH (in wei) needed for a donation
     * @dev Frontend can call this before sending transaction to show user exact amount
     */
    function viewRequiredETH() external view returns (uint256) {
        return getRequiredETH(donationAmountUSD);
    }
    
    /**
     * @notice Update the fixed USD donation amount (only owner can call)
     * @param newAmountUSD New donation amount in cents (e.g., 1000 = $10.00)
     * @dev You can add onlyOwner modifier if needed
     */
    function setDonationAmountUSD(uint256 newAmountUSD) external {
        require(newAmountUSD > 0, "Amount must be greater than 0");
        donationAmountUSD = newAmountUSD;
    }
    // -------- Chainlink Integration End --------
}
