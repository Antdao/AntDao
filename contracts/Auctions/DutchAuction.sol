pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


import "../OpenZeppelin/utils/ReentrancyGuard.sol";
import "../Access/ANTAccessControls.sol";
import "../Utils/SafeTransfer.sol";
import "../Utils/BoringBatchable.sol";
import "../Utils/BoringMath.sol";
import "../Utils/BoringERC20.sol";
import "../Utils/Documents.sol";
import "../interfaces/IPointList.sol";
import "../interfaces/IAntMarket.sol";


contract DutchAuction is IAntMarket, ANTAccessControls, BoringBatchable, SafeTransfer, Documents , ReentrancyGuard  {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringERC20 for IERC20;

    uint256 public constant override marketTemplate = 2;
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct MarketInfo {
        uint64 startTime;
        uint64 endTime;
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    struct MarketPrice {
        uint128 startPrice;
        uint128 minimumPrice;
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
    event AuctionPriceUpdated(uint256 startPrice, uint256 minimumPrice); 
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
        uint256 _startPrice,
        uint256 _minimumPrice,
        address _admin,
        address _pointList,
        address payable _wallet
    ) public {
        require(_endTime < 10000000000, "DutchAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "DutchAuction: start time is before current time");
        require(_endTime > _startTime, "DutchAuction: end time must be older than start price");
        require(_totalTokens > 0,"DutchAuction: total tokens must be greater than zero");
        require(_startPrice > _minimumPrice, "DutchAuction: start price must be higher than minimum price");
        require(_minimumPrice > 0, "DutchAuction: minimum price must be greater than 0"); 
        require(_admin != address(0), "DutchAuction: admin is the zero address");
        require(_wallet != address(0), "DutchAuction: wallet is the zero address");
        require(IERC20(_token).decimals() == 18, "DutchAuction: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IERC20(_paymentCurrency).decimals() > 0, "DutchAuction: Payment currency is not ERC20");
        }

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        marketPrice.startPrice = BoringMath.to128(_startPrice);
        marketPrice.minimumPrice = BoringMath.to128(_minimumPrice);

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        wallet = _wallet;

        initAccessControls(_admin);

        _setList(_pointList);
        _safeTransferFrom(_token, _funder, _totalTokens);

        emit AuctionDeployed(_funder, _token, _totalTokens, _paymentCurrency, _admin, _wallet);
        emit AuctionTimeUpdated(_startTime, _endTime);
        emit AuctionPriceUpdated(_startPrice, _minimumPrice);
    }



   
    function tokenPrice() public view returns (uint256) {
        return uint256(marketStatus.commitmentsTotal).mul(1e18).div(uint256(marketInfo.totalTokens));
    }

   
    function priceFunction() public view returns (uint256) {
        if (block.timestamp <= uint256(marketInfo.startTime)) {
            return uint256(marketPrice.startPrice);
        }
        if (block.timestamp >= uint256(marketInfo.endTime)) {
            return uint256(marketPrice.minimumPrice);
        }

        return _currentPrice();
    }

    
    function clearingPrice() public view returns (uint256) {

        uint256 _tokenPrice = tokenPrice();
        uint256 _currentPrice = priceFunction();
        return _tokenPrice > _currentPrice ? _tokenPrice : _currentPrice;

    }


    
    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }

      
    function marketParticipationAgreement() public pure returns (string memory) {
        return "I understand that I'm interacting with a smart contract. I understand that tokens committed are subject to the token issuer and local laws where applicable. I reviewed code of the smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings";
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
        require(paymentCurrency == ETH_ADDRESS, "DutchAuction: payment currency is not ETH address"); 
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

        require(marketStatus.commitmentsTotal <= address(this).balance, "DutchAuction: The committed ETH exceeds the balance");
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
        require(address(paymentCurrency) != ETH_ADDRESS, "DutchAuction: Payment currency is not a token");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        uint256 tokensToTransfer = calculateCommitment(_amount);
        if (tokensToTransfer > 0) {
            _safeTransferFrom(paymentCurrency, msg.sender, tokensToTransfer);
            _addCommitment(_from, tokensToTransfer);
        }
    }

    
    function priceDrop() public view returns (uint256) {
        MarketInfo memory _marketInfo = marketInfo;
        MarketPrice memory _marketPrice = marketPrice;

        uint256 numerator = uint256(_marketPrice.startPrice.sub(_marketPrice.minimumPrice));
        uint256 denominator = uint256(_marketInfo.endTime.sub(_marketInfo.startTime));
        return numerator / denominator;
    }


   
    function tokensClaimable(address _user) public view returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) return 0;
        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));

        claimerCommitment = commitments[_user].mul(uint256(marketInfo.totalTokens)).div(uint256(marketStatus.commitmentsTotal));
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        if(claimerCommitment > unclaimedTokens){
            claimerCommitment = unclaimedTokens;
        }
    }

    
    function totalTokensCommitted() public view returns (uint256) {
        return uint256(marketStatus.commitmentsTotal).mul(1e18).div(clearingPrice());
    }

    
    function calculateCommitment(uint256 _commitment) public view returns (uint256 committed) {
        uint256 maxCommitment = uint256(marketInfo.totalTokens).mul(clearingPrice()).div(1e18);
        if (uint256(marketStatus.commitmentsTotal).add(_commitment) > maxCommitment) {
            return maxCommitment.sub(uint256(marketStatus.commitmentsTotal));
        }
        return _commitment;
    }

    
    function isOpen() public view returns (bool) {
        return block.timestamp >= uint256(marketInfo.startTime) && block.timestamp <= uint256(marketInfo.endTime);
    }

    
    function auctionSuccessful() public view returns (bool) {
        return tokenPrice() >= clearingPrice();
    }

    
    function auctionEnded() public view returns (bool) {
        return auctionSuccessful() || block.timestamp > uint256(marketInfo.endTime);
    }

    
    function finalized() public view returns (bool) {
        return marketStatus.finalized;
    }

    
    function finalizeTimeExpired() public view returns (bool) {
        return uint256(marketInfo.endTime) + 7 days < block.timestamp;
    }

    
    function _currentPrice() private view returns (uint256) {
        MarketInfo memory _marketInfo = marketInfo;
        MarketPrice memory _marketPrice = marketPrice;
        uint256 priceDiff = block.timestamp.sub(uint256(_marketInfo.startTime)).mul(
            uint256(_marketPrice.startPrice.sub(_marketPrice.minimumPrice))
        ) / uint256(_marketInfo.endTime.sub(_marketInfo.startTime));        
        return uint256(_marketPrice.startPrice).sub(priceDiff);
    }

