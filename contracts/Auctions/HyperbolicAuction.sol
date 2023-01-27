pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../OpenZeppelin/utils/ReentrancyGuard.sol";
import "../Access/ANTAccessControls.sol";
import "../Utils/SafeTransfer.sol";
import "../Utils/BoringBatchable.sol";
import "../Utils/BoringERC20.sol";
import "../Utils/BoringMath.sol";
import "../Utils/Documents.sol";
import "../interfaces/IPointList.sol";
import "../interfaces/IAntMarket.sol";

contract HyperbolicAuction is IAntMarket, ANTAccessControls, BoringBatchable, SafeTransfer, Documents , ReentrancyGuard  {
    using BoringERC20 for IERC20;
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    uint256 public constant override marketTemplate = 4;
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct MarketInfo {
        uint64 startTime;
        uint64 endTime;
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    struct MarketPrice {
        uint128 minimumPrice;
        uint128 alpha;
       
    }
    MarketPrice public marketPrice;

    struct MarketStatus {
        uint128 commitmentsTotal;
        bool finalized;
        bool usePointList;

    }
    MarketStatus public marketStatus;

    address public auctionToken; 
    address public paymentCurrency;  
    address payable public wallet;  
    address public pointList;

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public claimed;
    
    event AuctionDeployed(address funder, address token, uint256 totalTokens, address paymentCurrency, address admin, address wallet);
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime); 
    event AuctionPriceUpdated(uint256 minimumPrice); 
    event AuctionWalletUpdated(address wallet); 
    event AuctionPointListUpdated(address pointList, bool enabled);
    event AddedCommitment(address addr, uint256 commitment);
    event TokensWithdrawn(address token, address to, uint256 amount);
    event AuctionFinalized();
    event AuctionCancelled();

    function initAuction(
        address _funder,
        address _token,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        address _paymentCurrency,
        uint256 _factor,
        uint256 _minimumPrice,
        address _admin,
        address _pointList,
        address payable _wallet
    ) public {
        require(_endTime < 10000000000, "HyperbolicAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "HyperbolicAuction: start time is before current time");
        require(_totalTokens > 0,"HyperbolicAuction: total tokens must be greater than zero");
        require(_endTime > _startTime, "HyperbolicAuction: end time must be older than start time");
        require(_minimumPrice > 0, "HyperbolicAuction: minimum price must be greater than 0"); 
        require(_wallet != address(0), "HyperbolicAuction: wallet is the zero address");
        require(_admin != address(0), "HyperbolicAuction: admin is the zero address");
        require(_token != address(0), "HyperbolicAuction: token is the zero address");
        require(IERC20(_token).decimals() == 18, "HyperbolicAuction: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IERC20(_paymentCurrency).decimals() > 0, "HyperbolicAuction: Payment currency is not ERC20");
        }

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        marketPrice.minimumPrice = BoringMath.to128(_minimumPrice);

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        wallet = _wallet;

        initAccessControls(_admin);
        
        _setList(_pointList);

        uint256 _duration = _endTime - _startTime;
        uint256 _alpha = _duration.mul(_minimumPrice);
        marketPrice.alpha = BoringMath.to128(_alpha);

        _safeTransferFrom(_token, _funder, _totalTokens);

        emit AuctionDeployed(_funder, _token, _totalTokens, _paymentCurrency, _admin, _wallet);
        emit AuctionTimeUpdated(_startTime, _endTime);
        emit AuctionPriceUpdated(_minimumPrice);
    }


    function tokenPrice() public view returns (uint256) {
        return uint256(marketStatus.commitmentsTotal)
            .mul(1e18).div(uint256(marketInfo.totalTokens));
    }

    function priceFunction() public view returns (uint256) {
        if (block.timestamp <= uint256(marketInfo.startTime)) {
            return uint256(-1);
        }
        if (block.timestamp >= uint256(marketInfo.endTime)) {
            return uint256(marketPrice.minimumPrice);
        }
        return _currentPrice();
    }

    function clearingPrice() public view returns (uint256) {
        if (tokenPrice() > priceFunction()) {
            return tokenPrice();
        }
        return priceFunction();
    }

    function _currentPrice() private view returns (uint256) {
        uint256 elapsed = block.timestamp.sub(uint256(marketInfo.startTime));
        uint256 currentPrice = uint256(marketPrice.alpha).div(elapsed);
        return currentPrice;
    }

    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }

    function marketParticipationAgreement() public pure returns (string memory) {
        return "I understand that I'm interacting with a smart contract. I understand that tokens commited are subject to the token issuer and local laws where applicable. I reviewed code of the smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings";
    }
    function revertBecauseUserDidNotProvideAgreement() internal pure {
        revert("No agreement provided, please review the smart contract before interacting with it");
    }

    function commitEth(
        address payable _beneficiary,
        bool readAndAgreedToMarketParticipationAgreement
    ) 
        public payable
    {
        require(paymentCurrency == ETH_ADDRESS, "HyperbolicAuction: payment currency is not ETH address"); 
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        require(msg.value > 0, "HyperbolicAuction: Value must be higher than 0");
        uint256 ethToTransfer = calculateCommitment(msg.value);

        uint256 ethToRefund = msg.value.sub(ethToTransfer);
        if (ethToTransfer > 0) {
            _addCommitment(_beneficiary, ethToTransfer);
        }
        if (ethToRefund > 0) {
            _beneficiary.transfer(ethToRefund);
        }

        require(marketStatus.commitmentsTotal <= address(this).balance, "HyperbolicAuction: The committed ETH exceeds the balance");
    }

    function commitTokens(uint256 _amount, bool readAndAgreedToMarketParticipationAgreement) public {
        commitTokensFrom(msg.sender, _amount, readAndAgreedToMarketParticipationAgreement);
    }

    function commitTokensFrom(
        address _from,
        uint256 _amount,
        bool readAndAgreedToMarketParticipationAgreement
    )
        public   nonReentrant  
    {
        require(paymentCurrency != ETH_ADDRESS, "HyperbolicAuction: payment currency is not a token");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        uint256 tokensToTransfer = calculateCommitment(_amount);
        if (tokensToTransfer > 0) {
            _safeTransferFrom(paymentCurrency, msg.sender, tokensToTransfer);
            _addCommitment(_from, tokensToTransfer);
        }
    }
