// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8;

import {Test} from "forge-std/Test.sol";
import {DeploySC} from "../script/DeploySC.s.sol";
import {CoinEngine} from "../src/CoinEngine.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";


contract SCEngine is Test {
    CoinEngine ce ; 
    StableCoin sc;
    HelperConfig config;

    address weth;
    address ethPriceFeed;
    address user = makeAddr("USER");
    uint256 amountCollateral = 10 ether;

    function setUp() public {
       DeploySC deployer = new DeploySC();
       (sc,ce,config) = deployer.run();
       (ethPriceFeed,,weth,,) = config.activeNetworkConfig();
    }

 function testGetUsdValue() public view {
    uint256 ethAmount = 1 ether;
    // 1 ETH = $2000, with 18 decimals precision
    uint256 expectedUsd = 2000e18;
    
    uint256 actualUsd = ce.getValueUSD(weth, ethAmount);
    assertEq(actualUsd, expectedUsd, "USD value incorrect");
}

function testRevertIfCollateralIsZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(ce),amountCollateral);

    vm.expectRevert(CoinEngine.CoinEngine_AmountShouldMoreThanZero.selector);
    ce.depositCollateral(weth, 0);
    vm.stopPrank();
}
    
}