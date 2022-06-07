pragma solidity 0.6.12;


import "./Utils/CloneFactory.sol";
import "./Access/ANTAccessControls.sol";

contract ANTFermenter is CloneFactory {

    ANTAccessControls public accessControls;
    bytes32 public constant VAULT_MINTER_ROLE = keccak256("VAULT_MINTER_ROLE");

    bool private initialised;
    bool public locked;

    struct Fermenter{
        bool exists;
        uint256 templateId;
        uint256 index;
    }

    address[] public escrows;

    uint256 public escrowTemplateId;

    mapping(uint256 => address) private escrowTemplates;

    mapping(address => uint256) private escrowTemplateToId;

    mapping(address => Fermenter) public isChildEscrow;

    event AntInitFermenter(address sender);
    event EscrowTemplateAdded(address newTemplate, uint256 templateId);
    event EscrowTemplateRemoved(address template, uint256 templateId);
    event EscrowCreated(address indexed owner, address indexed addr,address escrowTemplate);

    function initANTFermenter(address _accessControls) external {
        
        require(!initialised);
        initialised = true;
        locked = true;
        accessControls = ANTAccessControls(_accessControls);
        emit AntInitFermenter(msg.sender);
    }

    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTFermenter: Sender must be admin address"
        );
        locked = _locked;
    }


    function hasVaultMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(VAULT_MINTER_ROLE, _address);
    }



    function createEscrow(uint256 _templateId) external returns (address newEscrow) {

        
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasVaultMinterRole(msg.sender),
                "ANTFermenter: Sender must be minter if locked"
            );
        }

        require(escrowTemplates[_templateId]!= address(0));
        newEscrow = createClone(escrowTemplates[_templateId]);


        isChildEscrow[address(newEscrow)] = Fermenter(true,_templateId,escrows.length);
        escrows.push(newEscrow);
        emit EscrowCreated(msg.sender,address(newEscrow),escrowTemplates[_templateId]);
    }

    function addEscrowTemplate(address _escrowTemplate) external {
         require(
            accessControls.hasOperatorRole(msg.sender),
            "ANTFermenter: Sender must be operator"
        );
        escrowTemplateId++;
        escrowTemplates[escrowTemplateId] = _escrowTemplate;
        escrowTemplateToId[_escrowTemplate] = escrowTemplateId;
        emit EscrowTemplateAdded(_escrowTemplate, escrowTemplateId);
    }

    function removeEscrowTemplate(uint256 _templateId) external {
        require(
            accessControls.hasOperatorRole(msg.sender),
            "ANTFermenter: Sender must be operator"
        );
        require(escrowTemplates[_templateId] != address(0));
        address template = escrowTemplates[_templateId];
        escrowTemplates[_templateId] = address(0);
        delete escrowTemplateToId[template];
        emit EscrowTemplateRemoved(template, _templateId);
    }

    function getEscrowTemplate(uint256 _templateId) external view returns (address) {
        return escrowTemplates[_templateId];
    }

    function getTemplateId(address _escrowTemplate) external view returns (uint256 templateId) {
        return escrowTemplateToId[_escrowTemplate];
    }

    function numberOfTokens() external view returns (uint256) {
        return escrows.length;
    }


}
