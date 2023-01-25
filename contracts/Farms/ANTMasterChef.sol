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
