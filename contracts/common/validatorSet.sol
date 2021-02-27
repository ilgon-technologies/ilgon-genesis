/*
	Validator dispatcher
	validatorSet.sol
	v2.0.0
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
	Docs: https://openethereum.github.io/wiki/Validator-Set.html
*/
pragma solidity 0.4.26;
/* Imports */
import "./owned.sol";

/* Contracts */
/// @title Validator set proxy contract
/// @dev This contract would forward AURA protocol calls for the validator set library.
contract ValidatorSetProxy is Owned {
	/* Structures */
	
	/* Variables */
	address systemAddress = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
	ValidatorSetLib public libContract;
	
	/* Connstructor */
	/// @dev Constructor for a new validator set proxy.
	/// @param _owner Owner address.
	/// @param _libAddress Validator set library address.
	constructor(address _owner, address _libAddress) Owned(_owner) public {
		libContract = ValidatorSetLib(_libAddress);
	}
	
	/* Modifiers */
	modifier forSystem { require(msg.sender == systemAddress); _; }
	modifier forLibrary { require(msg.sender == address(libContract)); _; }
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can change validator set library address.
	/// @param _newLibAddress The new library contract address.
	function changeLibAddress(address _newLibAddress) forOwner {
		libContract = ValidatorSetLib(_newLibAddress);
	}
	/// @dev System address call this function when the new validator set has been activated.
	function finalizeChange() public forSystem {
		libContract.finalizeChange();
	}
	/// @dev Validator set library can call this when new validator set must be applied.
	/// @param _parentHash The parent block hash where the validators must be activated.
	/// @param _newSet A list of the validators.
	function initiateChange(bytes32 _parentHash, address[] _newSet) forLibrary {
		emit InitiateChange(_parentHash, _newSet);
	}
	/// @dev Validator calls this when some other validator did not sealing blocks.
	/// @param _validator The bad validator address.
	/// @param _blockNumber The block what the validator did not sealed.
	function reportBenign(address _validator, uint256 _blockNumber) {
		return libContract.reportBenign(msg.sender, _validator, _blockNumber);
	}
	/// @dev Validator calls this when some other validator sealing bad blocks.
	/// @param _validator The bad validator address.
	/// @param _blockNumber The block what the validator has malicious block sealed.
	/// @param _proof Proof about it.
	function reportMalicious(address _validator, uint256 _blockNumber, bytes _proof) {
		return libContract.reportMalicious(msg.sender, _validator, _blockNumber, _proof);
	}
	
	/* Constants */
	/// @dev Returns array with the current validator addresses.
	/// @return Array of validator addresses
	function getValidators() constant returns (address[]) {
		return libContract.getActiveValidators();
	}
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
	event InitiateChange(bytes32 indexed parentHash, address[] newSet);
}
/// @title Validator set library contract
/// @dev This contract handle the validators for an AURA blockchain
contract ValidatorSetLib is Owned {
	/* Structures */
	struct s_validatorStatus {
		bool isValid;
		uint index;
	}
	
	/* Variables */
	ValidatorSetProxy public proxyContract;
	bool              public isFinalized;
	address[]         public activeValidators;
	address[]         public pendingValidators;
	mapping(address => s_validatorStatus) public validatorStatus;
	
	/* Connstructor */
	/// @dev Constructor for a new validator set library. The initial validators will be broadcasted on deploy.
	/// @param _owner Owner address.
	/// @param _proxyAddress Validator set proxy address.
	/// @param _baseValidators List from the initial validator addresses
	constructor(address _owner, address _proxyAddress, address[] _baseValidators) Owned(_owner) public {
		for ( uint256 i=0 ; i < _baseValidators.length ; i++ ) {
			validatorStatus[ _baseValidators[i] ].isValid = true;
			validatorStatus[ _baseValidators[i] ].index = pendingValidators.length;
			pendingValidators.push(_baseValidators[i]);
		}
		proxyContract = ValidatorSetProxy(_proxyAddress);
		if ( block.number == 0 ) {
			proxyContract.initiateChange(0x0000000000000000000000000000000000000000000000000000000000000000, pendingValidators);
			isFinalized = true;
		}
		activeValidators = pendingValidators;
	}
	
	/* Modifiers */
	modifier forProxy { require(msg.sender == address(proxyContract)); _; }
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can add new validator.
	/// @param _newValidator New validator address.
	function addValidator(address _newValidator) public forOwner {
		require( ! validatorStatus[_newValidator].isValid );
		// Set new status for the new validator
		validatorStatus[ _newValidator ].isValid = true;
		validatorStatus[ _newValidator ].index = pendingValidators.length;
		// Pushing into pending validator list
		pendingValidators.push(_newValidator);
		// Emit an event
		commitChangeEvent();
	}
	/// @dev Owner can remove validator.
	/// @param _validator Validator address for removing.
	function removeValidator(address _validator) public forOwner {
		require( validatorStatus[_validator].isValid );
		uint256 index = validatorStatus[_validator].index;
		// Replace with the last array element
		pendingValidators[index] = pendingValidators[pendingValidators.length - 1];
		// Set new index for the last array element in the status
		validatorStatus[ pendingValidators[index] ].index = index;
		// Delete the last array element
		delete pendingValidators[pendingValidators.length - 1];
		// Decreasing array length
		pendingValidators.length--;
		// Delete the given validator status
		delete validatorStatus[_validator];
		// Emit an event
		commitChangeEvent();
	}
	/// @dev Validator set proxy call this function when the new validator set has been activated.
	function finalizeChange() public forProxy {
		require( ! isFinalized );
		activeValidators = pendingValidators;
		isFinalized = true;
	}
	/// @dev Handling bad validator which not sealing specific block. Only the validator set proxy or the owner can call this.
	/// @param _sender Reporter address.
	/// @param _validator The bad validator address
	/// @param _blockNumber The block what the validator did not sealed.
	function reportBenign(address _sender, address _validator, uint256 _blockNumber) {
		require( validatorStatus[_sender].isValid || _sender == owner );
	}
	/// @dev Handling bad validator which not sealing specific block. Only the validator set proxy or the owner can call this.
	/// @param _sender Reporter address.
	/// @param _validator The bad validator address
	/// @param _blockNumber The block what the validator has malicious block sealed.
	/// @param _proof Proof about it.
	function reportMalicious(address _sender, address _validator, uint256 _blockNumber, bytes _proof) {
		require( validatorStatus[_sender].isValid || _sender == owner );
	}
	
	/* Constants */
	/// @dev Returns list of active validator addresses.
	/// @return List of addresses.
	function getActiveValidators() public constant returns (address[]) {
		return activeValidators;
	}
	/// @dev Returns list of pending validator addresses.
	/// @return List of addresses.
	function getPendingValidators() public constant returns (address[]) {
		return pendingValidators;
	}
	
	/* Internals */
	
	/* Privates */
	/// @dev Calling validator set proxy that should broadcast new validator set list
	function commitChangeEvent() private {
		isFinalized = false;
		proxyContract.initiateChange(blockhash(block.number - 1), pendingValidators);
	}
	
	/* Events */
}
