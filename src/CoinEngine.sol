// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions (CONSTRUCTOR , EXTERNAL , PUBLIC , PRIVATE , INTERNAL)

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8;

import {StableCoin} from "./StableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Coin Engine
 * @author Vivek Tanna
 *  This contract it the essential file for pegging our Stable coin 1SC = $1
 * ~Algorithmic Stable
 * ~Exogenously Collateral
 * ~Dollar Pegged
 *
 * Engine need to be overcollateral than total value of issued DSC
 * Total DSC issued < Total $ Collateral Backed Value in Engine
 *
 * @notice contract is core and handler of all the operation of minting , burning of SC, and  depositing , withdrawal of Collateral
 */
contract CoinEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error CoinEngine_AmountShouldMoreThanZero();
    error CoinEngine_isAllowedToken(address token);
    error CoinEngine_TransferFailed();
    error CoinEngine_HealthFactorBroken();
    error CoinEngine_TokenAddressAndPriceFeedAddressLengthDontMatch();
    error CoinEngine_HealtFactorIsGood();
    error CoinEngine_HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////

    ///////////////////
    // State Variables
    ///////////////////

    StableCoin private immutable i_sc;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /// @dev Mapping of token address to price feed address
    mapping(address tokenCollateralAddress => address priceFeed) private s_priceFeeds;
    /// @dev Mapping of Amount of token deposited by user
    mapping(address user => mapping(address tokenCollateralAddress => uint256 amount)) private s_collateralDeposited;
    /// @dev Mapping of Amount of SC token minted by user
    mapping(address user => uint256 amount) private s_scMinted;
    /// @dev using this to know how many token we are having (assuming we will declare it later externall pass it)
    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert CoinEngine_AmountShouldMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert CoinEngine_isAllowedToken(token);
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address scAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert CoinEngine_TokenAddressAndPriceFeedAddressLengthDontMatch();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_sc = StableCoin(scAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /**
     *
     * @param tokenCollateralAddress address of the token to be deposited
     * @param amountCollateral amount of the token to be deposited
     * @param amountToMint amount of the token to be minted
     * @notice This function is used to deposit collateral in the engine and mint SC in one go
     */
    function depositeCollateralAndMintSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintSc(amountToMint);
    }

    ///////////////////
    // Public Functions
    ///////////////////

    /// @dev This function is used to deposit collateral in the engine
    /// @param tokenCollateralAddress address of the token to be deposited
    /// @param amountCollateral amount of the token to be deposited
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert CoinEngine_TransferFailed();
        }
    }

    function mintSc(uint256 amountToMint) public nonReentrant moreThanZero(amountToMint) {
        s_scMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //  Burn you own SC.
    function burnSC(uint256 amount) external moreThanZero(amount) {
        _burnSc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // technically not needed to do this
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(uint256 debtToCover, address tokenCollateralAddress, address user) external {
        uint256 startingHealthFactor = _getUserHealthFactor(user);

        if (startingHealthFactor > MIN_HEALTH_FACTOR) {
            revert CoinEngine_HealtFactorIsGood();
        }
        uint256 tokenAmountToCoverFromDebt = getTokenValueFromUSD(debtToCover, tokenCollateralAddress);
        uint256 bonusCollateral = (tokenAmountToCoverFromDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(tokenCollateralAddress, tokenAmountToCoverFromDebt + bonusCollateral, user, msg.sender);
        _burnSc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getUserHealthFactor(user);

        // This condtional will not hit
        if (endingUserHealthFactor < startingHealthFactor) {
            revert CoinEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    /**
     *
     * @param amountScToBurn amount of SC to be burned
     * @param onBehalfOf address of the user on behalf of whom the SC is being burned
     * @param dscFrom address of user who is burning the SC
     * @notice This function is used to burn SC also during liquidation of another user
     *
     */
    function _burnSc(uint256 amountScToBurn, address onBehalfOf, address dscFrom) private {
        // this will auto revert if user balance is less than amount to burn in newer versions
        s_scMinted[onBehalfOf] -= amountScToBurn;
        bool success = i_sc.transferFrom(dscFrom, address(this), amountScToBurn);
        if (!success) {
            revert CoinEngine_TransferFailed();
        }
        i_sc.burn(amountScToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert CoinEngine_TransferFailed();
        }
    }

    function _getValueUSD(address tokenAddress, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = dataFeed.latestRoundData();
        // we can try this : price * amount / 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _getUserHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert CoinEngine_HealthFactorBroken();
        }
    }

    function _getUserHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalSCMinted, collateralValueInUSD);
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalSCMinted, uint256 collateralValueInUSD)
    {
        totalSCMinted = s_scMinted[user];
        collateralValueInUSD = _getAccountCollateralValue(user);
    }

    function _getAccountCollateralValue(address user) internal view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][tokenAddress];
            totalCollateralValueInUSD += _getValueUSD(tokenAddress, amount);
        }
        return totalCollateralValueInUSD;
    }

    function _calculateHealthFactor(uint256 totalSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalSCMinted == 0) return type(uint256).max;
        uint256 collateralThresold = (collateralValueInUSD * LIQUIDATION_THRESOLD) / LIQUIDATION_PRECISION;
        return (collateralThresold * PRECISION) / totalSCMinted;
    }

    /////////////////////////////////////////////
    // External & Public View & Pure Functions
    /////////////////////////////////////////////
    function getTokenValueFromUSD(uint256 amountSC, address tokenAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((amountSC * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getValueUSD(address tokenAddress, uint256 amount) external view returns (uint256) {
        return _getValueUSD(tokenAddress, amount);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalSCMinted, uint256 collateralValueInUSD)
    {
        (totalSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }
}
