pragma solidity 0.6.12;

import "../OpenZeppelin/access/AccessControl.sol";
import "./ERC20Burnable.sol";
import "./ERC20Pausable.sol";
import "../interfaces/IAntToken.sol";


contract MintableToken is AccessControl, ERC20Burnable, ERC20Pausable, IAntToken {
    
    uint256 public constant override tokenTemplate = 2;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function initToken(string memory _name, string memory _symbol, address _owner, uint256 _initialSupply) public {
        _initERC20(_name, _symbol);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(MINTER_ROLE, _owner);
        _setupRole(PAUSER_ROLE, _owner);
        _mint(msg.sender, _initialSupply);
    }

    function init(bytes calldata _data) external override payable {}

   function initToken(
        bytes calldata _data
    ) public override {
        (string memory _name,
        string memory _symbol,
        address _owner,
        uint256 _initialSupply) = abi.decode(_data, (string, string, address, uint256));

        initToken(_name,_symbol,_owner,_initialSupply);
    }

   function getInitData(
        string calldata _name,
        string calldata _symbol,
        address _owner,
        uint256 _initialSupply
    )
        external
        pure
        returns (bytes memory _data)
    {
        return abi.encode(_name, _symbol, _owner, _initialSupply);
    }



    function mint(address to, uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "MintableToken: must have minter role to mint");
        _mint(to, amount);
    }

    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MintableToken: must have pauser role to pause");
        _pause();
    }

    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MintableToken: must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Pausable) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
