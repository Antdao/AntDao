pragma solidity 0.6.12;

import "../Access/ANTAccessControls.sol";
import "../interfaces/IGnosisProxyFactory.sol";
import "../interfaces/ISafeGnosis.sol";
import "../interfaces/IERC20.sol";


contract GnosisSafeFactory {

    ISafeGnosis public safeGnosis;

    IGnosisProxyFactory public proxyFactory;
    ANTAccessControls public accessControls;
    bool private initialised;

    mapping(address => ISafeGnosis) userToProxy;

    event GnosisSafeCreated(address indexed user, address indexed proxy, address safeGnosis, address proxyFactory);

    event AntInitGnosisVault(address sender);

    event SafeGnosisUpdated(address indexed sender, address oldSafeGnosis, address newSafeGnosis);

    event ProxyFactoryUpdated(address indexed sender, address oldProxyFactory, address newProxyFactory);

    function initGnosisVault(address _accessControls, address _safeGnosis, address _proxyFactory) public {
        require(!initialised);
        safeGnosis = ISafeGnosis(_safeGnosis);
        proxyFactory = IGnosisProxyFactory(_proxyFactory);
        accessControls = ANTAccessControls(_accessControls);
        initialised = true;
        emit AntInitGnosisVault(msg.sender);
    }

    function setSafeGnosis(address _safeGnosis) external {
        require(accessControls.hasOperatorRole(msg.sender), "GnosisVault.setSafeGnosis: Sender must be operator");
        address oldSafeGnosis = address(safeGnosis);
        safeGnosis = ISafeGnosis(_safeGnosis);
        emit SafeGnosisUpdated(msg.sender, oldSafeGnosis, address(safeGnosis));
    }

    function setProxyFactory(address _proxyFactory) external {
        require(accessControls.hasOperatorRole(msg.sender), "GnosisVault.setProxyFactory: Sender must be operator");
        address oldProxyFactory = address(proxyFactory);
        proxyFactory = IGnosisProxyFactory(_proxyFactory);
        emit ProxyFactoryUpdated(msg.sender, oldProxyFactory, address(proxyFactory));
    }

    function createSafe(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    )
        public returns (ISafeGnosis proxy)
    {
        bytes memory safeGnosisData = abi.encode("setup(address[],uint256,address,bytes,address,address,uint256,address)",
        _owners,_threshold,to,data,fallbackHandler,paymentToken,payment,paymentReceiver);
        proxy = proxyFactory.createProxy(
            safeGnosis,
            safeGnosisData
        );
        userToProxy[msg.sender] = proxy;
        emit GnosisSafeCreated(msg.sender, address(proxy), address(safeGnosis), address(proxyFactory));
        return proxy;
    }
    
}
