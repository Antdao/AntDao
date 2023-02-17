pragma solidity 0.6.12;

import "../OpenZeppelin/math/SafeMath.sol";
import "./ANTAccessControls.sol";
import "../interfaces/IPointList.sol";

contract MaxList is IPointList, ANTAccessControls {
    using SafeMath for uint;

    uint256 public maxPoints;

    event PointsUpdated(uint256 oldPoints, uint256 newPoints);

    constructor() public {}

    function initPointList(address _admin) public override {
        initAccessControls(_admin);
    }

    function points(address _account) public view returns (uint256) {
        return maxPoints;
    }

    function isInList(address _account) public view override returns (bool) {
        return true;
    }

    function hasPoints(address _account, uint256 _amount) public view override returns (bool) {
        return maxPoints >= _amount ;
    }

    function setPoints(address[] memory _accounts, uint256[] memory _amounts) external override {
        require(hasAdminRole(msg.sender) || hasOperatorRole(msg.sender), "MaxList.setPoints: Sender must be operator");
        require(_amounts.length == 1);
        maxPoints = _amounts[0];
        emit PointsUpdated(maxPoints, _amounts[0]);
    }
}
