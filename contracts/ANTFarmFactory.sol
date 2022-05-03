pragma solidity 0.6.12;
                                                                                                                                                                                                                    
import "./Utils/CloneFactory.sol";
import "./interfaces/IAntFarm.sol";
import "./Access/ANTAccessControls.sol";

contract ANTFarmFactory is CloneFactory {

    
    ANTAccessControls public accessControls;
    bytes32 public constant FARM_MINTER_ROLE = keccak256("FARM_MINTER_ROLE");

    
    bool private initialised;
    bool public locked;

    struct Farm {
        bool exists;
        uint256 templateId;
        uint256 index;
    }

    mapping(address => Farm) public farmInfo;

    address[] public farms;

    uint256 public farmTemplateId;

    mapping(uint256 => address) private farmTemplates;

    mapping(address => uint256) private farmTemplateToId;

   mapping(uint256 => uint256) public currentTemplateId;

    uint256 public minimumFee;
    uint256 public integratorFeePct;

    address payable public antDiv;

    event AntInitFarmFactory(address sender);

    event FarmCreated(address indexed owner, address indexed addr, address farmTemplate);

    event FarmTemplateAdded(address newFarm, uint256 templateId);

    event FarmTemplateRemoved(address farm, uint256 templateId);

    function initANTFarmFactory(
        address _accessControls,
        address payable _antDiv,
        uint256 _minimumFee,
        uint256 _integratorFeePct
    )
        external
    {
        require(!initialised);
        require(_antDiv != address(0));
        locked = true;
        initialised = true;
        antDiv = _antDiv;
        minimumFee = _minimumFee;
        integratorFeePct = _integratorFeePct;
        accessControls = ANTAccessControls(_accessControls);
        emit AntInitFarmFactory(msg.sender);
    }

    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTFarmFactory: Sender must be operator"
        );
        minimumFee = _amount;
    }

    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTFarmFactory: Sender must be operator"
        );
        require(
            _amount <= 1000, 
            "ANTFarmFactory: Range is from 0 to 1000"
        );
        integratorFeePct = _amount;
    }

    function setDividends(address payable _divaddr) external  {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTFarmFactory: Sender must be operator"
        );
        require(_divaddr != address(0));
        antDiv = _divaddr;
    }

    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTFarmFactory: Sender must be admin"
        );
        locked = _locked;
    }


    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTFarmFactory: Sender must be admin"
        );
        currentTemplateId[_templateType] = _templateId;
    }

    function hasFarmMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(FARM_MINTER_ROLE, _address);
    }



    function deployFarm(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address farm)
    {
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasFarmMinterRole(msg.sender),
                "ANTFarmFactory: Sender must be minter if locked"
            );
        }

        require(msg.value >= minimumFee, "ANTFarmFactory: Failed to transfer minimumFee");
        require(farmTemplates[_templateId] != address(0));
        uint256 integratorFee = 0;
        uint256 antFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != antDiv) {
            integratorFee = antFee * integratorFeePct / 1000;
            antFee = antFee - integratorFee;
        }
        farm = createClone(farmTemplates[_templateId]);
        farmInfo[address(farm)] = Farm(true, _templateId, farms.length);
        farms.push(address(farm));
        emit FarmCreated(msg.sender, address(farm), farmTemplates[_templateId]);
        if (antFee > 0) {
            antDiv.transfer(antFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }

    function createFarm(
        uint256 _templateId,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address farm)
    {
        farm = deployFarm(_templateId, _integratorFeeAccount);
        IAntFarm(farm).initFarm(_data);
    }

    function addFarmTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTFarmFactory: Sender must be operator"
        );
        require(farmTemplateToId[_template] == 0, "ANTFarmFactory: Template already added");
        uint256 templateType = IAntFarm(_template).farmTemplate();
        require(templateType > 0, "ANTFarmFactory: Incorrect template code ");
        farmTemplateId++;
        farmTemplates[farmTemplateId] = _template;
        farmTemplateToId[_template] = farmTemplateId;
        currentTemplateId[templateType] = farmTemplateId;
        emit FarmTemplateAdded(_template, farmTemplateId);

    }

    function removeFarmTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTFarmFactory: Sender must be operator"
        );
        require(farmTemplates[_templateId] != address(0));
        address template = farmTemplates[_templateId];
        farmTemplates[_templateId] = address(0);
        delete farmTemplateToId[template];
        emit FarmTemplateRemoved(template, _templateId);
    }

    function getFarmTemplate(uint256 _farmTemplate) external view returns (address) {
        return farmTemplates[_farmTemplate];
    }

    function getTemplateId(address _farmTemplate) external view returns (uint256) {
        return farmTemplateToId[_farmTemplate];
    }

    function numberOfFarms() external view returns (uint256) {
        return farms.length;
    }

    function getFarms() external view returns(address[] memory) {
        return farms;
    }
}
