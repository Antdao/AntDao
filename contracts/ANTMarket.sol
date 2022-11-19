pragma solidity 0.6.12;

import "./Access/ANTAccessControls.sol";
import "./Utils/BoringMath.sol";
import "./Utils/SafeTransfer.sol";
import "./interfaces/IAntMarket.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IBentoBoxFactory.sol";
import "./OpenZeppelin/token/ERC20/SafeERC20.sol";

contract ANTMarket is SafeTransfer {

    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using SafeERC20 for IERC20;

    ANTAccessControls public accessControls;
    bytes32 public constant MARKET_MINTER_ROLE = keccak256("MARKET_MINTER_ROLE");

    bool private initialised;

    /// @notice Struct to track Auction template.
    struct Auction {
        bool exists;
        uint64 templateId;
        uint128 index;
    }

    address[] public auctions;

    uint256 public auctionTemplateId;

    IBentoBoxFactory public bentoBox;

    /// @notice Mapping from market template id to market template address.
    mapping(uint256 => address) private auctionTemplates;

    /// @notice Mapping from market template address to market template id.
    mapping(address => uint256) private auctionTemplateToId;

    /// @notice mapping from template type to template id
    mapping(uint256 => uint256) public currentTemplateId;

    /// @notice Mapping from auction created through this contract to Auction struct.
    mapping(address => Auction) public auctionInfo;

    /// @notice Struct to define fees.
    struct MarketFees {
        uint128 minimumFee;
        uint32 integratorFeePct;
    }

    MarketFees public marketFees;

    bool public locked;

    address payable public antDiv;

    event AntInitMarket(address sender);

    event AuctionTemplateAdded(address newAuction, uint256 templateId);

    event AuctionTemplateRemoved(address auction, uint256 templateId);

    event MarketCreated(address indexed owner, address indexed addr, address marketTemplate);

    constructor() public {
    }

    function initANTMarket(address _accessControls, address _bentoBox, address[] memory _templates) external {
        require(!initialised);
        require(_accessControls != address(0), "initANTMarket: accessControls cannot be set to zero");
        require(_bentoBox != address(0), "initANTMarket: bentoBox cannot be set to zero");

        accessControls = ANTAccessControls(_accessControls);
        bentoBox = IBentoBoxFactory(_bentoBox);

        for(uint i = 0; i < _templates.length; i++) {
            _addAuctionTemplate(_templates[i]);
        }
        locked = true;
        initialised = true;
        emit AntInitMarket(msg.sender);
    }

    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTMarket: Sender must be operator"
        );
        marketFees.minimumFee = BoringMath.to128(_amount);
    }

    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTMarket: Sender must be admin address"
        );
        locked = _locked;
    }


    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTMarket: Sender must be operator"
        );
        require(_amount <= 1000, "ANTMarket: Percentage is out of 1000");
        marketFees.integratorFeePct = BoringMath.to32(_amount);
    }

    function setDividends(address payable _divaddr) external {
        require(accessControls.hasAdminRole(msg.sender), "ANTMarket.setDev: Sender must be operator");
        require(_divaddr != address(0));
        antDiv = _divaddr;
    }

    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTMarket: Sender must be admin"
        );
        require(auctionTemplates[_templateId] != address(0), "ANTMarket: incorrect _templateId");
        require(IAntMarket(auctionTemplates[_templateId]).marketTemplate() == _templateType, "ANTMarket: incorrect _templateType");
        currentTemplateId[_templateType] = _templateId;
    }


    function hasMarketMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(MARKET_MINTER_ROLE, _address);
    }


    function deployMarket(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address newMarket)
    {
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasMarketMinterRole(msg.sender),
                "ANTMarket: Sender must be minter if locked"
            );
        }

        MarketFees memory _marketFees = marketFees;
        address auctionTemplate = auctionTemplates[_templateId];
        require(msg.value >= uint256(_marketFees.minimumFee), "ANTMarket: Failed to transfer minimumFee");
        require(auctionTemplate != address(0), "ANTMarket: Auction template doesn't exist");
        uint256 integratorFee = 0;
        uint256 antFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != antDiv) {
            integratorFee = antFee * uint256(_marketFees.integratorFeePct) / 1000;
            antFee = antFee - integratorFee;
        }

        newMarket = bentoBox.deploy(auctionTemplate, "", false);
        auctionInfo[newMarket] = Auction(true, BoringMath.to64(_templateId), BoringMath.to128(auctions.length));
        auctions.push(newMarket);
        emit MarketCreated(msg.sender, newMarket, auctionTemplate);
        if (antFee > 0) {
            antDiv.transfer(antFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }

    function createMarket(
        uint256 _templateId,
        address _token,
        uint256 _tokenSupply,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address newMarket)
    {
        newMarket = deployMarket(_templateId, _integratorFeeAccount);
        if (_tokenSupply > 0) {
            _safeTransferFrom(_token, msg.sender, _tokenSupply);
            IERC20(_token).safeApprove(newMarket, _tokenSupply);
        }
        IAntMarket(newMarket).initMarket(_data);

        if (_tokenSupply > 0) {
            uint256 remainingBalance = IERC20(_token).balanceOf(address(this));
            if (remainingBalance > 0) {
                _safeTransfer(_token, msg.sender, remainingBalance);
            }
        }
        return newMarket;
    }

    function addAuctionTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTMarket: Sender must be operator"
        );
        _addAuctionTemplate(_template);    
    }

    function removeAuctionTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "ANTMarket: Sender must be operator"
        );
        address template = auctionTemplates[_templateId];
        uint256 templateType = IAntMarket(template).marketTemplate();
        if (currentTemplateId[templateType] == _templateId) {
            delete currentTemplateId[templateType];
        }   
        auctionTemplates[_templateId] = address(0);
        delete auctionTemplateToId[template];
        emit AuctionTemplateRemoved(template, _templateId);
    }


