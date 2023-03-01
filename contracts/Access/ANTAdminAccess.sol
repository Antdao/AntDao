// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.6.12;

import "../OpenZeppelin/access/AccessControl.sol";


contract ANTAdminAccess is AccessControl {

    bool private initAccess;

    constructor() public {
    }

    function initAccessControls(address _admin) public {
        require(!initAccess, "Already initialised");
        require(_admin != address(0), "Incorrect input");
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        initAccess = true;
    }

    function hasAdminRole(address _address) public  view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _address);
    }

    
    function addAdminRole(address _address) external {
        grantRole(DEFAULT_ADMIN_ROLE, _address);
    }

    function removeAdminRole(address _address) external {
        revokeRole(DEFAULT_ADMIN_ROLE, _address);
    }
}
