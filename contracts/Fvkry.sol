// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Fvkry is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct Lock {
        address token;
        uint256 amount;
        uint256 lockEndTime;
        uint8 vault;
        bool withdrawn;
        bool isNative;
    }

    mapping  (address => Lock[]) public userLockedAssets;

    //Events
    event AssetLocked(address indexed _token, uint256 amount, uint8 vault,uint256 lockEndTime);
    event AssetTransfered(address indexed  _token, uint256 amount, uint8 vault);

    constructor() Ownable(msg.sender) {}

    //Lock ETH
    function lockETH(uint8 _vault, uint256 _lockperiod) external payable nonReentrant {
        require(msg.value > 0, "ETH to lock must a value greater than 0");
        require(_lockperiod > 0, "The lockperiod must be greater then zero");

        // Create lock entry for ETH
        userLockedAssets[msg.sender].push(Lock({
            token: address(0), 
            amount: msg.value,  
            lockEndTime: block.timestamp + _lockperiod,
            vault: _vault,    
            withdrawn: false,   
            isNative: true  
        }));      
        
        emit AssetLocked(address(0), msg.value, _vault, block.timestamp + _lockperiod);
    }

    //Lock ERC20 Tokens
    function lockToken (IERC20 _token, uint256 _amount, uint8 _vault, uint256 _lockperiod) external nonReentrant {
        require(address(_token) != address(0), "Must provide a valid token address");
        require(_amount > 0, "Token amount must be greater then zero");
        require(_lockperiod > 0, "The lockperiod must be greater then zero");

        uint256 _tokenBalance = _token.balanceOf(msg.sender);
        require (_amount >= _tokenBalance, "Not enough tokens to lock");

        // Transfer tokens from user to contract
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        // Create lock entry for Tokens 
        userLockedAssets[msg.sender].push(Lock({
            token: address(_token), 
            amount: _amount,  
            lockEndTime: block.timestamp + _lockperiod,
            vault: _vault,    
            withdrawn: false,   
            isNative: false  
        }));

        emit AssetLocked(address(_token), _amount, _vault, block.timestamp + _lockperiod);
    }

    //Withdraw Assets
    function transferAsset(uint256 _assetId, uint256 _amount, uint8 _vault) external  nonReentrant {
        require(_assetId < userLockedAssets[msg.sender].length, "The specified asset ID is invalid.");
        
        Lock storage lock = userLockedAssets[msg.sender][_assetId];

        require(!lock.withdrawn,"Assets have already been withdrawn!");
        require(block.timestamp > lock.lockEndTime, "The lock period has not yet expired!");

        uint256  updateBalance = lock.amount - _amount;
        require (updateBalance >= 0,"Not enough assets to withdraw!");

        //mark as withdrawn
        if(updateBalance == 0) {
            userLockedAssets[msg.sender][_assetId].withdrawn = true;
        } 

        //update balance  
        userLockedAssets[msg.sender][_assetId].amount = updateBalance;    

        if(lock.isNative) {
            // Transfer ETH
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Transfer ERC20 tokens
            IERC20(lock.token).safeTransfer(msg.sender, _amount);
        }

        emit AssetTransfered(address(lock.token), _amount , _vault);
    }

}