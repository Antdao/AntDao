pragma solidity 0.6.12;


import "./Utils/SafeTransfer.sol";
import "./Utils/BoringMath.sol";
import "./Access/ANTAccessControls.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IAntLiquidity.sol";
import "./interfaces/IBentoBoxFactory.sol";
import "./OpenZeppelin/token/ERC20/SafeERC20.sol";


contract ANTLauncher is SafeTransfer {

    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using SafeERC20 for IERC20;

   ANTAccessControls public accessControls;
    bytes32 public constant LAUNCHER_MINTER_ROLE = keccak256("LAUNCHER_MINTER_ROLE");

    bool private initialised;

    struct Launcher {
        bool exists;
        uint64 templateId;
        uint128 index;
    }

    address[] public launchers;

    uint256 public launcherTemplateId;

    IBentoBoxFactory public bentoBox;

    mapping(uint256 => address) private launcherTemplates;
    mapping(address => uint256) private launcherTemplateToId;
    mapping(uint256 => uint256) public currentTemplateId;
    mapping(address => Launcher) public launcherInfo;

    struct LauncherFees {
        uint128 minimumFee;
        uint32 integratorFeePct;
    }

    LauncherFees public launcherFees;

    bool public locked;

    address payable public antDiv;

    event AntInitLauncher(address sender);
    event LauncherCreated(address indexed owner, address indexed addr, address launcherTemplate);
    event LauncherTemplateAdded(address newLauncher, uint256 templateId);
    event LauncherTemplateRemoved(address launcher, uint256 templateId);

    constructor() public {
    }

    function initANTLauncher(address _accessControls, address _bentoBox) external {
        require(!initialised);
        require(_accessControls != address(0), "initANTLauncher: accessControls cannot be set to zero");
        require(_bentoBox != address(0), "initANTLauncher: bentoBox cannot be set to zero");

        accessControls = ANTAccessControls(_accessControls);
        bentoBox = IBentoBoxFactory(_bentoBox); 
        locked = true;
        initialised = true;

        emit AntInitLauncher(msg.sender);
    }

    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTLauncher: Sender must be operator"
        );
        launcherFees.minimumFee = BoringMath.to128(_amount);
    }

    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTLauncher: Sender must be operator"
        );
       require(_amount <= 1000, "ANTLauncher: Percentage is out of 1000");
        launcherFees.integratorFeePct = BoringMath.to32(_amount);
    }

   function setDividends(address payable _divaddr) external {
        require(accessControls.hasAdminRole(msg.sender), "ANTLauncher: Sender must be operator");
        require(_divaddr != address(0));
        antDiv = _divaddr;
    }
    
    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTLauncher: Sender must be admin address"
        );
        locked = _locked;
    }

    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTLauncher: Sender must be Operator"
        );
        currentTemplateId[_templateType] = _templateId;
    }

    function hasLauncherMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(LAUNCHER_MINTER_ROLE, _address);
    }



    function deployLauncher(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address launcher)
    {
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasLauncherMinterRole(msg.sender),
                "ANTLauncher: Sender must be minter if locked"
            );
        }

        LauncherFees memory _launcherFees = launcherFees;
        address launcherTemplate = launcherTemplates[_templateId];
        require(msg.value >= uint256(_launcherFees.minimumFee), "ANTLauncher: Failed to transfer minimumFee");
        require(launcherTemplate != address(0), "ANTLauncher: Launcher template doesn't exist");
        uint256 integratorFee = 0;
        uint256 antFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != antDiv) {
            integratorFee = antFee * uint256(_launcherFees.integratorFeePct) / 1000;
            antFee = antFee - integratorFee;
        }
        launcher = bentoBox.deploy(launcherTemplate, "", false);
        launcherInfo[address(launcher)] = Launcher(true, BoringMath.to64(_templateId), BoringMath.to128(launchers.length));
        launchers.push(address(launcher));
        emit LauncherCreated(msg.sender, address(launcher), launcherTemplates[_templateId]);
        if (antFee > 0) {
            antDiv.transfer(antFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }


    function createLauncher(
        uint256 _templateId,
        address _token,
        uint256 _tokenSupply,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address newLauncher)
    {

        newLauncher = deployLauncher(_templateId, _integratorFeeAccount);
        if (_tokenSupply > 0) {
            _safeTransferFrom(_token, msg.sender, _tokenSupply);
            IERC20(_token).safeApprove(newLauncher, _tokenSupply);
        }
        IAntLiquidity(newLauncher).initLauncher(_data);

        if (_tokenSupply > 0) {
            uint256 remainingBalance = IERC20(_token).balanceOf(address(this));
            if (remainingBalance > 0) {
                _safeTransfer(_token, msg.sender, remainingBalance);
            }
        }
        return newLauncher;
    }


    function addLiquidityLauncherTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTLauncher: Sender must be operator"
        );
        uint256 templateType = IAntLiquidity(_template).liquidityTemplate();
        require(templateType > 0, "ANTLauncher: Incorrect template code");
        launcherTemplateId++;

        launcherTemplates[launcherTemplateId] = _template;
        launcherTemplateToId[_template] = launcherTemplateId;
        currentTemplateId[templateType] = launcherTemplateId;
        emit LauncherTemplateAdded(_template, launcherTemplateId);

    }

    function removeLiquidityLauncherTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTLauncher: Sender must be operator"
        );
        require(launcherTemplates[_templateId] != address(0));
        address _template = launcherTemplates[_templateId];
        launcherTemplates[_templateId] = address(0);
        delete launcherTemplateToId[_template];
        uint256 templateType = IAntLiquidity(_template).liquidityTemplate();
        if(currentTemplateId[templateType] == _templateId){
            delete currentTemplateId[templateType];
        }
        emit LauncherTemplateRemoved(_template, _templateId);
    }

    function getLiquidityLauncherTemplate(uint256 _templateId) external view returns (address) {
        return launcherTemplates[_templateId];
    }

    function getTemplateId(address _launcherTemplate) external view returns (uint256) {
        return launcherTemplateToId[_launcherTemplate];
    }

    function numberOfLiquidityLauncherContracts() external view returns (uint256) {
        return launchers.length;
    }

    function minimumFee() external view returns(uint128) {
        return launcherFees.minimumFee;
    }

    function getLauncherTemplateId(address _launcher) external view returns(uint64) {
        return launcherInfo[_launcher].templateId;
    }
    function getLaunchers() external view returns(address[] memory) {
        return launchers;
    }


}
