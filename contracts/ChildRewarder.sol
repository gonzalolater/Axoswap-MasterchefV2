// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IRewarder.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "./MasterChefV2.sol";

interface IRewarderExt is IRewarder {
    function pendingToken(uint _pid, address _user) external view returns (uint pending);
    function rewardToken() external view returns (IERC20);
}

interface IERC20Ext is IERC20 {
    function decimals() external returns (uint);
}

contract ChildRewarder is IRewarder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of REWARD entitled to the user.
    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of REWARD to distribute per block.
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    /// @notice Info of each pool.
    mapping (uint => PoolInfo) public poolInfo;

    uint[] public poolIds;

    /// @notice Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint totalAllocPoint;

    uint public rewardPerblock;
    uint public ACC_TOKEN_PRECISION;

    address private MASTERCHEF_V2;

    address private PARENT;

    bool notinit = true;

    event LogOnReward(address indexed user, uint indexed pid, uint amount, address indexed to);
    event LogPoolAddition(uint indexed pid, uint allocPoint);
    event LogSetPool(uint indexed pid, uint allocPoint);
    event LogUpdatePool(uint indexed pid, uint lastRewardTime, uint lpSupply, uint accRewardPerShare);
    event LogRewardPerblock(uint rewardPerblock);
    event AdminTokenRecovery(address _tokenAddress, uint _amt, address _adr);
    event LogInit();

    modifier onlyParent {
        require(msg.sender == PARENT, "Only PARENT can call this function.");
        _;
    }

    constructor () {} //use init()

    function init(IERC20Ext _rewardToken, uint _rewardPerblock, address _MASTERCHEF_V2, address _PARENT) external {
        require(notinit);

        uint decimalsRewardToken = _rewardToken.decimals();
        require(decimalsRewardToken < 30, "Token has way too many decimals");
        ACC_TOKEN_PRECISION = 10**(30 - decimalsRewardToken);
        rewardToken = _rewardToken;
        rewardPerblock = _rewardPerblock;
        MASTERCHEF_V2 = _MASTERCHEF_V2;
        PARENT = _PARENT;

        notinit = false;
    }


    function onReward (uint _pid, address _user, address _to, uint, uint _amt) onlyParent nonReentrant override external {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][_user];
        uint pending;
        if (user.amount > 0) {
            pending = (user.amount * pool.accRewardPerShare / ACC_TOKEN_PRECISION) - user.rewardDebt;
            rewardToken.safeTransfer(_to, pending);
        }
        user.amount = _amt;
        user.rewardDebt = _amt * pool.accRewardPerShare / ACC_TOKEN_PRECISION;
        emit LogOnReward(_user, _pid, pending, _to);
    }

    function pendingTokens(uint pid, address user, uint) override external view returns (IERC20[] memory rewardTokens, uint[] memory rewardAmounts) {
        IERC20[] memory _rewardTokens = new IERC20[](1);
        _rewardTokens[0] = (rewardToken);
        uint[] memory _rewardAmounts = new uint[](1);
        _rewardAmounts[0] = pendingToken(pid, user);
        return (_rewardTokens, _rewardAmounts);
    }

    /// @notice Sets the reward per block to be distributed. Can only be called by the owner.
    /// @param _rewardPerblock The amount of token to be distributed per block.
    function setRewardPerblock(uint _rewardPerblock) public onlyOwner {
        rewardPerblock = _rewardPerblock;
        emit LogRewardPerblock(_rewardPerblock);
    }


    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint pools) {
        pools = poolIds.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _pid Pid on MCV2
    function add(uint64 allocPoint, uint _pid, bool _update) public onlyOwner {
        require(poolInfo[_pid].lastRewardTime == 0, "Pool already exists");
        if (_update) {
            massUpdatePools();
        }
        uint64 lastRewardTime = uint64(block.timestamp);
        totalAllocPoint = totalAllocPoint + allocPoint;

        PoolInfo storage poolinfo = poolInfo[_pid];
        poolinfo.allocPoint = allocPoint;
        poolinfo.lastRewardTime = lastRewardTime;
        poolinfo.accRewardPerShare = 0;
        poolIds.push(_pid);
        emit LogPoolAddition(_pid, allocPoint);
    }

    /// @notice Update the given pool's REWARD allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint _pid, uint64 _allocPoint, bool _update) public onlyOwner {
        if (_update) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice View function to see pending Token
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD reward for a given user.
    function pendingToken(uint _pid, address _user) public view returns (uint pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accRewardPerShare = pool.accRewardPerShare;
        uint lpSupply = MasterChefV2(MASTERCHEF_V2).lpToken(_pid).balanceOf(MASTERCHEF_V2);

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint time = block.timestamp - pool.lastRewardTime;
            uint reward = totalAllocPoint == 0 ? 0 : (time * rewardPerblock * pool.allocPoint / totalAllocPoint);
            accRewardPerShare = accRewardPerShare + (reward * ACC_TOKEN_PRECISION / lpSupply);
        }
        pending = (user.amount * accRewardPerShare / ACC_TOKEN_PRECISION) - user.rewardDebt;
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint len = poolIds.length;
        for (uint i = 0; i < len; ++i) {
            updatePool(poolIds[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint lpSupply = MasterChefV2(MASTERCHEF_V2).lpToken(pid).balanceOf(MASTERCHEF_V2);

            if (lpSupply > 0) {
                uint time = block.timestamp - pool.lastRewardTime;
                uint reward = totalAllocPoint == 0 ? 0 : (time * rewardPerblock * pool.allocPoint / totalAllocPoint);
                pool.accRewardPerShare = pool.accRewardPerShare + uint128(reward * ACC_TOKEN_PRECISION / lpSupply);
            }
            pool.lastRewardTime = uint64(block.timestamp);
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply, pool.accRewardPerShare);
        }
    }

    function recoverTokens(address _tokenAddress, uint _amt, address _adr) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(_adr, _amt);

        emit AdminTokenRecovery(_tokenAddress, _amt, _adr);
    }

}