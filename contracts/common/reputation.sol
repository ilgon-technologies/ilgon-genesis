/*
	Reputation contract
	reputation.sol
	v0.2.1
	Author: Andor 'iFA' Rajci - https://www.fusionsolutions.io
*/
pragma solidity 0.4.26;
/* Imports */
import "./owned.sol";

/* Libraries */
library SafeMath {
	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		assert(b <= a);
		return a - b;
	}
	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		assert(c >= a);
		return c;
	}
}

/* Contracts */
/// @title Reputation contract
contract Reputation is Owned {
	/* Libraries */
	using SafeMath for uint256;
	
	/* Structures */
	struct member_s {
		uint256 value;
		bytes   meta;
	}
	struct group_s {
		bool                         valid;
		string                       name;
		address                      owner;
		mapping(address => member_s) members;
		uint256                      totalMembers;
		bytes                        meta;
	}
	/* Variables */
	bytes                       private nonOwnerPrefix;
	mapping(bytes32 => group_s) private groups;
	
	/* Connstructor */
	/// @dev Constructor for a new reputation contract
	/// @param _owner Owner address.
	/// @param _nonOwnerPrefix Prefix what the group must have when a non-owner creates.
	constructor(address _owner, string _nonOwnerPrefix) Owned(_owner) public {
		bytes memory bNonOwnerPrefix = bytes(_nonOwnerPrefix);
		require( bNonOwnerPrefix.length > 0 );
		nonOwnerPrefix.length = bNonOwnerPrefix.length;
		for ( uint256 i=0 ; i<bNonOwnerPrefix.length ; i++ ) {
			nonOwnerPrefix[i] = bNonOwnerPrefix[i];
		}
	}
	
	/* Modifiers */
	modifier ValidGroupOwner(bytes32 groupHash) {
		require( groups[groupHash].valid == true && groups[groupHash].owner == msg.sender );
		_;
	}
	
	/* Fallback */
	
	/* Externals */
	/// @dev Set new nonOwner group prefix by owner.
	/// @param _nonOwnerPrefix Prefix what the group must have when a non-owner creates.
	/// @return Returns boolean about call success.
	function setNonOwnerPrefix(string _nonOwnerPrefix) external returns (bool) {
		require( msg.sender == owner );
		bytes memory bNonOwnerPrefix = bytes(_nonOwnerPrefix);
		require( bNonOwnerPrefix.length > 0 );
		nonOwnerPrefix.length = bNonOwnerPrefix.length;
		for ( uint256 i=0 ; i<bNonOwnerPrefix.length ; i++ ) {
			nonOwnerPrefix[i] = bNonOwnerPrefix[i];
		}
	}
	/// @dev Creates new group.
	/// @param name Group name which can not be duplicated and must begin with `nonOwnerPrefix` when nonOwner creates.
	/// @param meta Group meta data which are optional.
	/// @return Returns boolean about call success.
	function createGroup(string name, bytes meta) external returns (bool) {
		if ( msg.sender != owner ) {
			require( checkPrefix(name) );
		}
		bytes32 groupHash = keccak256(name);
		require( ! groups[groupHash].valid );
		groups[groupHash].valid = true;
		groups[groupHash].name = name;
		groups[groupHash].owner = msg.sender;
		groups[groupHash].meta = meta;
		emit GroupCreated(name, groupHash, msg.sender, meta);
		return true;
	}
	/// @dev Changes exiting group owner. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param owner New owner address.
	/// @return Returns boolean about call success.
	function changeGroupOwner(bytes32 groupHash, address owner) external ValidGroupOwner(groupHash) returns (bool) {
		groups[groupHash].owner = owner;
		emit GroupNewOwner(groupHash, owner);
		return true;
	}
	/// @dev Changes exiting group metadata. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param meta New metadata.
	/// @return Returns boolean about call success.
	function changeGroupMeta(bytes32 groupHash, bytes meta) external ValidGroupOwner(groupHash) returns (bool) {
		groups[groupHash].meta = meta;
		emit GroupNewMeta(groupHash, meta);
		return true;
	}
	/// @dev Set group member metadata. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @param meta New metadata.
	/// @return Returns boolean about call success.
	function setMemberMeta(bytes32 groupHash, address member, bytes meta) external ValidGroupOwner(groupHash) returns (bool) {
		groups[groupHash].members[member].meta = meta;
		emit MemberMetaChanged(groupHash, member, meta);
		return true;
	}
	/// @dev Set group member rating value. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @param value New rating value.
	/// @return Returns boolean about call success.
	function setMemberRating(bytes32 groupHash, address member, uint256 value) external ValidGroupOwner(groupHash) returns (bool) {
	    require( groups[groupHash].members[member].value != value );
		_setMemberRating(
			groupHash,
			member,
			value
		);
		return true;
	}
	/// @dev Increases group member rating value by amount. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @param amount Increase amount.
	/// @return Returns boolean about call success.
	function increaseMemberRating(bytes32 groupHash, address member, uint256 amount) external ValidGroupOwner(groupHash) returns (bool) {
		_setMemberRating(
			groupHash,
			member,
			groups[groupHash].members[member].value.add( amount )
		);
		return true;
	}
	/// @dev Decreases group member rating value by amount. Callable by group owner.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @param amount Decrease amount.
	/// @return Returns boolean about call success.
	function decreaseMemberRating(bytes32 groupHash, address member, uint256 amount) external ValidGroupOwner(groupHash) returns (bool) {
		_setMemberRating(
			groupHash,
			member,
			groups[groupHash].members[member].value.sub( amount )
		);
		return true;
	}
	
	/* Constants */
	/// @dev Constant which returns the group name prefix which must have when a nonOwner creates a group.
	function getNonOwnerGroupPrefix() public view returns (string) {
		return string(nonOwnerPrefix);
	}
	/// @dev Helper to get group identifier.
	/// @param groupName Group name.
	/// @return Returns group identifier.
	function groupNameToGroupHash(string groupName) public pure returns (bytes32) {
		return keccak256(groupName);
	}
	/// @dev Get group details
	/// @param groupHash Group identifier.
	/// @return Returns group details like validation, name, owner, total members and metadata.
	function getGroupDetails(bytes32 groupHash) public view returns (bool valid, string name, address owner, uint256 totalMembers, bytes meta) {
		if ( groups[groupHash].valid ) {
			valid = true;
			name = groups[groupHash].name;
			owner = groups[groupHash].owner;
			totalMembers = groups[groupHash].totalMembers;
			meta = groups[groupHash].meta;
		}
	}
	/// @dev Get group member details.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @return Returns member details like rating value and metadata.
	function getGroupMember(bytes32 groupHash, address member) public view returns (uint256 value, bytes meta) {
		return (
		    groups[groupHash].members[member].value,
		    groups[groupHash].members[member].meta
        );
	}
	
	/* Internals */
	/// @dev Internal function which checks group name that has nonOwner prefix.
	/// @param groupName Group name.
	/// @return Returns check result.
	function checkPrefix(string groupName) internal view returns (bool) {
		bytes memory bGroupName = bytes(groupName);
		if ( bGroupName.length <= nonOwnerPrefix.length ) {
			return false;
		}
		for ( uint256 i=0 ; i<nonOwnerPrefix.length ; i++ ) {
			if ( nonOwnerPrefix[i] != bGroupName[i] ) {
				return false;
			}
		}
		return true;
	}
	/// @dev Internal function which sets group member rating. Automatic decreases or increases group totalMembers depending on newValue.
	/// @param groupHash Group identifier.
	/// @param member Member address.
	/// @param newValue New rating value.
	function _setMemberRating(bytes32 groupHash, address member, uint256 newValue) internal {
		if ( newValue != 0 && groups[groupHash].members[member].value == 0 ) {
			groups[groupHash].totalMembers++;
		}
		else if ( newValue == 0 && groups[groupHash].members[member].value > 0 ) {
			groups[groupHash].totalMembers--;
		}
		groups[groupHash].members[member].value = newValue;
		emit MemberRatingChanged(groupHash, member, newValue);
	}
	
	/* Privates */
	
	/* Events */
	event GroupCreated(string indexed groupName, bytes32 indexed groupHash, address indexed owner, bytes meta);
	event GroupNewOwner(bytes32 indexed groupHash, address indexed owner);
	event GroupNewMeta(bytes32 indexed groupHash, bytes meta);
	event MemberMetaChanged(bytes32 indexed groupHash, address indexed member, bytes meta);
	event MemberRatingChanged(bytes32 indexed groupHash, address indexed member, uint256 indexed value);
}
