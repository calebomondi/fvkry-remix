// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Fvkry is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    //constants
    uint256 private constant MAX_LOCKDURATION = 1096 * 24 * 60 * 60;
    uint8 private constant MAX_VAULTS = 5;
    uint8 private constant MAX_SUB_VAULTS = 100;

    //structs
    struct Lock {
        address token;
        uint256 amount;
        uint256 lockEndTime;
        string title;
        bool withdrawn;
        bool isNative;
    }

    struct TransacHist {
        address token;
        uint256 amount;
        string title;
        bool withdrawn;
        uint256 timestamp;
    }

    //Events
    event AssetLocked(address indexed token, uint256 amount, string title, uint8 vault,uint256 lockEndTime, uint256 timestamp);
    event AssetWithdrawn(address indexed  token, uint256 amount, string title, uint8 vault, uint256 timestamp);
    event AssetAdded(address indexed token, uint256 amount, string title, uint8 vault, uint256 timestamp);
    event LockPeriodExtended(address indexed  token, uint8 vault, uint256 lockperiod, string title, uint256 timestamp);
    //---
    event ContractPaused(uint256 timestamp);
    event ContractUnpaused(uint256 timestamp);
    event BlackListed(address indexed  token);
    event UnBlackListed(address indexed token);
    //---
    event VaultDeleted(uint8 vault, uint8 assetID, uint256 timestamp);
    event RenameVault(string newtitle, uint8 assetID, uint8 vault);
    event TransferAsset(address indexed token, uint256 amount, uint8 fromVault, uint8 fromAssetID, uint8 toVault, uint8 toAssetID);

    //state variables
    bool public paused;

    //mappings
    mapping (address => mapping (uint8 => Lock[])) public userLockedAssets;
    mapping (address => mapping (uint8 => TransacHist[])) public userTransactions;
    mapping (address => bool) public blackListedToken;

    constructor() Ownable(msg.sender) {
        paused = false;
    }

    //modifiers
    modifier validLockPeriod(uint256 _lockperiod) {
        require(_lockperiod > 0 && _lockperiod < MAX_LOCKDURATION, "Invalid Lock Period!");
        _;
    }

    modifier validVault(uint8 _vault) {
        require(_vault > 0 && _vault < 5, "Invalid Vault Number!");
        _;
    }

    modifier contractNotPaused() {
        require(!paused, "Contract Has Been Paused!");
        _;
    }

    //Lock ETH
    function lockETH(
        uint8 _vault, 
        uint256 _lockperiod, 
        string memory _title
    ) external payable nonReentrant contractNotPaused validVault(_vault) validLockPeriod(_lockperiod) {
        uint256 num_of_locks = userLockedAssets[msg.sender][_vault].length;
        require(num_of_locks < MAX_SUB_VAULTS, "Vault Is Full!");
        require(msg.value > 0, "ETH to lock must a value greater than 0!");
        require(bytes(_title).length > 0 && bytes(_title).length <= 100, "Invalid Title Length!");

        // Create lock entry for ETH
        userLockedAssets[msg.sender][_vault].push(Lock({
            token: address(0), 
            amount: msg.value,  
            lockEndTime: block.timestamp + _lockperiod,
            title: _title,    
            withdrawn: false,   
            isNative: true
        }));     

        //record transaction
        recordTransac(address(0), _vault, msg.value, _title, false);
        
        emit AssetLocked(address(0), msg.value, _title, _vault, block.timestamp + _lockperiod, block.timestamp);
    }

    function addToLockedETH(
        uint8 _vault, 
        uint32 _assetID) 
    external payable  nonReentrant contractNotPaused validVault(_vault) {
        require(msg.value > 0, "ETH to add to lock must be an amount greater than 0");
        require(_assetID < userLockedAssets[msg.sender][_vault].length, "Invalid Asset ID!");

        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetID];

        require(lock.lockEndTime > block.timestamp, "This Vault Is Open, Lock Before Adding!");

        //get current balance and add to it
        userLockedAssets[msg.sender][_vault][_assetID].amount += msg.value;

        //record transaction
        recordTransac(address(0), _vault, msg.value, lock.title, false);

        emit AssetAdded(address(0), msg.value, lock.title, _vault, block.timestamp);
    }

    //Lock ERC20 Tokens
    function lockToken (
        IERC20 _token, 
        uint256 _amount, 
        uint8 _vault, 
        uint256 _lockperiod, 
        string memory _title
    ) external nonReentrant contractNotPaused validVault(_vault) validLockPeriod(_lockperiod) {
        uint256 num_of_locks = userLockedAssets[msg.sender][_vault].length;
        require(num_of_locks < MAX_SUB_VAULTS, "Vault Is Full!");
        require(address(_token) != address(0), "Invalid Token Address!");
        require(!blackListedToken[address(_token)],"Token Has Been Blacklisted!");
        require(_amount > 0, "Amount Must Be Greater Then Zero!");
        require(bytes(_title).length > 0 && bytes(_title).length <= 100, "Invalid title length!");

        //check balance
        uint256 _tokenBalance = _token.balanceOf(msg.sender);
        require (_amount <= _tokenBalance, "Inadequate Tokens To Lock!");

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

        //record transaction
        recordTransac(address(_token), _vault, _amount, _title, false);

        emit AssetLocked(address(_token), _amount, _title, _vault, block.timestamp + _lockperiod, block.timestamp);
    }

    function addToLockedTokens(
        IERC20 _token, 
        uint32 _assetID, 
        uint256 _amount, 
        uint8 _vault
    ) external  nonReentrant contractNotPaused validVault(_vault) {
        require(address(_token) != address(0), "Invalid Token Address!");
        require(!blackListedToken[address(_token)],"Token Has Been Blacklisted!");
        require(_amount > 0, "Amount Must Be Greater Then Zero!");

        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetID];

        //check balance
        uint256 _tokenBalance = _token.balanceOf(msg.sender);
        require (_amount <= _tokenBalance, "Inadequate Tokens To Lock!");

        //add to vault
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        //update locked tokens balance
        userLockedAssets[msg.sender][_vault][_assetID].amount += _amount;

        //record transaction
        recordTransac(address(_token), _vault, _amount, lock.title, false);
        
        emit AssetAdded(address(_token), _amount, lock.title, _vault, block.timestamp);
    }

    //Withdraw Assets
    function withdrawAsset( 
        uint32 _assetId,
        uint8 _vault, 
        uint256 _amount, 
        bool _goalReachedByValue
    ) external  nonReentrant validVault(_vault) {
        require(_assetId < userLockedAssets[msg.sender][_vault].length, "Invalid Asset ID!");
        
        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetId];

        require(!lock.withdrawn,"Assets have already been withdrawn!");
        require(_amount <= lock.amount, "Not enough assets to withdraw!");
        require(block.timestamp > lock.lockEndTime || _goalReachedByValue, "The lock period has not yet expired and the value has not reached set goal!");

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

            recordTransac(address(0), _vault, _amount, lock.title, true);
        } else {
            // Transfer ERC20 tokens
            IERC20(lock.token).safeTransfer(msg.sender, _amount);

            recordTransac(address(lock.token), _vault, _amount, lock.title, true);
        }

        emit AssetWithdrawn(address(lock.token), _amount , lock.title, _vault, block.timestamp);
    }

    //record transaction
    function recordTransac(
        address _token, 
        uint8 _vault, 
        uint256 _amount, 
        string memory _title, 
        bool _withdraw
    ) internal {
        userTransactions[msg.sender][_vault].push(TransacHist({ 
            token: _token,     
            amount: _amount,  
            title: _title,    
            withdrawn: _withdraw,   
            timestamp: block.timestamp       
        }));
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
    function extendLockPeriod(
        uint32 _assetID, 
        uint8 _vault, 
        uint256 _lockperiod
    ) external {
        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetID];

        require(_assetID < userLockedAssets[msg.sender][_vault].length, "The specified asset ID is invalid.");
        require(block.timestamp > lock.lockEndTime, "The lock period has not yet expired!");
        
        userLockedAssets[msg.sender][_vault][_assetID].lockEndTime = block.timestamp + _lockperiod;

        emit LockPeriodExtended(lock.token, _vault, _lockperiod, lock.title, block.timestamp);
    }

    //emergencies executed by admin
    function pauseContract() external onlyOwner {
        require(!paused, "Contract Is Already Paused!");
        paused = true;
        emit ContractPaused(block.timestamp);
    }

    function unPauseContract() external  onlyOwner {
        require(paused,"Contract Is Already UnPaused!");
        paused = false;
        emit ContractUnpaused(block.timestamp);
    }

    function blackListToken(IERC20 _token) external  onlyOwner {
        require(!blackListedToken[address(_token)],"Token Already Blacklisted!");
        blackListedToken[address(_token)] = true;
        emit BlackListed(address(_token));
    }

    function unBlackListToken(IERC20 _token) external onlyOwner  {
        require(blackListedToken[address(_token)],"Token Is Not BlackListed!");
        blackListedToken[address(_token)] = false;
        emit UnBlackListed(address(_token));
    }

    //delete vault
    function deleteVault(uint8 _vault, uint8 _assetID) external  {
        require(_assetID < userLockedAssets[msg.sender][_vault].length, "Invalid Asset ID!");

        Lock storage lock = userLockedAssets[msg.sender][_vault][_assetID];
        require(block.timestamp > lock.lockEndTime,"Vault Lock Period Not Yet Expired!");
        require(lock.withdrawn, "Vault Not Empty!");

        //get last index
        uint256 lastIndex = userLockedAssets[msg.sender][_vault].length - 1;

        //swap if asset ID not last index
        if(_assetID != lastIndex) {
            userLockedAssets[msg.sender][_vault][_assetID] = userLockedAssets[msg.sender][_vault][lastIndex];
        }

        //remove last element
        userLockedAssets[msg.sender][_vault].pop();

        emit VaultDeleted(_vault, _assetID, block.timestamp);
    }

    //rename vault
    function renameVault(uint8 _vault, uint8 _assetID, string memory _newTitle) external {
        require(_assetID < userLockedAssets[msg.sender][_vault].length, "Invalid Asset ID!");
        require(bytes(_newTitle).length > 0 && bytes(_newTitle).length <= 100, "Invalid title length!");

        //rename
        userLockedAssets[msg.sender][_vault][_assetID].title = _newTitle;

        emit  RenameVault(_newTitle, _assetID, _vault);
    }

    //transfer assets between vaults and sub-vaults
    function transferAsset(uint256 _amount, uint8 _fromVault, uint8 _fromAssetID, uint8 _toVault, uint8 _toAssetID) external nonReentrant {
        require(_fromAssetID < userLockedAssets[msg.sender][_fromVault].length, "Invalid Transfer From Asset ID!");
        require(_toAssetID < userLockedAssets[msg.sender][_toVault].length, "Invalid Transfer To Asset ID!");

        Lock storage fLock = userLockedAssets[msg.sender][_fromVault][_fromAssetID];
        Lock storage tLock = userLockedAssets[msg.sender][_toVault][_toAssetID];

        require(address(fLock.token) == address(tLock.token), "Token Addresses Don't Match!");
        require(block.timestamp > fLock.lockEndTime, "Transfer From Sub-Vault Is Still Locked!");
        require(block.timestamp < tLock.lockEndTime, "Transfer To Sub-Vault Is Not Locked!");
        require(!fLock.withdrawn, "Vault Has No Assets!");
        require(_amount <= fLock.amount, "Insufficient Assets To Transfer!");

        //transfer
        userLockedAssets[msg.sender][_fromVault][_fromAssetID].amount -= _amount;

        if (userLockedAssets[msg.sender][_fromVault][_fromAssetID].amount == 0) {
            userLockedAssets[msg.sender][_fromVault][_fromAssetID].withdrawn = true;
        }

        userLockedAssets[msg.sender][_toVault][_toAssetID].amount += _amount;

        emit TransferAsset(address(fLock.token),_amount,_fromVault,_fromAssetID,_toVault,_toAssetID);
    }

}