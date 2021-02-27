/*
	Contract owner
	owned.sol
	v1.0.2
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
*/
pragma solidity 0.4.26;
/* Imports */

/* Contracts */
/// @title Owned contract
/// @dev Used for other contracts as subclass. Implements owner functions for it.
contract Owned {
	/* Structures */
	
	/* Variables */
	address public owner;
	
	/* Connstructor */
	/// @dev Constructor for a new block reward proxy.
	/// @param _owner Owner address. If none given the deployer will be the owner.
	constructor(address _owner) public {
		if ( _owner == 0x00 ) {
			_owner = msg.sender;
		}
		owner = _owner;
	}
	
	/* Modifiers */
	modifier forOwner { require( owner == msg.sender ); _; }
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can replace himself.
	/// @param _owner The new owner address.
	function replaceOwner(address _owner) forOwner external returns(bool)  {
		owner = _owner;
		return true;
	}
	
	/* Constants */
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
}
