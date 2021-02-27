/*
	Block reward dispatcher
	blockReward.sol
	v1.2.0
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
	Docs: https://openethereum.github.io/wiki/Block-Reward-Contract.html
*/
pragma solidity 0.4.26;
/* Imports */
import "./owned.sol";

/* Contracts */
/// @title Block reward proxy contract
/// @dev This contract would forward AURA protocol calls for the block reward library.
contract BlockRewardProxy is Owned {
	/* Structures */
	
	/* Variables */
	address systemAddress = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
	BlockRewardLib public libContract;
	
	/* Connstructor */
	/// @dev Constructor for a new block reward proxy.
	/// @param _owner Owner address.
	/// @param _libAddress Block reward Library address.
	constructor(address _owner, address _libAddress) Owned(_owner) public {
		libContract = BlockRewardLib(_libAddress);
	}
	
	/* Modifiers */
	modifier forSystem { require(msg.sender == systemAddress); _; }
	
	/* Fallback */
	
	/* Externals */
	/// @dev Owner can change block reward library address.
	/// @param _newLibAddress The new library contract address.
	function changeLibAddress(address _newLibAddress) forOwner {
		libContract = BlockRewardLib(_newLibAddress);
	}
	/// @dev Will call block reward lib with the same input.
	/// @param _benefactors Input for base reward addresses like block/uncle/transaction fees.
	/// @param _kind Input for the reward type.
	/// @return Addresses and rewards in wei.
	function reward(address[] _benefactors, uint16[] _kind) public forSystem returns (address[], uint256[]) {
		return libContract.reward(_benefactors, _kind);
	}
	
	/* Constants */
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
}
/// @title Block reward library contract
/// @dev This contract determines which addresses will receive rewards during new block for a AURA blockchain
contract BlockRewardLib is Owned {
	/* Structures */
	
	/* Variables */
	BlockRewardProxy public proxyContract;
	uint256          public baseBlockReward;
	
	/* Connstructor */
	/// @dev Constructor for a new block reward library
	/// @param _owner Owner address.
	/// @param _proxyAddress Block reward proxy address.
	/// @param _baseBlockReward Base block reward amount.
	constructor(address _owner, address _proxyAddress, uint256 _baseBlockReward) Owned(_owner) public {
		proxyContract = BlockRewardProxy(_proxyAddress);
		baseBlockReward = _baseBlockReward;
	}
	
	/* Modifiers */
	modifier forProxy { require(msg.sender == address(proxyContract)); _; }
	
	/* Fallback */
	
	/* Externals */
	/// @dev Determines which address how much reward receive. Only the block reward proxy can call this.
	/// @param _benefactors Input for base reward addresses.
	/// @param _kind Input for the reward type like block/uncle/transaction fees etc.
	/// @return Addresses and rewards in wei.
	function reward(address[] _benefactors, uint16[] _kind) external forProxy returns (address[] memory receivers, uint256[] memory rewards) {
		if (_benefactors.length != _kind.length || _benefactors.length != 1 || _kind[0] != 0 ) {
			return;
		}
		receivers = new address[](_benefactors.length);
		rewards = new uint256[](receivers.length);
		for ( uint256 i=0 ; i<_benefactors.length ; i++ ) {
			if ( _kind[i] == 0 ) {
				receivers[i] = _benefactors[i];
				rewards[i] = baseBlockReward;
			}
		}
		return (receivers, rewards);
	}
	/// @dev Owner can change the base block reward.
	/// @param _baseBlockReward Base block reward amount.
	function changeBaseBlockReward(uint256 _baseBlockReward) external forOwner {
		baseBlockReward = _baseBlockReward;
	}
	
	/* Constants */
	
	/* Internals */
	
	/* Privates */
	
	/* Events */
}
