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



contract BatchAuction is  IAntMarket, ANTAccessControls, BoringBatchable, SafeTransfer, Documents, ReentrancyGuard  {

    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringERC20 for IERC20;

    uint256 public constant override marketTemplate = 3;

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct MarketInfo {
        uint64 startTime;
        uint64 endTime; 
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    struct MarketStatus {
        uint128 commitmentsTotal;
        uint128 minimumCommitmentAmount;
        bool finalized;
        bool usePointList;
    }

    MarketStatus public marketStatus;

    address public auctionToken;
    address public paymentCurrency;
    address public pointList;
    address payable public wallet; 

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public claimed;

    event AuctionDeployed(address funder, address token, uint256 totalTokens, address paymentCurrency, address admin, address wallet); 
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime); 
    event AuctionPriceUpdated(uint256 minimumCommitmentAmount); 
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
        uint256 _minimumCommitmentAmount,
        address _admin,
        address _pointList,
        address payable _wallet
    ) public {
        require(_endTime < 10000000000, "BatchAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "BatchAuction: start time is before current time");
        require(_endTime > _startTime, "BatchAuction: end time must be older than start time");
        require(_totalTokens > 0,"BatchAuction: total tokens must be greater than zero");
        require(_admin != address(0), "BatchAuction: admin is the zero address");
        require(_wallet != address(0), "BatchAuction: wallet is the zero address");
        require(IERC20(_token).decimals() == 18, "BatchAuction: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IERC20(_paymentCurrency).decimals() > 0, "BatchAuction: Payment currency is not ERC20");
        }

        marketStatus.minimumCommitmentAmount = BoringMath.to128(_minimumCommitmentAmount);
        
        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        wallet = _wallet;

        initAccessControls(_admin);

        _setList(_pointList);
        _safeTransferFrom(auctionToken, _funder, _totalTokens);

        emit AuctionDeployed(_funder, _token, _totalTokens, _paymentCurrency, _admin, _wallet);
        emit AuctionTimeUpdated(_startTime, _endTime);
        emit AuctionPriceUpdated(_minimumCommitmentAmount);
    }


    
    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }
    
    function marketParticipationAgreement() public pure returns (string memory) {
        return "I understand that I am interacting with a smart contract. I understand that tokens commited are subject to the token issuer and local laws where applicable. I have reviewed the code of this smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings";
    }
    function revertBecauseUserDidNotProvideAgreement() internal pure {
        revert("No agreement provided, please review the smart contract before interacting with it");
    }

    function commitEth(address payable _beneficiary, bool readAndAgreedToMarketParticipationAgreement) public payable {
        require(paymentCurrency == ETH_ADDRESS, "BatchAuction: payment currency is not ETH");

        require(msg.value > 0, "BatchAuction: Value must be higher than 0");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        _addCommitment(_beneficiary, msg.value);

        require(marketStatus.commitmentsTotal <= address(this).balance, "BatchAuction: The committed ETH exceeds the balance");
    }

    function commitTokens(uint256 _amount, bool readAndAgreedToMarketParticipationAgreement) public {
        commitTokensFrom(msg.sender, _amount, readAndAgreedToMarketParticipationAgreement);
    }

    
    function commitTokensFrom(address _from, uint256 _amount, bool readAndAgreedToMarketParticipationAgreement) public   nonReentrant  {
        require(paymentCurrency != ETH_ADDRESS, "BatchAuction: Payment currency is not a token");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        require(_amount> 0, "BatchAuction: Value must be higher than 0");
        _safeTransferFrom(paymentCurrency, msg.sender, _amount);
        _addCommitment(_from, _amount);

    }


    
    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(block.timestamp >= marketInfo.startTime && block.timestamp <= marketInfo.endTime, "BatchAuction: outside auction hours"); 

        uint256 newCommitment = commitments[_addr].add(_commitment);
        if (marketStatus.usePointList) {
            require(IPointList(pointList).hasPoints(_addr, newCommitment));
        }
        commitments[_addr] = newCommitment;
        marketStatus.commitmentsTotal = BoringMath.to128(uint256(marketStatus.commitmentsTotal).add(_commitment));
        emit AddedCommitment(_addr, _commitment);
    }

    
    function _getTokenAmount(uint256 amount) internal view returns (uint256) { 
        if (marketStatus.commitmentsTotal == 0) return 0;
        return amount.mul(1e18).div(tokenPrice());
    }

    
    function tokenPrice() public view returns (uint256) {
        return uint256(marketStatus.commitmentsTotal)
            .mul(1e18).div(uint256(marketInfo.totalTokens));
    }


    
    function finalize() public    nonReentrant 
    {
        require(hasAdminRole(msg.sender) 
                || wallet == msg.sender
                || hasSmartContractRole(msg.sender) 
                || finalizeTimeExpired(),  "BatchAuction: Sender must be admin");
        require(!marketStatus.finalized, "BatchAuction: Auction has already finalized");
        require(marketInfo.totalTokens > 0, "Not initialized");
        require(block.timestamp > marketInfo.endTime, "BatchAuction: Auction has not finished yet");
        if (auctionSuccessful()) {
            
            _safeTokenPayment(paymentCurrency, wallet, uint256(marketStatus.commitmentsTotal));
        } else {
            
            _safeTokenPayment(auctionToken, wallet, marketInfo.totalTokens);
        }
        marketStatus.finalized = true;
        emit AuctionFinalized();
    }

    
    function cancelAuction() public   nonReentrant  
    {
        require(hasAdminRole(msg.sender));
        MarketStatus storage status = marketStatus;
        require(!status.finalized, "BatchAuction: already finalized");
        require( uint256(status.commitmentsTotal) == 0, "BatchAuction: Funds already raised" );

        _safeTokenPayment(auctionToken, wallet, uint256(marketInfo.totalTokens));

        status.finalized = true;
        emit AuctionCancelled();
    }

    
    function withdrawTokens() public  {
        withdrawTokens(msg.sender);
    }

    
    function withdrawTokens(address payable beneficiary) public   nonReentrant  {
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "BatchAuction: not finalized");
           
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "BatchAuction: No tokens to claim");
            claimed[beneficiary] = claimed[beneficiary].add(tokensToClaim);

            _safeTokenPayment(auctionToken, beneficiary, tokensToClaim);
        } else {
            
            require(block.timestamp > marketInfo.endTime, "BatchAuction: Auction has not finished yet");
            uint256 fundsCommitted = commitments[beneficiary];
            require(fundsCommitted > 0, "BatchAuction: No funds committed");
            commitments[beneficiary] = 0; 
            _safeTokenPayment(paymentCurrency, beneficiary, fundsCommitted);
        }
    }


    
    function tokensClaimable(address _user) public view returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) return 0;
        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        claimerCommitment = _getTokenAmount(commitments[_user]);
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        if(claimerCommitment > unclaimedTokens){
            claimerCommitment = unclaimedTokens;
        }
    }
    
    
    function auctionSuccessful() public view returns (bool) {
        return uint256(marketStatus.commitmentsTotal) >= uint256(marketStatus.minimumCommitmentAmount) && uint256(marketStatus.commitmentsTotal) > 0;
    }

    
    function auctionEnded() public view returns (bool) {
        return block.timestamp > marketInfo.endTime;
    }

    
