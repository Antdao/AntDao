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


contract Crowdsale is IAntMarket, ANTAccessControls, BoringBatchable, SafeTransfer, Documents , ReentrancyGuard  {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringERC20 for IERC20;

    uint256 public constant override marketTemplate = 1;

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 private constant AUCTION_TOKEN_DECIMAL_PLACES = 18;
    uint256 private constant AUCTION_TOKEN_DECIMALS = 10 ** AUCTION_TOKEN_DECIMAL_PLACES;

    struct MarketPrice {
        uint128 rate;
        uint128 goal; 
    }
    MarketPrice public marketPrice;

    struct MarketInfo {
        uint64 startTime;
        uint64 endTime; 
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    struct MarketStatus {
        uint128 commitmentsTotal;
        bool finalized;
        bool usePointList;
    }
    MarketStatus public marketStatus;

    address public auctionToken;
    address payable public wallet;
    address public paymentCurrency;
    address public pointList;

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public claimed;

    event AuctionDeployed(address funder, address token, address paymentCurrency, uint256 totalTokens, address admin, address wallet);
    
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime); 
    event AuctionPriceUpdated(uint256 rate, uint256 goal); 
    event AuctionWalletUpdated(address wallet); 
    event AuctionPointListUpdated(address pointList, bool enabled);

    event AddedCommitment(address addr, uint256 commitment);

    event AuctionFinalized();
    event AuctionCancelled();

    function initCrowdsale(
        address _funder,
        address _token,
        address _paymentCurrency,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rate,
        uint256 _goal,
        address _admin,
        address _pointList,
        address payable _wallet
    ) public {
        require(_endTime < 10000000000, "Crowdsale: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "Crowdsale: start time is before current time");
        require(_endTime > _startTime, "Crowdsale: start time is not before end time");
        require(_rate > 0, "Crowdsale: rate is 0");
        require(_wallet != address(0), "Crowdsale: wallet is the zero address");
        require(_admin != address(0), "Crowdsale: admin is the zero address");
        require(_totalTokens > 0, "Crowdsale: total tokens is 0");
        require(_goal > 0, "Crowdsale: goal is 0");
        require(IERC20(_token).decimals() == AUCTION_TOKEN_DECIMAL_PLACES, "Crowdsale: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IERC20(_paymentCurrency).decimals() > 0, "Crowdsale: Payment currency is not ERC20");
        }

        marketPrice.rate = BoringMath.to128(_rate);
        marketPrice.goal = BoringMath.to128(_goal);

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        wallet = _wallet;

        initAccessControls(_admin);

        _setList(_pointList);
        
        require(_getTokenAmount(_goal) <= _totalTokens, "Crowdsale: goal should be equal to or lower than total tokens");

        _safeTransferFrom(_token, _funder, _totalTokens);

        emit AuctionDeployed(_funder, _token, _paymentCurrency, _totalTokens, _admin, _wallet);
        emit AuctionTimeUpdated(_startTime, _endTime);
        emit AuctionPriceUpdated(_rate, _goal);
    }


    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }

    function marketParticipationAgreement() public pure returns (string memory) {
        return "I understand that I am interacting with a smart contract. I understand that tokens commited are subject to the token issuer and local laws where applicable. I reviewed code of the smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings";
    }
    function revertBecauseUserDidNotProvideAgreement() internal pure {
        revert("No agreement provided, please review the smart contract before interacting with it");
    }

    function commitEth(
        address payable _beneficiary,
        bool readAndAgreedToMarketParticipationAgreement
    ) 
        public payable   nonReentrant    
    {
        require(paymentCurrency == ETH_ADDRESS, "Crowdsale: Payment currency is not ETH"); 
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }

        
        uint256 ethToTransfer = calculateCommitment(msg.value);

        
        uint256 ethToRefund = msg.value.sub(ethToTransfer);
        if (ethToTransfer > 0) {
            _addCommitment(_beneficiary, ethToTransfer);
        }

        
        if (ethToRefund > 0) {
            _beneficiary.transfer(ethToRefund);
        }

        
        require(marketStatus.commitmentsTotal <= address(this).balance, "CrowdSale: The committed ETH exceeds the balance");
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
        require(address(paymentCurrency) != ETH_ADDRESS, "Crowdsale: Payment currency is not a token");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        uint256 tokensToTransfer = calculateCommitment(_amount);
        if (tokensToTransfer > 0) {
            _safeTransferFrom(paymentCurrency, msg.sender, tokensToTransfer);
            _addCommitment(_from, tokensToTransfer);
        }
    }

    function calculateCommitment(uint256 _commitment)
        public
        view
        returns (uint256 committed)
    {
        uint256 tokens = _getTokenAmount(_commitment);
        uint256 tokensCommited =_getTokenAmount(uint256(marketStatus.commitmentsTotal));
        if ( tokensCommited.add(tokens) > uint256(marketInfo.totalTokens)) {
            return _getTokenPrice(uint256(marketInfo.totalTokens).sub(tokensCommited));
        }
        return _commitment;
    }

    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(block.timestamp >= uint256(marketInfo.startTime) && block.timestamp <= uint256(marketInfo.endTime), "Crowdsale: outside auction hours");
        require(_addr != address(0), "Crowdsale: beneficiary is the zero address");
        require(!marketStatus.finalized, "CrowdSale: Auction is finalized");
        uint256 newCommitment = commitments[_addr].add(_commitment);
        if (marketStatus.usePointList) {
            require(IPointList(pointList).hasPoints(_addr, newCommitment));
        }

        commitments[_addr] = newCommitment;

        marketStatus.commitmentsTotal = BoringMath.to128(uint256(marketStatus.commitmentsTotal).add(_commitment));

        emit AddedCommitment(_addr, _commitment);
    }

    function withdrawTokens() public  {
        withdrawTokens(msg.sender);
    }

    function withdrawTokens(address payable beneficiary) public   nonReentrant  {    
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "Crowdsale: not finalized");
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "Crowdsale: no tokens to claim"); 
            claimed[beneficiary] = claimed[beneficiary].add(tokensToClaim);
            _safeTokenPayment(auctionToken, beneficiary, tokensToClaim);            
        } else {
            require(block.timestamp > uint256(marketInfo.endTime), "Crowdsale: auction has not finished yet");
            uint256 accountBalance = commitments[beneficiary];
            commitments[beneficiary] = 0;  
            _safeTokenPayment(paymentCurrency, beneficiary, accountBalance);
        }
    }

