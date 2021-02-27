/*
	Weighted multi owner contract
	weightedMultiOwner.sol
	v1.0.2
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
	Original author: Stefan George - <stefan.george@consensys.net>
*/
pragma solidity 0.4.26;
/* Imports */

/* Contracts */
/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract WeightedMultiOwner {
	/* Structures */
	struct Transaction {
		address                   destination;
		uint256                   value;
		bytes                     data;
		bool                      executed;
		mapping (address => bool) votedOwners;
		uint256                   voteWeight;
	}
	
	/* Variables */
	address[]                        public owners;
	uint256                          public required;
	uint256                          public transactionCount;
	uint256                          public totalWeight;
	mapping (uint256 => Transaction) public transactions;
	mapping (address => uint8)       public ownerWeights;
	
	/* Connstructor */
	/// @dev Contract constructor sets initial owners and required number of confirmations.
	/// @param _owners List of initial owners.
	/// @param _ownerWeights List of initial owner weights. Every owner must have at least 1 weight.
	/// @param _required Number of required confirmations.
	constructor(address[] _owners, uint8[] _ownerWeights, uint256 _required) public payable {
		require( _owners.length == _ownerWeights.length && _owners.length > 1 );
		for ( uint256 i=0 ; i < _owners.length ; i++ ) {
			require(
				_owners[i] != 0x00 &&
				_ownerWeights[i] > 0 &&
				ownerWeights[ _owners[i] ] == 0
			);
			totalWeight += _ownerWeights[i];
			ownerWeights[ _owners[i] ] = _ownerWeights[i];
		}
		require( totalWeight >= required );
		owners = _owners;
		required = _required;
	    if ( msg.value > 0 ) {
	        emit Deposit(msg.sender, msg.value);
	    }
	}
	
	/* Modifiers */
	modifier onlyWallet() {
		require( msg.sender == address(this) );
		_;
	}
	
	/* Fallback */
	/// @dev Fallback function allows to deposit ether.
	function() public payable {
		if ( msg.value > 0 ) {
			emit Deposit(msg.sender, msg.value);
		}
	}
	
	/* Externals */
	/// @dev Allows to add a new owner. Transaction has to be sent by wallet.
	/// @param owner Address of new owner.
	/// @param weight Weight amount of new owner.
	function addOwner(address owner, uint8 weight) public onlyWallet {
		require(
			owner != 0x00 &&
			weight > 0 &&
			ownerWeights[owner] == 0
		);
		totalWeight += uint256(weight);
		ownerWeights[owner] = weight;
		owners.push(owner);
		emit OwnerAddition(owner, weight);
	}
	/// @dev Allows to remove an owner. Transaction has to be sent by wallet.
	/// @param owner Address of owner.
	function removeOwner(address owner) public onlyWallet {
		require(
			owner != 0x00 &&
			ownerWeights[owner] > 0 &&
			(totalWeight - ownerWeights[owner]) >= required
		);
		for ( uint256 i=0 ; i < owners.length - 1 ; i++ ) {
			if ( owners[i] == owner ) {
				owners[i] = owners[owners.length - 1];
				break;
			}
		}
		owners.length -= 1;
		totalWeight -= ownerWeights[owner];
		delete ownerWeights[owner];
		emit OwnerRemoval(owner);
	}
	/// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
	/// @param owner Address of owner to be replaced.
	/// @param newOwner Address of new owner.
	function replaceOwner(address owner, address newOwner) public onlyWallet {
		require(
			owner != 0x00 &&
			newOwner != 0x00 &&
			ownerWeights[owner] != 0 &&
			ownerWeights[newOwner] == 0
		);
		for ( uint256 i=0 ; i < owners.length ; i++ ) {
			if ( owners[i] == owner ) {
				owners[i] = newOwner;
				break;
			}
		}
		ownerWeights[newOwner] = ownerWeights[owner];
		delete ownerWeights[owner];
		emit OwnerRemoval(owner);
		emit OwnerAddition(newOwner, ownerWeights[newOwner]);
	}
	/// @dev Allows to change owner weight amount. Transaction has to be sent by wallet.
	/// @param owner Owner address.
	/// @param newWeight New weight.
	function changeOwnerWeight(address owner, uint8 newWeight) public onlyWallet {
		require(
			owner != 0x00 &&
			ownerWeights[owner] != 0 &&
			(totalWeight + newWeight - ownerWeights[owner]) >= required
		);
		totalWeight += newWeight;
		totalWeight -= ownerWeights[owner];
		ownerWeights[owner] = newWeight;
		emit OwnerWeightChanged(owner, newWeight);
	}
	/// @dev Allows to change weight amount of required confirmations. Transaction has to be sent by wallet.
	/// @param _required Weight amount.
	function changeRequirement(uint256 _required) public onlyWallet {
		require( totalWeight >= _required );
		required = _required;
		emit RequirementChange(_required);
	}
	/// @dev Allows an owner to submit and confirm a transaction.
	/// @param destination Transaction target address.
	/// @param value Transaction ether value.
	/// @param data Transaction data payload.
	/// @return Returns transaction ID.
	function submitTransaction(address destination, uint256 value, bytes data) public returns (uint256 transactionID) {
		require( ownerWeights[msg.sender] > 0 && destination != 0x00 );
		transactionID = transactionCount;
		transactions[transactionID] = Transaction({
			destination: destination,
			value: value,
			data: data,
			executed: false,
			voteWeight: 0
		});
		transactionCount += 1;
		emit Submission(transactionID);
		confirmTransaction(transactionID);
	}
	/// @dev Allows an owner to confirm a transaction.
	/// @param transactionID Transaction ID.
	function confirmTransaction(uint256 transactionID) public {
		require(
			! transactions[transactionID].executed &&
			ownerWeights[msg.sender] != 0 &&
			transactions[transactionID].destination != 0x00 &&
			! transactions[transactionID].votedOwners[msg.sender]
		);
		transactions[transactionID].votedOwners[msg.sender] = true;
		transactions[transactionID].voteWeight += ownerWeights[msg.sender];
		emit Confirmation(msg.sender, transactionID);
		if ( isConfirmed(transactionID) ) {
			executeTransaction(transactionID);
		}
	}
	/// @dev Allows an owner to revoke a confirmation for a transaction.
	/// @param transactionID Transaction ID.
	function revokeConfirmation(uint256 transactionID) public {
		require(
			! transactions[transactionID].executed &&
			ownerWeights[msg.sender] != 0 &&
			transactions[transactionID].destination != 0x00 &&
			transactions[transactionID].votedOwners[msg.sender]
		);
		delete transactions[transactionID].votedOwners[msg.sender];
		transactions[transactionID].voteWeight -= ownerWeights[msg.sender];
		emit Revocation(msg.sender, transactionID);
	}
	/// @dev Allows anyone to execute a confirmed transaction.
	/// @param transactionID Transaction ID.
	function executeTransaction(uint256 transactionID) public {
		require(
			! transactions[transactionID].executed &&
			transactions[transactionID].destination != 0x00 &&
			isConfirmed(transactionID)
		);
		Transaction storage txn = transactions[transactionID];
		txn.executed = true;
		if ( external_call(txn.destination, txn.value, txn.data.length, txn.data) )
		{
			emit Execution(transactionID);
		} else {
			emit ExecutionFailure(transactionID);
			txn.executed = false;
		}
	}
	/// @dev Returns the confirmation status of a transaction.
	/// @param transactionID Transaction ID.
	/// @return Confirmation status.
	function isConfirmed(uint256 transactionID) public constant returns (bool) {
		return transactions[transactionID].voteWeight >= required;
	}
	
	/* Constants */
	/// @dev Returns weight amount for confirmation a transaction.
	/// @param transactionID Transaction ID.
	/// @return Weight amount.
	function getConfirmationWeight(uint256 transactionID) public constant returns (uint256) {
		return transactions[transactionID].voteWeight;
	}
	/// @dev Returns total number of transactions after filters are applied.
	/// @param pending Include pending transactions.
	/// @param executed Include executed transactions.
	/// @return Total number of transactions after filters are applied.
	function getTransactionCount(bool pending, bool executed) public constant returns (uint256 count) {
		for ( uint256 i=0 ; i < transactionCount ; i++ )
			if ( pending && !transactions[i].executed || executed && transactions[i].executed ) {
				count += 1;
			}
	}
	/// @dev Returns list of owners.
	/// @return List of owner addresses.
	function getOwners() public constant returns (address[]) {
		return owners;
	}
	/// @dev Returns array with owner addresses, which confirmed transaction.
	/// @param transactionID Transaction ID.
	/// @return Returns array of owner addresses.
	function getConfirmations(uint256 transactionID) public constant returns (address[] _confirmations) {
		address[] memory confirmationsTemp = new address[](owners.length);
		uint256 count = 0;
		uint256 i;
		for ( i=0 ; i < owners.length ; i++ ) {
			if ( transactions[transactionID].votedOwners[owners[i]] ) {
				confirmationsTemp[count] = owners[i];
				count += 1;
			}
		}
		_confirmations = new address[](count);
		for ( i=0 ; i < count ; i++ ) {
			_confirmations[i] = confirmationsTemp[i];
		}
	}
	/// @dev Returns list of transaction IDs in defined range.
	/// @param from Index start position of transaction array.
	/// @param to Index end position of transaction array.
	/// @param pending Include pending transactions.
	/// @param executed Include executed transactions.
	/// @return Returns array of transaction IDs.
	function getTransactionIds(uint256 from, uint256 to, bool pending, bool executed) public constant returns (uint256[] _transactionIds) {
		uint256[] memory transactionIdsTemp = new uint256[](transactionCount);
		uint256 count = 0;
		uint256 i;
		for ( i=0 ; i < transactionCount ; i++ ) {
			if ( pending && !transactions[i].executed || executed && transactions[i].executed ) {
				transactionIdsTemp[count] = i;
				count += 1;
			}
		}
		_transactionIds = new uint256[](to - from);
		for ( i=from ; i < to ; i++ ) {
			_transactionIds[i - from] = transactionIdsTemp[i];
		}
	}
	
	// Helper functions to calculate (call)data for submitTransaction
	function helper_addOwner(address owner, uint8 weight) pure public returns (bytes memory) {
		return abi.encodeWithSignature("addOwner(address, uint8)", owner, weight);
	}
	function helper_removeOwner(address owner) pure public returns (bytes memory) {
		return abi.encodeWithSignature("removeOwner(address)", owner);
	}
	function helper_replaceOwner(address owner, address newOwner) pure public returns (bytes memory) {
		return abi.encodeWithSignature("replaceOwner(address, address)", owner, newOwner);
	}
	function helper_changeOwnerWeight(address owner, uint8 newWeight) pure public returns (bytes memory) {
		return abi.encodeWithSignature("changeOwnerWeight(address, uint8)", owner, newWeight);
	}
	function helper_changeRequirement(uint256 _required) pure public returns (bytes memory) {
		return abi.encodeWithSignature("changeRequirement(uint256)", _required);
	}
	/* Internals */
	
	/* Privates */
	function external_call(address destination, uint256 value, uint256 dataLength, bytes data) private returns (bool) {
		bool result;
		assembly {
			let x := mload(0x40)
			let d := add(data, 32)
			result := call(gas, destination, value, d, dataLength, x, 0)
		}
		return result;
	}
	
	/* Events */
	event Confirmation(address indexed sender, uint256 indexed transactionID);
	event Revocation(address indexed sender, uint256 indexed transactionID);
	event Submission(uint256 indexed transactionID);
	event Execution(uint256 indexed transactionID);
	event ExecutionFailure(uint256 indexed transactionID);
	event Deposit(address indexed sender, uint256 indexed value);
	event OwnerAddition(address indexed owner, uint256 indexed weight);
	event OwnerRemoval(address indexed owner);
	event OwnerWeightChanged(address indexed owner, uint256 indexed weight);
	event RequirementChange(uint256 required);
}