/*
	Transaction premissions
	txPremission.sol
	v1.1.2
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
	Docs: https://openethereum.github.io/wiki/Permissioning.html
*/
pragma solidity 0.4.26;
/* Imports */
import "./owned.sol";

/* Contracts */
/// @title Transaction premission proxy contract
/// @dev This contract would forward AURA protocol calls for the tx premission library.
contract TxPremissionProxy is Owned {
	/* Structures */
	
	/* Variables */
	TxPremissionLib public libContract;
	
	/* Connstructor */
	/// @dev Constructor for a new tx premission proxy.
	/// @param _owner Owner address.
	/// @param _libAddress Block reward Library address.
	constructor(address _owner, address _libAddress) Owned(_owner) public {
		libContract = TxPremissionLib(_libAddress);
	}
	
	/* Modifiers */
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can change tx premission library address.
	/// @param _newLibAddress The new library contract address.
	function changeLibAddress(address _newLibAddress) forOwner {
		libContract = TxPremissionLib(_newLibAddress);
	}
	
	/* Constants */
	/// @dev Will call tx premission lib with the same input.
	/// @param _from Transaction sender.
	/// @param _to Transaction receiver.
	/// @param _value Transaction amount.
	/// @param _gasPrice Transaction gas price.
	/// @param _data Transaction input data.
	/// @return typesMask for a premission bit. Cache boolean that the node should cache the typeMask forever.
	function allowedTxTypes(address _from, address _to, uint256 _value, uint256 _gasPrice, bytes memory _data ) public constant returns(uint32 typesMask, bool cache) {
		return libContract.allowedTxTypes(_from, _to, _value, _gasPrice, _data);
	}
	/// @dev Required for AURA protocol.
	function contractName() public constant returns (string) {
		return "TX_PERMISSION_CONTRACT";
	}
	/// @dev Required for AURA protocol.
	function contractNameHash() public constant returns (bytes32) {
		return keccak256(contractName());
	}
	/// @dev Required for AURA protocol. Every version has different parameters for allowedTxTypes, we use verison nr 3.
	function contractVersion() public constant returns (uint256) {
		return 3;
	}
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
}
/// @title An abstract contract for validator set proxy
contract ValidatorSetAbstract {
	function getValidators() public constant returns (address[]) {}
}
/// @title TX premission library contract
/// @dev This contract determines which addresses will receive rewards during new block for a AURA blockchain
contract TxPremissionLib is Owned {
	/* Structures */
	
	/* Variables */
	TxPremissionProxy    public proxyContract;
	ValidatorSetAbstract public validatorSet;
	uint256              public minGasPrice = 100000000;
	uint32               private constant NONE = 0;         // Can not do anything
	uint32               private constant ALL = 0xffffffff; // Can do everything
	uint32               private constant BASIC = 0x01;
	uint32               private constant CALL = 0x02;      // Can do calls
	uint32               private constant CREATE = 0x04;    // Can create contracts
	uint32               private constant PRIVATE = 0x08;

	/* Connstructor */
	/// @dev Constructor for a new tx premission library.
	/// @param _owner Owner address.
	/// @param _proxyAddress TX premission proxy address.
	/// @param _validatorSet Validator set proxy address.
	constructor(address _owner, address _proxyAddress, address _validatorSet) Owned(_owner) public {
		proxyContract = TxPremissionProxy(_proxyAddress);
		validatorSet = ValidatorSetAbstract(_validatorSet);
	}
	
	/* Modifiers */
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can change the minimum gas price for mining transactions.
	/// @param _minGasPrice Gas price in wei.
	function changeMinGasPrice(uint256 _minGasPrice) external forOwner {
		minGasPrice = _minGasPrice;
	}
	
	/* Constants */
	/// @dev Returns that the transaction which premission has. The transaction must have at least the minGasPrice amount for gas price, otherwise will return NONE. Validators and owner can send transaction with zero gas price.
	/// @param _from Transaction sender.
	/// @param _to Transaction receiver.
	/// @param _value Transaction amount.
	/// @param _gasPrice Transaction gas price.
	/// @param _data Transaction input data.
	/// @return typesMask for a premission bit. Cache boolean that the node should cache the typeMask forever.
	function allowedTxTypes(address _from, address _to, uint256 _value, uint256 _gasPrice, bytes memory _data ) public constant returns(uint32 typesMask, bool cache) {
		if ( _gasPrice < minGasPrice && _from != owner ) {
			address[] memory validators = validatorSet.getValidators();
			for ( uint256 i=0 ; i < validators.length ; i++ ) {
				if ( validators[i] == _from ) {
					return (ALL, false);
				}
			}
			return (NONE, false);
		}
		return (ALL, false);
	}
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
}
