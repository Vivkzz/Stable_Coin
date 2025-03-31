// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8;

/**
 * @title StableCoin
 * @author Vivek Tanna
 * It is Exogenous algorithmic pegged stable coin
 * This contract ownership transfered to DSCEngine
 *
 */
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StableCoin is ERC20Burnable, Ownable {
    error StableCoin_NotZeroAddress();
    error StableCoin_AmountMustBeMoreThanZero();
    error StableCoin_BurnAmountShouldExceedsBalance();

    constructor() ERC20("StableCoin", "SC") Ownable(msg.sender) {}

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableCoin_AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin_AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableCoin_BurnAmountShouldExceedsBalance();
        }
        super.burn(_amount);
    }
}
