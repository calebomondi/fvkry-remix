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
        string title;
        bool withdrawn;
        bool isNative;
    }

    mapping  (address => mapping (uint8 => Lock[])) public userLockedAssets;

    //Events
    event AssetLocked(address indexed token, uint256 amount, string title, uint8 vault,uint256 lockEndTime, uint256 timestamp);
    event AssetTransfered(address indexed  token, uint256 amount, string title, uint8 vault, uint256 timestamp);
    event AssetAdded(address indexed token, uint256 amount, string title, uint8 vault, uint256 timestamp);
    event LockPeriodExtended(address indexed  token, uint8 vault, uint256 lockperiod, string title, uint256 timestamp);

    constructor() Ownable(msg.sender) {}

    //Lock ETH
    function lockETH(uint8 _vault, uint256 _lockperiod, string memory _title) external payable nonReentrant {
        require(msg.value > 0, "ETH to lock must a value greater than 0");
        require(_lockperiod >= 0, "The lockperiod must be greater then zero");

        // Create lock entry for ETH
        userLockedAssets[msg.sender][_vault].push(Lock({
            token: address(0), 
            amount: msg.value,  
            lockEndTime: block.timestamp + _lockperiod,
            title: _title,    
            withdrawn: false,   
            isNative: true  
        }));      
        
        emit AssetLocked(address(0), msg.value, _title, _vault, block.timestamp + _lockperiod, block.timestamp);
    }

    function addToLockedETH(uint8 _vault, uint32 _assetID) external payable  nonReentrant {
        require(msg.value > 0, "ETH to add to lock must be an amount greater than 0");

        //get current balance and add to it
        userLockedAssets[msg.sender][_vault][_assetID].amount += msg.value;

        emit AssetAdded(address(0), msg.value, userLockedAssets[msg.sender][_vault][_assetID].title, _vault, block.timestamp);
    }

    //Lock ERC20 Tokens
    function lockToken (IERC20 _token, uint256 _amount, uint8 _vault, uint256 _lockperiod, string memory _title) external nonReentrant {
        require(address(_token) != address(0), "Must provide a valid token address");
        require(_amount > 0, "Token amount must be greater then zero");
        require(_lockperiod > 0, "The lock period must be greater then zero");

        uint256 _tokenBalance = _token.balanceOf(msg.sender);
        require (_amount <= _tokenBalance, "Not enough tokens to lock");

        // Transfer tokens from user to contract
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        // Create lock entry for Tokens 
        userLockedAssets[msg.sender][_vault].push(Lock({
            token: address(_token), 
            amount: _amount,  
            lockEndTime: block.timestamp + _lockperiod,
            title: _title,    
            withdrawn: false,   
            isNative: false  
        }));

        emit AssetLocked(address(_token), _amount, _title, _vault, block.timestamp + _lockperiod, block.timestamp);
    }

    function addToLockedTokens(IERC20 _token, uint32 _assetID, uint256 _amount, uint8 _vault) external  nonReentrant {
        require(address(_token) != address(0), "Must provide a valid token address");
        require(_amount > 0, "Token amount must be greater then zero");

        //add to vault
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        //update locked tokens balance
        userLockedAssets[msg.sender][_vault][_assetID].amount += _amount;
        
        emit AssetAdded(address(_token), _amount, userLockedAssets[msg.sender][_vault][_assetID].title, _vault, block.timestamp);
    }

    //Withdraw Assets
    function transferAsset( uint32 _assetId,uint8 _vault, uint256 _amount) external  nonReentrant {
        require(_assetId < userLockedAssets[msg.sender][_vault].length, "The specified asset ID is invalid.");
        
        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetId];

        require(!lock.withdrawn,"Assets have already been withdrawn!");
        require(block.timestamp > lock.lockEndTime, "The lock period has not yet expired!");

        uint256  updateBalance = lock.amount - _amount;
        require (updateBalance >= 0,"Not enough assets to withdraw!");

        //mark as withdrawn
        if(updateBalance == 0) {
            userLockedAssets[msg.sender][_vault][_assetId].withdrawn = true;
        } 

        //update balance  
        userLockedAssets[msg.sender][_vault][_assetId].amount = updateBalance;    

        if(lock.isNative) {
            // Transfer ETH
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Transfer ERC20 tokens
            IERC20(lock.token).safeTransfer(msg.sender, _amount);
        }

        emit AssetTransfered(address(lock.token), _amount , lock.title, _vault, block.timestamp);
    }

    //view contract locked assets
    function getContractTokenBalance(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getContractETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    //Get User Locked Assets
    function getUserLocks(uint8 _vault) public view returns (Lock[] memory) {
        return userLockedAssets[msg.sender][_vault];
    }

    //extend lock period after expiry
    function extendLockPeriod(uint32 _assetID, uint8 _vault, uint256 _lockperiod) external  {
        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetID];

        require(_assetID < userLockedAssets[msg.sender][_vault].length, "The specified asset ID is invalid.");
        require(block.timestamp > lock.lockEndTime, "The lock period has not yet expired!");
        
        userLockedAssets[msg.sender][_vault][_assetID].lockEndTime = block.timestamp + _lockperiod;

        emit LockPeriodExtended(lock.token, _vault, _lockperiod, lock.title, block.timestamp);
    }

}