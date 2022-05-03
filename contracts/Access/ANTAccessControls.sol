// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.6.12;

import "./ANTAdminAccess.sol";

contract ANTAccessControls is ANTAdminAccess {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SMART_CONTRACT_ROLE = keccak256("SMART_CONTRACT_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

   constructor() public {
    }


   function hasMinterRole(address _address) public view returns (bool) {
        return hasRole(MINTER_ROLE, _address);
    }

   function hasSmartContractRole(address _address) public view returns (bool) {
        return hasRole(SMART_CONTRACT_ROLE, _address);
    }

    function hasOperatorRole(address _address) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, _address);
    }

    function addMinterRole(address _address) external {
        grantRole(MINTER_ROLE, _address);
    }

    function removeMinterRole(address _address) external {
        revokeRole(MINTER_ROLE, _address);
    }

    function addSmartContractRole(address _address) external {
        grantRole(SMART_CONTRACT_ROLE, _address);
    }

    function removeSmartContractRole(address _address) external {
        revokeRole(SMART_CONTRACT_ROLE, _address);
    }

    function addOperatorRole(address _address) external {
        grantRole(OPERATOR_ROLE, _address);
    }

    function removeOperatorRole(address _address) external {
        revokeRole(OPERATOR_ROLE, _address);
    }

}
