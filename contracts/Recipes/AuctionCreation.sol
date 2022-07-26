// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "../interfaces/IERC20.sol";
import "../Utils/SafeTransfer.sol";

interface IAntTokenFactory {
  function createToken(
    uint256 _templateId,
    address payable _integratorFeeAccount,
    bytes calldata _data
  ) external payable returns (address token);
}

interface IPointList {
  function deployPointList(
    address _listOwner,
    address[] calldata _accounts,
    uint256[] calldata _amounts
  ) external payable returns (address pointList);
}

interface IAntLauncher {
  function createLauncher(
    uint256 _templateId,
    address _token,
    uint256 _tokenSupply,
    address payable _integratorFeeAccount,
    bytes calldata _data
  ) external payable returns (address newLauncher);
}

interface IAntMarket {
  function createMarket(
    uint256 _templateId,
    address _token,
    uint256 _tokenSupply,
    address payable _integratorFeeAccount,
    bytes calldata _data
  ) external payable returns (address newMarket);

  function setAuctionWallet(address payable _wallet) external;

  function addAdminRole(address _address) external;

  function getAuctionTemplate(uint256 _templateId) external view returns (address);
}

interface IAuctionTemplate {
  function marketTemplate() external view returns (uint256);
}

contract AuctionCreation is SafeTransfer {

  IAntTokenFactory public antTokenFactory;
  IPointList public pointListFactory;
  IAntLauncher public antLauncher;
  IAntMarket public antMarket;
  address public factory;

  constructor(
    IAntTokenFactory _antTokenFactory,
    IPointList _pointListFactory,
    IAntLauncher _antLauncher,
    IAntMarket _antMarket,
    address _factory
  ) public {
    antTokenFactory = _antTokenFactory;
    pointListFactory = _pointListFactory;
    antLauncher = _antLauncher;
    antMarket = _antMarket;
    factory = _factory;
  }

  function prepareAnt(
    bytes memory tokenFactoryData,
    address[] memory _accounts,
    uint256[] memory _amounts,
    bytes memory marketData,
    bytes memory launcherData
  ) external payable {
    require(_accounts.length == _amounts.length, '!len');

    address token = createToken(tokenFactoryData);

    address pointList = createPointList(_accounts, _amounts);

    (address newMarket, uint256 tokenForSale) = createMarket(marketData, token, pointList);

    IAntMarket(newMarket).addAdminRole(msg.sender);

    createLauncher(launcherData, token, tokenForSale, newMarket);

    uint256 tokenBalanceRemaining = IERC20(token).balanceOf(address(this));
    if (tokenBalanceRemaining > 0) {
      _safeTransfer(token, msg.sender, tokenBalanceRemaining);
    }
  }

  function createToken(bytes memory tokenFactoryData) internal returns (address token) {
    (
      bool isDeployed,
      address deployedToken,
      uint256 _antTokenFactoryTemplateId,
      string memory _name,
      string memory _symbol,
      uint256 _initialSupply
    ) = abi.decode(tokenFactoryData, (bool, address, uint256, string, string, uint256));
    if (isDeployed) {
      token = deployedToken;
      IERC20(deployedToken).transferFrom(msg.sender, address(this), _initialSupply);
    } else {
      token = antTokenFactory.createToken(
        _antTokenFactoryTemplateId,
        address(0),
        abi.encode(_name, _symbol, msg.sender, _initialSupply)
      );
    }

    IERC20(token).approve(address(antMarket), _initialSupply);
    IERC20(token).approve(address(antLauncher), _initialSupply);
  }

  function createPointList(address[] memory _accounts, uint256[] memory _amounts) internal returns (address pointList) {
    if (_accounts.length != 0) {
      pointList = pointListFactory.deployPointList(msg.sender, _accounts, _amounts);
    }
  }

  function createMarket(bytes memory marketData, address token, address pointList ) internal returns (address newMarket, uint256 tokenForSale) {
    (uint256 _marketTemplateId, bytes memory mData) = abi.decode(marketData, (uint256, bytes));

    tokenForSale = getTokenForSale(_marketTemplateId, mData);

    newMarket = antMarket.createMarket(
      _marketTemplateId,
      token,
      tokenForSale,
      address(0),
      abi.encodePacked(abi.encode(address(antMarket), token), mData, abi.encode(address(this), pointList, msg.sender))
    );
  }

  function createLauncher(bytes memory launcherData,address token, uint256 tokenForSale,address newMarket) internal returns (address newLauncher) {
    (uint256 _launcherTemplateId, uint256 _liquidityPercent, uint256 _locktime) = abi.decode(
      launcherData,
      (uint256, uint256, uint256)
    );

    if(_liquidityPercent > 0) {
      newLauncher = antLauncher.createLauncher(
        _launcherTemplateId,
        token,
        (tokenForSale * _liquidityPercent) / 10000,
        address(0),
        abi.encode(newMarket, factory, msg.sender, msg.sender, _liquidityPercent, _locktime)
      );

      IAntMarket(newMarket).setAuctionWallet(payable(newLauncher));
    }
  }

  function getTokenForSale(uint256 marketTemplateId, bytes memory mData) internal view returns (uint256 tokenForSale) {
    address auctionTemplate = antMarket.getAuctionTemplate(marketTemplateId);

    uint256 auctionTemplateId = IAuctionTemplate(auctionTemplate).marketTemplate();

    if (auctionTemplateId == 1) {
      (, tokenForSale) = abi.decode(mData, (uint256, uint256));
    } else {
      tokenForSale = abi.decode(mData, (uint256));
    }
  }
}
