// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Fvkry is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct LockAsset {
        address token;
        uint256 amount;
        uint256 lockEndTime;
        uint8 vault;
        bool withdrawn;
        bool isNative;
    }

    mapping  (address => LockAsset[]) public userLockedAssets;

    event LockedAsset(address indexed _token, uint256 indexed amount, uint8 vault,uint256 lockEndTime);

    constructor() Ownable(msg.sender) {}


}