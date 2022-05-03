pragma solidity 0.6.12;

import "../OpenZeppelin/utils/ReentrancyGuard.sol";
import "../Access/ANTAccessControls.sol";
import "../Utils/SafeTransfer.sol";
import "../Utils/BoringMath.sol";
import "../UniswapV2/UniswapV2Library.sol";
import "../UniswapV2/interfaces/IUniswapV2Pair.sol";
import "../UniswapV2/interfaces/IUniswapV2Factory.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IAntAuction.sol";



contract PostAuctionLauncher is ANTAccessControls, SafeTransfer, ReentrancyGuard {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringMath32 for uint32;
    using BoringMath16 for uint16;


    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant LIQUIDITY_PRECISION = 10000;
    uint256 public constant liquidityTemplate = 3;
    IERC20 public token1;
    IERC20 public token2;
    IUniswapV2Factory public factory;
    address private immutable weth;
    address public tokenPair;
    address public wallet;
    IAntAuction public market;

    struct LauncherInfo {
        uint32 locktime;
        uint64 unlock;
        uint16 liquidityPercent;
        bool launched;
        uint128 liquidityAdded;
    }
    LauncherInfo public launcherInfo;

    event InitLiquidityLauncher(address indexed token1, address indexed token2, address factory, address sender);
    event LiquidityAdded(uint256 liquidity);
    event WalletUpdated(address indexed wallet);
    event LauncherCancelled(address indexed wallet);

    constructor (address _weth) public {
        weth = _weth;
    }


    function initAuctionLauncher(
            address _market,
            address _factory,
            address _admin,
            address _wallet,
            uint256 _liquidityPercent,
            uint256 _locktime
    )
        public
    {
        require(_locktime < 10000000000, 'PostAuction: Enter an unix timestamp in seconds, not miliseconds');
        require(_liquidityPercent <= LIQUIDITY_PRECISION, 'PostAuction: Liquidity percentage greater than 100.00% (>10000)');
        require(_liquidityPercent > 0, 'PostAuction: Liquidity percentage equals zero');
        require(_admin != address(0), "PostAuction: admin is the zero address");
        require(_wallet != address(0), "PostAuction: wallet is the zero address");

        initAccessControls(_admin);

        market = IAntAuction(_market);
        token1 = IERC20(market.paymentCurrency());
        token2 = IERC20(market.auctionToken());

        if (address(token1) == ETH_ADDRESS) {
            token1 = IERC20(weth);
        }

        uint256 d1 = uint256(token1.decimals());
        uint256 d2 = uint256(token2.decimals());
        require(d2 >= d1);

        factory = IUniswapV2Factory(_factory);
        bytes32 pairCodeHash = IUniswapV2Factory(_factory).pairCodeHash();
        tokenPair = UniswapV2Library.pairFor(_factory, address(token1), address(token2), pairCodeHash);
   
        wallet = _wallet;
        launcherInfo.liquidityPercent = BoringMath.to16(_liquidityPercent);
        launcherInfo.locktime = BoringMath.to32(_locktime);

        uint256 initalTokenAmount = market.getTotalTokens().mul(_liquidityPercent).div(LIQUIDITY_PRECISION);
        _safeTransferFrom(address(token2), msg.sender, initalTokenAmount);

        emit InitLiquidityLauncher(address(token1), address(token2), address(_factory), _admin);
    }

    receive() external payable {
        if(msg.sender != weth ){
             depositETH();
        }
    }

    function depositETH() public payable {
        require(address(token1) == weth || address(token2) == weth, "PostAuction: Launcher not accepting ETH");
        if (msg.value > 0 ) {
            IWETH(weth).deposit{value : msg.value}();
        }
    }

    function depositToken1(uint256 _amount) external returns (bool success) {
        return _deposit( address(token1), msg.sender, _amount);
    }

    function depositToken2(uint256 _amount) external returns (bool success) {
        return _deposit( address(token2), msg.sender, _amount);
    }

    function _deposit(address _token, address _from, uint _amount) internal returns (bool success) {
        require(!launcherInfo.launched, "PostAuction: Must first launch liquidity");
        require(launcherInfo.liquidityAdded == 0, "PostAuction: Liquidity already added");

        require(_amount > 0, "PostAuction: Token amount must be greater than 0");
        _safeTransferFrom(_token, _from, _amount);
        return true;
    }
    
    function marketConnected() public view returns (bool)  {
        return market.wallet() == address(this);
    }

    function finalize() external nonReentrant returns (uint256 liquidity) {
        require(marketConnected(), "PostAuction: Auction must have this launcher address set as the destination wallet");
        require(!launcherInfo.launched);

        if (!market.finalized()) {
            market.finalize();
        }

        launcherInfo.launched = true;
        if (!market.auctionSuccessful() ) {
            return 0;
        }

        uint256 launcherBalance = address(this).balance;
        if (launcherBalance > 0 ) {
            IWETH(weth).deposit{value : launcherBalance}();
        }
        
        (uint256 token1Amount, uint256 token2Amount) =  getTokenAmounts();

         if (token1Amount == 0 || token2Amount == 0 ) {
            return 0;
        }

        address pair = factory.getPair(address(token1), address(token2));
        require(pair == address(0) || getLPBalance() == 0, "PostLiquidity: Pair not new");
        if(pair == address(0)) {
            createPool();
        }

        _safeTransfer(address(token1), tokenPair, token1Amount);
        _safeTransfer(address(token2), tokenPair, token2Amount);
        liquidity = IUniswapV2Pair(tokenPair).mint(address(this));
        launcherInfo.liquidityAdded = BoringMath.to128(uint256(launcherInfo.liquidityAdded).add(liquidity));

        if (launcherInfo.unlock == 0 ) {
            launcherInfo.unlock = BoringMath.to64(block.timestamp + uint256(launcherInfo.locktime));
        }
        emit LiquidityAdded(liquidity);
    }


    function getTokenAmounts() public view returns (uint256 token1Amount, uint256 token2Amount) {
        token1Amount = getToken1Balance().mul(uint256(launcherInfo.liquidityPercent)).div(LIQUIDITY_PRECISION);
        token2Amount = getToken2Balance(); 

        uint256 tokenPrice = market.tokenPrice();  
        uint256 d2 = uint256(token2.decimals());
        uint256 maxToken1Amount = token2Amount.mul(tokenPrice).div(10**(d2));
        uint256 maxToken2Amount = token1Amount
                                    .mul(10**(d2))
                                    .div(tokenPrice);

       if (token2Amount > maxToken2Amount) {
            token2Amount =  maxToken2Amount;
        } 
        if (token1Amount > maxToken1Amount) {
            token1Amount =  maxToken1Amount;
        }

    }

    function withdrawLPTokens() external returns (uint256 liquidity) {
        require(hasAdminRole(msg.sender) || hasOperatorRole(msg.sender), "PostAuction: Sender must be operator");
        require(launcherInfo.launched, "PostAuction: Must first launch liquidity");
        require(block.timestamp >= uint256(launcherInfo.unlock), "PostAuction: Liquidity is locked");
        liquidity = IERC20(tokenPair).balanceOf(address(this));
        require(liquidity > 0, "PostAuction: Liquidity must be greater than 0");
        _safeTransfer(tokenPair, wallet, liquidity);
    }

    function withdrawDeposits() external {
        require(hasAdminRole(msg.sender) || hasOperatorRole(msg.sender), "PostAuction: Sender must be operator");
        require(launcherInfo.launched, "PostAuction: Must first launch liquidity");

        uint256 token1Amount = getToken1Balance();
        if (token1Amount > 0 ) {
            _safeTransfer(address(token1), wallet, token1Amount);
        }
        uint256 token2Amount = getToken2Balance();
        if (token2Amount > 0 ) {
            _safeTransfer(address(token2), wallet, token2Amount);
        }
    }

    function setWallet(address payable _wallet) external {
        require(hasAdminRole(msg.sender));
        require(_wallet != address(0), "Wallet is the zero address");

        wallet = _wallet;

        emit WalletUpdated(_wallet);
    }

    function cancelLauncher() external {
        require(hasAdminRole(msg.sender));
        require(!launcherInfo.launched);

        launcherInfo.launched = true;
        emit LauncherCancelled(msg.sender);

    }

    function createPool() internal {
        factory.createPair(address(token1), address(token2));
    }

    function getToken1Balance() public view returns (uint256) {
         return token1.balanceOf(address(this));
    }

    function getToken2Balance() public view returns (uint256) {
         return token2.balanceOf(address(this));
    }

    function getLPTokenAddress() public view returns (address) {
        return tokenPair;
    }
    
    function getLPBalance() public view returns (uint256) {
         return IERC20(tokenPair).balanceOf(address(this));
    }


    function init(bytes calldata _data) external payable {

    }

    function initLauncher(
        bytes calldata _data
    ) public {
        (
            address _market,
            address _factory,
            address _admin,
            address _wallet,
            uint256 _liquidityPercent,
            uint256 _locktime
        ) = abi.decode(_data, (
            address,
            address,
            address,
            address,
            uint256,
            uint256
        ));
        initAuctionLauncher( _market, _factory,_admin,_wallet,_liquidityPercent,_locktime);
    }

    function getLauncherInitData(
            address _market,
            address _factory,
            address _admin,
            address _wallet,
            uint256 _liquidityPercent,
            uint256 _locktime
    )
        external 
        pure
        returns (bytes memory _data)
    {
            return abi.encode(_market,
                                _factory,
                                _admin,
                                _wallet,
                                _liquidityPercent,
                                _locktime
            );
    }

}
