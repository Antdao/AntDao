pragma solidity 0.6.12;

import "../interfaces/IERC20.sol";
import "../OpenZeppelin/token/ERC20/SafeERC20.sol";
import "../OpenZeppelin/utils/EnumerableSet.sol";
import "../OpenZeppelin/math/SafeMath.sol";
import "../OpenZeppelin/access/Ownable.sol";
import "../Access/ANTAccessControls.sol";
import "../interfaces/IAntFarm.sol";
import "../Utils/SafeTransfer.sol";

contract ANTMasterChef is IAntFarm, ANTAccessControls, SafeTransfer {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
        
    }

   
    struct PoolInfo {
        IERC20 lpToken;             
        uint256 allocPoint;         
        uint256 lastRewardBlock;    
        uint256 accRewardsPerShare; 
    }

    IERC20 public rewards;
    address public devaddr;
    uint256 public devPercentage;
    uint256 public tips;
    uint256 public bonusEndBlock;
    uint256 public rewardsPerBlock;
    uint256 public bonusMultiplier;
    uint256 public totalRewardDebt;
    uint256 public constant override farmTemplate = 1;
    bool private initialised;
    PoolInfo[] public poolInfo;
    
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint;
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function initFarm(
        address _rewards,
        uint256 _rewardsPerBlock,
        uint256 _startBlock,
        address _devaddr,
        address _admin
    ) public {
        require(!initialised);
        rewards = IERC20(_rewards);
        totalAllocPoint = 0;
        rewardsPerBlock = _rewardsPerBlock;
        startBlock = _startBlock;
        devaddr = _devaddr;
        initAccessControls(_admin);
        initialised = true;
    }

    function initFarm(
        bytes calldata _data
    ) public override {
        (address _rewards,
        uint256 _rewardsPerBlock,
        uint256 _startBlock,
        address _devaddr,
        address _admin) = abi.decode(_data, (address, uint256, uint256, address, address));
        initFarm(_rewards,_rewardsPerBlock,_startBlock,_devaddr,_admin );
    }


    function getInitData(
            address _rewards,
            uint256 _rewardsPerBlock,
            uint256 _startBlock,
            address _divaddr,
            address _accessControls
    ) external pure returns (bytes memory _data)
    {
        return abi.encode(_rewards, _rewardsPerBlock, _startBlock, _divaddr, _accessControls);
    }


    function setBonus(
        uint256 _bonusEndBlock,
        uint256 _bonusMultiplier
    ) public {
        require(
            hasAdminRole(msg.sender),
            "MasterChef.setBonus: Sender must be admin"
        );

        bonusEndBlock = _bonusEndBlock;
        bonusMultiplier = _bonusMultiplier;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addToken(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public  {
        require(
            hasAdminRole(msg.sender),
            "MasterChef.addToken: Sender must be admin"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardsPerShare: 0
        }));
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public  {
        require(
            hasOperatorRole(msg.sender) ,
            "MasterChef.set: Sender must be admin"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 remaining = blocksRemaining();
        uint multiplier = 0;
        if (remaining == 0) {
            return 0;
        } 
        if (_to <= bonusEndBlock) {
            multiplier = _to.sub(_from).mul(bonusMultiplier);
        } else if (_from >= bonusEndBlock) {
            multiplier = _to.sub(_from);
        } else {
            multiplier = bonusEndBlock.sub(_from).mul(bonusMultiplier).add(
                _to.sub(bonusEndBlock)
            );
        }

        if (multiplier > remaining ) {
            multiplier = remaining;
        }
        return multiplier;
    }

    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 rewardsAccum = multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(rewardsAccum.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e12).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 rewardsAccum = multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if (devPercentage > 0) {
            tips = tips.add(rewardsAccum.mul(devPercentage).div(1000));
        }
        totalRewardDebt = totalRewardDebt.add(rewardsAccum);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(rewardsAccum.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                totalRewardDebt = totalRewardDebt.sub(pending);
                safeRewardsTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            totalRewardDebt = totalRewardDebt.sub(pending);
            safeRewardsTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function safeRewardsTransfer(address _to, uint256 _amount) internal {
        uint256 rewardsBal = rewards.balanceOf(address(this));
        if (_amount > rewardsBal) {
            _safeTransfer(address(rewards), _to, rewardsBal);
        } else {
            _safeTransfer(address(rewards), _to, _amount);
        }
    }

    function tokensRemaining() public view returns(uint256) {
        return rewards.balanceOf(address(this));
    }

    function tokenDebt() public view returns(uint256) {
        return  totalRewardDebt.add(tips);
    }
    
    function blocksRemaining() public view returns (uint256){
        if (tokensRemaining() <= tokenDebt()) {
            return 0;
        }
        uint256 rewardsBal = tokensRemaining().sub(tokenDebt()) ;
        if (rewardsPerBlock > 0) {
            if (devPercentage > 0) {
                rewardsBal = rewardsBal.mul(1000).div(devPercentage.add(1000));
            }
            return rewardsBal / rewardsPerBlock;
        } else {
            return 0;
        }
    }

    function claimTips() public {
        require(msg.sender == devaddr, "dev: wut?");
        require(tips > 0, "dev: broke");
        uint256 claimable = tips;
        tips = 0;
        safeRewardsTransfer(devaddr, claimable);
    }

    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setDevPercentage(uint256 _devPercentage) public {
        require(msg.sender == devaddr, "dev: wut?");
        devPercentage = _devPercentage;
    }   
}
