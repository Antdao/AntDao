pragma solidity 0.6.12;

import "../OpenZeppelin/math/SafeMath.sol";
import "../Utils/Owned.sol";
import "../Utils/CloneFactory.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPointList.sol";
import "../Utils/SafeTransfer.sol";
import "./ANTAccessControls.sol";

contract ListFactory is CloneFactory, SafeTransfer {
    using SafeMath for uint;

    ANTAccessControls public accessControls;

    bool private initialised;

    address public pointListTemplate;

    address public newAddress;

    uint256 public minimumFee;

    mapping(address => bool) public isChild;

    address[] public lists;

    address payable public antDiv;

    event PointListDeployed(address indexed operator, address indexed addr, address pointList, address owner);

    event FactoryDeprecated(address newAddress);

    event MinimumFeeUpdated(uint oldFee, uint newFee);

    event AntInitListFactory();

    function initListFactory(address _accessControls, address _pointListTemplate, uint256 _minimumFee) external  {
        require(!initialised);
        require(_accessControls != address(0), "Incorrect access controls");
        require(_pointListTemplate != address(0), "Incorrect list template");
        accessControls = ANTAccessControls(_accessControls);
        pointListTemplate = _pointListTemplate;
        minimumFee = _minimumFee;
        initialised = true;
        emit AntInitListFactory();
    }

    function numberOfChildren() external view returns (uint) {
        return lists.length;
    }

    function deprecateFactory(address _newAddress) external {
        require(accessControls.hasAdminRole(msg.sender), "ListFactory: Sender must be admin address");
        require(newAddress == address(0));
        emit FactoryDeprecated(_newAddress);
        newAddress = _newAddress;
    }

    function setMinimumFee(uint256 _minimumFee) external {
        require(accessControls.hasAdminRole(msg.sender), "ListFactory: Sender must be admin address");
        emit MinimumFeeUpdated(minimumFee, _minimumFee);
        minimumFee = _minimumFee;
    }

    function setDividends(address payable _divaddr) external  {
        require(accessControls.hasAdminRole(msg.sender), "ANTTokenFactory: Sender must be admin address");
        antDiv = _divaddr;
    }

    function deployPointList(
        address _listOwner,
        address[] calldata _accounts,
        uint256[] calldata _amounts
    )
        external payable returns (address pointList)
    {
        require(msg.value >= minimumFee);
        pointList = createClone(pointListTemplate);
        if (_accounts.length > 0) {
            IPointList(pointList).initPointList(address(this));
            IPointList(pointList).setPoints(_accounts, _amounts);
            ANTAccessControls(pointList).addAdminRole(_listOwner);
            ANTAccessControls(pointList).removeAdminRole(address(this));
        } else {
            IPointList(pointList).initPointList(_listOwner);
        }
        isChild[address(pointList)] = true;
        lists.push(address(pointList));
        emit PointListDeployed(msg.sender, address(pointList), pointListTemplate, _listOwner);
        if (msg.value > 0) {
            antDiv.transfer(msg.value);
        }
    }

    function transferAnyERC20Token(address _tokenAddress, uint256 _tokens) external returns (bool success) {
        require(accessControls.hasAdminRole(msg.sender), "ListFactory: Sender must be operator");
        _safeTransfer(_tokenAddress, antDiv, _tokens);
        return true;
    }

    receive () external payable {
        revert();
    }
}
