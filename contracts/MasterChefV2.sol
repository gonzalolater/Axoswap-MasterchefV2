// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./interfaces/IRewarder.sol";
import "./interfaces/IMasterChef.sol";


contract MasterChefV2 is Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }

    struct PoolInfo {
        uint128 accAxoPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    /// @notice Address of MCV1 contract.
    IMasterChef public immutable MASTER_CHEF;
    /// @notice Address of AXO contract.
    IERC20 public immutable AXO;
    /// @notice The index of MCV2 master pool in MCV1.
    uint public immutable MASTER_PID;

    /// @notice Info of each MCV2 pool.
    mapping (uint => PoolInfo) public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    mapping (uint => IERC20) public lpToken;
    /// @notice Amount of pool infos and their respective lpToken entries I.E stores last ID + 1, for above two mappings
    uint public poolInfoAmount;
    /// @notice Is an address contained in the above `lpToken` array
    mapping(address => bool) public isLpToken;
    /// @notice Address of each `IRewarder` contract in MCV2.
    mapping(uint => IRewarder) public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;

    uint private constant ACC_AXO_PRECISION = 1e12;

    /// @dev Last MCV1 harvest blockstamp.
    uint public lastV1HarvestBlockstamp;
    /// @dev How often v1 harvest should be called by the query function
    uint public V1_HARVEST_QUERY_TIME = 1 days;

    event Deposit(address indexed user, uint indexed pid, uint amount, address indexed to);
    event Withdraw(address indexed user, uint indexed pid, uint amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount, address indexed to);
    event Harvest(address indexed user, uint indexed pid, uint amount);
    event LogPoolAddition(uint indexed pid, uint allocPoint, IERC20 indexed lpToken, IRewarder rewarder, bool update);
    event LogSetPool(uint indexed pid, uint allocPoint, IRewarder rewarder, bool overwrite, bool update);
    event LogUpdatePool(uint indexed pid, uint lastRewardBlock, uint lpSupply, uint accAxoPerShare);
    event LogInit();

    /// @param _MASTER_CHEF The SpookySwap MCV1 contract address.
    /// @param _axo The AXO token contract address.
    /// @param _MASTER_PID The pool ID of the dummy token on the base MCV1 contract.
    constructor(IMasterChef _MASTER_CHEF, IERC20 _axo, uint _MASTER_PID) {
        MASTER_CHEF = _MASTER_CHEF;
        AXO = _axo;
        MASTER_PID = _MASTER_PID;
    }

    /// @notice Deposits a dummy token to `MASTER_CHEF` MCV1. This is required because MCV1 holds the minting rights for AXO.
    /// Any balance of transaction sender in `dummyToken` is transferred.
    /// The allocation point for the pool on MCV1 is the total allocation point for all pools that receive double incentives.
    /// @param dummyToken The address of the ERC-20 token to deposit into MCV1.
    function init(IERC20 dummyToken) external {
        uint balance = dummyToken.balanceOf(msg.sender);
        require(balance != 0, "MasterChefV2: Balance must exceed 0");
        dummyToken.safeTransferFrom(msg.sender, address(this), balance);
        dummyToken.approve(address(MASTER_CHEF), balance);
        MASTER_CHEF.deposit(MASTER_PID, balance);
        emit LogInit();
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint pools) {
        pools = poolInfoAmount;
    }

    function checkForDuplicate(IERC20 _lpToken) internal view {
        require(!isLpToken[address(_lpToken)], "add: pool already exists!!!!");
    }

    function getFarmData(uint pid) external view returns (PoolInfo memory, uint, IRewarder) {
        return (poolInfo[pid], totalAllocPoint, rewarder[pid]);
    }

    modifier validatePid(uint256 pid) {
        require(pid < poolInfoAmount, "pid doesn't exist...");
        _;
    }

    

    /// @notice View function to see pending AXO on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending AXO reward for a given user.
    function pendingAXO(uint _pid, address _user) external view validatePid(_pid) returns (uint pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accAxoPerShare = pool.accAxoPerShare;
        uint lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = block.timestamp - pool.lastRewardBlock;
            uint axoReward = totalAllocPoint == 0 ? 0 : ((multiplier * axoPerBlock() * pool.allocPoint) / totalAllocPoint);
            accAxoPerShare = accAxoPerShare + (axoReward * ACC_AXO_PRECISION / lpSupply);
        }
        pending = (user.amount * accAxoPerShare / ACC_AXO_PRECISION) - user.rewardDebt;
    }

    /// @notice Update reward variables for an array of pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        harvestFromMasterChef();
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            _updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @dev This function should never be called from a smart contract as it has an unbounded gas cost.
    function massUpdateAllPools() public {
        harvestFromMasterChef();
        uint len = poolInfoAmount;
        for (uint pid = 0; pid < len; ++pid) {
            _updatePool(pid);
        }
    }

    /// @notice Calculates and returns the `amount` of AXO per block allocated to this contract
    function axoPerBlock() public view returns (uint amount) {
        amount = MASTER_CHEF.axoPerBlock() * MASTER_CHEF.poolInfo(MASTER_PID).allocPoint / MASTER_CHEF.totalAllocPoint();
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function _updatePool(uint pid) internal validatePid(pid) returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardBlock) {
            uint lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint multiplier = block.timestamp - pool.lastRewardBlock;
                uint axoReward = totalAllocPoint == 0 ? 0 : ((multiplier * axoPerBlock() * pool.allocPoint) / totalAllocPoint);
                queryHarvestFromMasterChef();
                pool.accAxoPerShare = uint128(pool.accAxoPerShare + ((axoReward * ACC_AXO_PRECISION) / lpSupply));
            }
            pool.lastRewardBlock = uint64(block.timestamp);
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.accAxoPerShare);
        }
    }

    function updatePool(uint pid) external returns (PoolInfo memory pool) {
        return _updatePool(pid);
    }

    function deposit(uint pid, uint amount, address to) external validatePid(pid) {
        _deposit(pid, amount, to);
    }

    function deposit(uint pid, uint amount) external validatePid(pid) {
        _deposit(pid, amount, msg.sender);
    }


    /// @notice Deposit LP tokens to MCV2 for AXO allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function _deposit(uint pid, uint amount, address to) internal {
        PoolInfo memory pool = _updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        uint256 _pendingAxo = (user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION) - user.rewardDebt;

        user.amount += amount;
        user.rewardDebt = user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION;

        // Interactions
        if (_pendingAxo != 0) {
            AXO.safeTransfer(to, _pendingAxo);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, to, to, _pendingAxo, user.amount);
        }

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingAxo);
    }

    function withdraw(uint pid, uint amount, address to) external validatePid(pid) {
        _withdraw(pid, amount, to);
    }

    function withdraw(uint pid, uint amount) external validatePid(pid) {
        _withdraw(pid, amount, msg.sender);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and AXO rewards.
    function _withdraw(uint pid, uint amount, address to) internal {
        PoolInfo memory pool = _updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        require(user.amount >= amount, "withdraw: not good");

        // Effects
        uint256 _pendingAxo = (user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION) - user.rewardDebt;

        user.amount -= amount;
        user.rewardDebt = user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION;

        // Interactions
        if (_pendingAxo != 0) {
            AXO.safeTransfer(to, _pendingAxo);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, _pendingAxo, user.amount);
        }

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingAxo);
    }

    /// @notice Batch harvest all rewards from all staked pools
    /// @dev This function has an unbounded gas cost. Take care not to call it from other smart contracts if you don't know what you're doing.
    function harvestAll() external {
        uint256 length = poolInfoAmount;
        uint calc;
        uint pending;
        UserInfo storage user;
        PoolInfo memory pool;
        uint totalPending;
        for (uint256 pid = 0; pid < length; ++pid) {
            user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                pool = _updatePool(pid);

                calc = user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION;
                pending = calc - user.rewardDebt;
                user.rewardDebt = calc;

                if(pending > 0) {
                    totalPending+=pending;
                }

                IRewarder _rewarder = rewarder[pid];
                if (address(_rewarder) != address(0)) {
                    _rewarder.onReward(pid, msg.sender, msg.sender, pending, user.amount);
                }
            }
        }
        if (totalPending > 0) {
            AXO.safeTransfer(msg.sender, totalPending);
        }
    }

    /// @notice Batch harvest rewards from specified staked pools
    /// @param pids[] The array of pids of the pools you wish to harvest. See `poolInfo`.
    function harvestMultiple(uint[] memory pids) external {
        uint256 length = pids.length;
        uint calc;
        uint pending;
        UserInfo storage user;
        PoolInfo memory pool;
        uint totalPending;
        uint pid;
        for (uint256 i = 0; i < length; ++i) {
            pid = pids[i];
            user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                pool = _updatePool(pid);

                calc = user.amount * pool.accAxoPerShare / ACC_AXO_PRECISION;
                pending = calc - user.rewardDebt;
                user.rewardDebt = calc;

                if(pending > 0) {
                    totalPending+=pending;
                }

                IRewarder _rewarder = rewarder[pid];
                if (address(_rewarder) != address(0)) {
                    _rewarder.onReward(pid, msg.sender, msg.sender, pending, user.amount);
                }
            }

        }
        if (totalPending > 0) {
            AXO.safeTransfer(msg.sender, totalPending);
        }
    }

    /// @notice Harvests AXO from `MASTER_CHEF` MCV1 and pool `MASTER_PID` to this MCV2 contract.
    function harvestFromMasterChef() public {
        lastV1HarvestBlockstamp = block.timestamp;
        MASTER_CHEF.deposit(MASTER_PID, 0);
    }

    /// @notice calls harvestFromMasterChef() if its been more than `V1_HARVEST_QUERY_TIME` since last v1 harvest
    function queryHarvestFromMasterChef() public {
        if(block.timestamp - lastV1HarvestBlockstamp > V1_HARVEST_QUERY_TIME)
            harvestFromMasterChef();
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint pid, address to) external validatePid(pid) {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }


    // ADMIN FUNCTIONS

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Addresses of the rewarder delegate(s).
    function add(uint64 allocPoint, IERC20 _lpToken, IRewarder _rewarder, bool update) external onlyOwner {
        checkForDuplicate(_lpToken);
        
        if (update) {
            massUpdateAllPools();
        }

        uint pid = poolInfoAmount;
        uint64 lastRewardBlock = uint64(block.timestamp);
        totalAllocPoint = totalAllocPoint + allocPoint;
        lpToken[pid] = _lpToken;
        isLpToken[address(_lpToken)] = true;
        rewarder[pid] = _rewarder;

        PoolInfo storage poolinfo = poolInfo[pid];
        poolinfo.allocPoint = allocPoint;
        poolinfo.lastRewardBlock = lastRewardBlock;
        poolinfo.accAxoPerShare = 0;

        poolInfoAmount = poolInfoAmount + 1;

        emit LogPoolAddition(poolInfoAmount - 1, allocPoint, _lpToken, _rewarder, update);
    }

    /// @notice Update the given pool's AXO allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Addresses of the rewarder delegates.
    /// @param overwrite True if _rewarders should be `set`. Otherwise `_rewarders` is ignored.
    function set(uint _pid, uint64 _allocPoint, IRewarder _rewarder, bool overwrite, bool update) external onlyOwner {
        _set(_pid, _allocPoint, _rewarder, overwrite, update);
    }

    /// @notice Batch update the given pool's AXO allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarders Addresses of the rewarder delegates.
    /// @param overwrite True if _rewarders should be `set`. Otherwise `_rewarders` is ignored.
    function setBatch(uint[] memory _pid, uint64[] memory _allocPoint, IRewarder[] memory _rewarders, bool[] memory overwrite, bool update) external onlyOwner {
        require(_pid.length == _allocPoint.length && _allocPoint.length == _rewarders.length && _rewarders.length == overwrite.length, "MCV2: all arrays need to be the same length");

        if(update)
            massUpdateAllPools();

        uint len = _pid.length;
        for(uint i = 0; i < len; i++)
            _set(_pid[i], _allocPoint[i], _rewarders[i], overwrite[i], false);
    }

    function _set(uint _pid, uint64 _allocPoint, IRewarder _rewarder, bool overwrite, bool update) internal validatePid(_pid) {
        if (update) {
            massUpdateAllPools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) rewarder[_pid] = _rewarder;

        emit LogSetPool(_pid, _allocPoint, overwrite ? _rewarder : rewarder[_pid], overwrite, update);
    }

    function setV1HarvestQueryBlock(uint256 newBlock, bool inDays) external onlyOwner {
        V1_HARVEST_QUERY_TIME = newBlock * (inDays ? 1 days : 1);
    }


}
