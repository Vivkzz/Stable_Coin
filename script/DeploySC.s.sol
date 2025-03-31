// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {CoinEngine} from "../src/CoinEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function run() external {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerkey) =
            config.activeNetworkConfig();
        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerkey);
        StableCoin sc = new StableCoin();
        CoinEngine engine = new CoinEngine(tokenAddress, priceFeedAddress, address(sc));
        sc.transferOwnership(address(engine));
        vm.stopBroadcast();
    }
}
