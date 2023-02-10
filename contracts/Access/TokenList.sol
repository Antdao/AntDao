// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.6.12;

import "../interfaces/IPointList.sol";
import "../interfaces/IERC20.sol";

contract TokenList {
    IERC20 public token;
    
    bool private initialised;

    constructor() public {
    }

    function initPointList(IERC20 _token) public {
        require(!initialised, "Already initialised");
        token = _token;
        initialised = true;
    }
    function isInList(address _account) public view returns (bool) {
        return token.balanceOf(_account) > 0;
    }

    function hasPoints(address _account, uint256 _amount) public view returns (bool) {
        return token.balanceOf(_account) >= _amount;
    }
}
