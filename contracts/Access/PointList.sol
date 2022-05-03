// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.6.12;

import "../OpenZeppelin/math/SafeMath.sol";
import "./ANTAccessControls.sol";
import "../interfaces/IPointList.sol";


contract PointList is IPointList, ANTAccessControls {
    using SafeMath for uint;

    mapping(address => uint256) public points;

    uint256 public totalPoints;

    event PointsUpdated(address indexed account, uint256 oldPoints, uint256 newPoints);


    constructor() public {
    }

    function initPointList(address _admin) public override {
        initAccessControls(_admin);
    }

    function isInList(address _account) public view override returns (bool) {
        return points[_account] > 0 ;
    }

    function hasPoints(address _account, uint256 _amount) public view override returns (bool) {
        return points[_account] >= _amount ;
    }

    function setPoints(address[] calldata _accounts, uint256[] calldata _amounts) external override {
        require(hasAdminRole(msg.sender) || hasOperatorRole(msg.sender), "PointList.setPoints: Sender must be operator");
        require(_accounts.length != 0, "PointList.setPoints: empty array");
        require(_accounts.length == _amounts.length, "PointList.setPoints: incorrect array length");
        uint totalPointsCache = totalPoints;
        for (uint i; i < _accounts.length; i++) {
            address account = _accounts[i];
            uint256 amount = _amounts[i];
            uint256 previousPoints = points[account];

            if (amount != previousPoints) {
                points[account] = amount;
                totalPointsCache = totalPointsCache.sub(previousPoints).add(amount);
                emit PointsUpdated(account, previousPoints, amount);
            }
        }
        totalPoints = totalPointsCache;
    }
}
