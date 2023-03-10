// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.6.12;

import "../Utils/CloneFactory.sol";
import "./ANTAccessControls.sol";


contract ANTAccessFactory is CloneFactory {

    ANTAccessControls public accessControls;

    address public accessControlTemplate;

    bool private initialised;

    uint256 public minimumFee;

    address public devaddr;

    address[] public children;

    mapping(address => bool) public isChild;

    event AntInitAccessFactory(address sender);
    event AccessControlCreated(address indexed owner,  address accessControls, address admin, address accessTemplate);
    event AccessControlTemplateAdded(address oldAccessControl, address newAccessControl);
    event AccessControlTemplateRemoved(address access, uint256 templateId);
    event MinimumFeeUpdated(uint oldFee, uint newFee);
    event DevAddressUpdated(address oldDev, address newDev);


    constructor() public {
    }

    function initANTAccessFactory(uint256 _minimumFee, address _accessControls) external {
        require(!initialised);
        initialised = true;
        minimumFee = _minimumFee;
        accessControls = ANTAccessControls(_accessControls);
        emit AntInitAccessFactory(msg.sender);
    }

    function numberOfChildren() external view returns (uint256) {
        return children.length;
    }

    function deployAccessControl(address _admin) external payable returns (address access) {
        require(msg.value >= minimumFee, "Minimum fee needs to be paid.");
        require(accessControlTemplate != address(0), "Access control template does not exist");
        access = createClone(accessControlTemplate);
        isChild[address(access)] = true;
        children.push(address(access));
        ANTAccessControls(access).initAccessControls(_admin);
        emit AccessControlCreated(msg.sender, address(access), _admin, accessControlTemplate);
        if (msg.value > 0) {
            payable(devaddr).transfer(msg.value);
        }
    }

    function updateAccessTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTAccessFactory.updateAccessTemplate: Sender must be admin"
        );
        require(_template != address(0));
        emit AccessControlTemplateAdded(accessControlTemplate, _template);
        accessControlTemplate = _template;
    }

    function setDev(address _devaddr) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTAccessFactory.setMinimumFee: Sender must be admin address"
        );
        emit DevAddressUpdated(devaddr, _devaddr);
        devaddr = _devaddr;
    }

    function setMinimumFee(uint256 _minimumFee) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTAccessFactory.setMinimumFee: Sender must be admin"
        );
        emit MinimumFeeUpdated(minimumFee, _minimumFee);
        minimumFee = _minimumFee;
    }
}
