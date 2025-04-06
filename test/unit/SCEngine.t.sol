// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8;

import {Test} from "forge-std/Test.sol";
import {DeploySC} from "script/DeploySC.s.sol";
import {CoinEngine} from "src/CoinEngine.sol";
import {StableCoin} from "src/StableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract SCEngine is Test {
    CoinEngine ce;
    StableCoin sc;
    HelperConfig config;

    address weth;
    address ethPriceFeed;
    address btcPriceFeed;
    address constant USER = address(1);
    uint256 constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        DeploySC deployer = new DeploySC();
        (sc, ce, config) = deployer.run();
        (ethPriceFeed,, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, 1000e18);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethPriceFeed);
        priceFeedAddresses.push(btcPriceFeed);
        vm.expectRevert(CoinEngine.CoinEngine_TokenAddressAndPriceFeedAddressLengthDontMatch.selector);
        new CoinEngine(tokenAddresses, priceFeedAddresses, address(sc));
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetTokenValueFromUSD() public view {
        uint256 amountSc = 100 ether; // 100e18
        uint256 expectEthValue = 0.05 ether;
        uint256 actualEthValue = ce.getTokenValueFromUSD(amountSc, weth);
        assertEq(expectEthValue, actualEthValue);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 1 ether;
        // 1 ETH = $2000, with 18 decimals precision
        uint256 expectedUsd = 2000e18;

        uint256 actualUsd = ce.getValueUSD(weth, ethAmount);
        assertEq(actualUsd, expectedUsd, "USD value incorrect");
    }

    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////
    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ce), AMOUNT_COLLATERAL);

        vm.expectRevert(CoinEngine.CoinEngine_AmountShouldMoreThanZero.selector);
        ce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock tempToken = new ERC20Mock("TESTToken", "TST", USER, 1000e18);
        vm.expectRevert(abi.encodeWithSelector(CoinEngine.CoinEngine_isAllowedToken.selector, address(tempToken)));
        ce.depositCollateral(address(tempToken), AMOUNT_COLLATERAL);
    }

    function testCanDepositeCollateralAndGetUSERInfo() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ce), AMOUNT_COLLATERAL);
        ce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        (uint256 totalSCMinted, uint256 collateralValueInUSD) = ce.getAccountInformation(USER);
        uint256 expectedTotalSCMinted = 0;
        uint256 expectedDepositedValueinUSD = ce.getTokenValueFromUSD(collateralValueInUSD, weth);
        vm.assertEq(expectedTotalSCMinted, totalSCMinted);
        vm.assertEq(expectedDepositedValueinUSD, AMOUNT_COLLATERAL);
    }
}
