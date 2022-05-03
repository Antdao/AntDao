pragma solidity 0.6.12;

import "./Utils/CloneFactory.sol";
import "./interfaces/IAntToken.sol";
import "./Access/ANTAccessControls.sol";
import "./Utils/SafeTransfer.sol";
import "./interfaces/IERC20.sol";

contract ANTTokenFactory is CloneFactory, SafeTransfer{
    
    ANTAccessControls public accessControls;
    bytes32 public constant TOKEN_MINTER_ROLE = keccak256("TOKEN_MINTER_ROLE");

    uint256 private constant INTEGRATOR_FEE_PRECISION = 1000;

    bool private initialised;

    struct Token {
        bool exists;
        uint256 templateId;
        uint256 index;
    }

    mapping(address => Token) public tokenInfo;

    address[] public tokens;

    uint256 public tokenTemplateId;

    mapping(uint256 => address) private tokenTemplates;

    mapping(address => uint256) private tokenTemplateToId;

    mapping(uint256 => uint256) public currentTemplateId;

    uint256 public minimumFee;
    uint256 public integratorFeePct;

    bool public locked;

    address payable public antDiv;

    event AntInitTokenFactory(address sender);

    event TokenCreated(address indexed owner, address indexed addr, address tokenTemplate);
    
    event TokenInitialized(address indexed addr, uint256 templateId, bytes data);

    event TokenTemplateAdded(address newToken, uint256 templateId);

    event TokenTemplateRemoved(address token, uint256 templateId);

    constructor() public {
    }

    function initANTTokenFactory(address _accessControls) external  {
        require(!initialised);
        initialised = true;
        locked = true;
        accessControls = ANTAccessControls(_accessControls);
        emit AntInitTokenFactory(msg.sender);
    }

    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTTokenFactory: Sender must be operator"
        );
        minimumFee = _amount;
    }

    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTTokenFactory: Sender must be operator"
        );
        require(
            _amount <= INTEGRATOR_FEE_PRECISION, 
            "ANTTokenFactory: Range is from 0 to 1000"
        );
        integratorFeePct = _amount;
    }

    function setDividends(address payable _divaddr) external  {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTTokenFactory: Sender must be operator"
        );
        require(_divaddr != address(0));
        antDiv = _divaddr;
    }    
    
    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTTokenFactory: Sender must be admin"
        );
        locked = _locked;
    }


    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTTokenFactory: Sender must be admin"
        );
        require(tokenTemplates[_templateId] != address(0), "ANTTokenFactory: incorrect _templateId");
        require(IAntToken(tokenTemplates[_templateId]).tokenTemplate() == _templateType, "ANTTokenFactory: incorrect _templateType");
        currentTemplateId[_templateType] = _templateId;
    }

    function hasTokenMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(TOKEN_MINTER_ROLE, _address);
    }



    function deployToken(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address token)
    {
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasTokenMinterRole(msg.sender),
                "ANTTokenFactory: Sender must be minter if locked"
            );
        }
        require(msg.value >= minimumFee, "ANTTokenFactory: Failed to transfer minimumFee");
        require(tokenTemplates[_templateId] != address(0), "ANTTokenFactory: incorrect _templateId");
        uint256 integratorFee = 0;
        uint256 antFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != antDiv) {
            integratorFee = antFee * integratorFeePct / INTEGRATOR_FEE_PRECISION;
            antFee = antFee - integratorFee;
        }
        token = createClone(tokenTemplates[_templateId]);
        tokenInfo[token] = Token(true, _templateId, tokens.length);
        tokens.push(token);
        emit TokenCreated(msg.sender, token, tokenTemplates[_templateId]);
        if (antFee > 0) {
            antDiv.transfer(antFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }

    function createToken(
        uint256 _templateId,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address token)
    {
        token = deployToken(_templateId, _integratorFeeAccount);
        emit TokenInitialized(address(token), _templateId, _data);
        IAntToken(token).initToken(_data);
        uint256 initialTokens = IERC20(token).balanceOf(address(this));
        if (initialTokens > 0 ) {
            _safeTransfer(token, msg.sender, initialTokens);
        }
    }

    function addTokenTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTTokenFactory: Sender must be operator"
        );
        uint256 templateType = IAntToken(_template).tokenTemplate();
        require(templateType > 0, "ANTTokenFactory: Incorrect template code ");
        require(tokenTemplateToId[_template] == 0, "ANTTokenFactory: Template exists");
        tokenTemplateId++;
        tokenTemplates[tokenTemplateId] = _template;
        tokenTemplateToId[_template] = tokenTemplateId;
        currentTemplateId[templateType] = tokenTemplateId;
        emit TokenTemplateAdded(_template, tokenTemplateId);

    }

    function removeTokenTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTTokenFactory: Sender must be operator"
        );
        require(tokenTemplates[_templateId] != address(0));
        address template = tokenTemplates[_templateId];
        uint256 templateType = IAntToken(tokenTemplates[_templateId]).tokenTemplate();
        if (currentTemplateId[templateType] == _templateId) {
            delete currentTemplateId[templateType];
        }
        tokenTemplates[_templateId] = address(0);
        delete tokenTemplateToId[template];
        emit TokenTemplateRemoved(template, _templateId);
    }

    function numberOfTokens() external view returns (uint256) {
        return tokens.length;
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function getTokenTemplate(uint256 _templateId) external view returns (address ) {
        return tokenTemplates[_templateId];
    }

    function getTemplateId(address _tokenTemplate) external view returns (uint256) {
        return tokenTemplateToId[_tokenTemplate];
    }
}
