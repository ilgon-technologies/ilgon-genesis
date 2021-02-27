/*
	Ethereum Name Service registry
	ENS.sol
	v1.0.1
	Docs: https://docs.ens.domains
*/
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "./ENSResolvers.sol";

/**
 * The ENS registry contract.
 */
contract ENSRegistry is ENS {

	struct Record {
		address owner;
		address resolver;
		uint64 ttl;
	}

	mapping (bytes32 => Record) records;
	mapping (address => mapping(address => bool)) operators;

	// Permits modifications only by the owner of the specified node.
	modifier authorised(bytes32 node) {
		address owner = records[node].owner;
		require(owner == msg.sender || operators[owner][msg.sender]);
		_;
	}

	/**
	 * @dev Constructs a new ENS registrar.
	 */
	constructor() public {
		records[0x0].owner = msg.sender;
	}

	/**
	 * @dev Sets the record for a node.
	 * @param node The node to update.
	 * @param owner The address of the new owner.
	 * @param resolver The address of the resolver.
	 * @param ttl The TTL in seconds.
	 */
	function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external {
		setOwner(node, owner);
		_setResolverAndTTL(node, resolver, ttl);
	}

	/**
	 * @dev Sets the record for a subnode.
	 * @param node The parent node.
	 * @param label The hash of the label specifying the subnode.
	 * @param owner The address of the new owner.
	 * @param resolver The address of the resolver.
	 * @param ttl The TTL in seconds.
	 */
	function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external {
		bytes32 subnode = setSubnodeOwner(node, label, owner);
		_setResolverAndTTL(subnode, resolver, ttl);
	}

	/**
	 * @dev Transfers ownership of a node to a new address. May only be called by the current owner of the node.
	 * @param node The node to transfer ownership of.
	 * @param owner The address of the new owner.
	 */
	function setOwner(bytes32 node, address owner) public authorised(node) {
		_setOwner(node, owner);
		emit Transfer(node, owner);
	}

	/**
	 * @dev Transfers ownership of a subnode keccak256(node, label) to a new address. May only be called by the owner of the parent node.
	 * @param node The parent node.
	 * @param label The hash of the label specifying the subnode.
	 * @param owner The address of the new owner.
	 */
	function setSubnodeOwner(bytes32 node, bytes32 label, address owner) public authorised(node) returns(bytes32) {
		bytes32 subnode = keccak256(abi.encodePacked(node, label));
		_setOwner(subnode, owner);
		emit NewOwner(node, label, owner);
		return subnode;
	}

	/**
	 * @dev Sets the resolver address for the specified node.
	 * @param node The node to update.
	 * @param resolver The address of the resolver.
	 */
	function setResolver(bytes32 node, address resolver) public authorised(node) {
		emit NewResolver(node, resolver);
		records[node].resolver = resolver;
	}

	/**
	 * @dev Sets the TTL for the specified node.
	 * @param node The node to update.
	 * @param ttl The TTL in seconds.
	 */
	function setTTL(bytes32 node, uint64 ttl) public authorised(node) {
		emit NewTTL(node, ttl);
		records[node].ttl = ttl;
	}

	/**
	 * @dev Enable or disable approval for a third party ("operator") to manage
	 *  all of `msg.sender`'s ENS records. Emits the ApprovalForAll event.
	 * @param operator Address to add to the set of authorized operators.
	 * @param approved True if the operator is approved, false to revoke approval.
	 */
	function setApprovalForAll(address operator, bool approved) external {
		operators[msg.sender][operator] = approved;
		emit ApprovalForAll(msg.sender, operator, approved);
	}

	/**
	 * @dev Returns the address that owns the specified node.
	 * @param node The specified node.
	 * @return address of the owner.
	 */
	function owner(bytes32 node) public view returns (address) {
		address addr = records[node].owner;
		if (addr == address(this)) {
			return address(0x0);
		}

		return addr;
	}

	/**
	 * @dev Returns the address of the resolver for the specified node.
	 * @param node The specified node.
	 * @return address of the resolver.
	 */
	function resolver(bytes32 node) public view returns (address) {
		return records[node].resolver;
	}

	/**
	 * @dev Returns the TTL of a node, and any records associated with it.
	 * @param node The specified node.
	 * @return ttl of the node.
	 */
	function ttl(bytes32 node) public view returns (uint64) {
		return records[node].ttl;
	}

	/**
	 * @dev Returns whether a record has been imported to the registry.
	 * @param node The specified node.
	 * @return Bool if record exists
	 */
	function recordExists(bytes32 node) public view returns (bool) {
		return records[node].owner != address(0x0);
	}

	/**
	 * @dev Query if an address is an authorized operator for another address.
	 * @param owner The address that owns the records.
	 * @param operator The address that acts on behalf of the owner.
	 * @return True if `operator` is an approved operator for `owner`, false otherwise.
	 */
	function isApprovedForAll(address owner, address operator) external view returns (bool) {
		return operators[owner][operator];
	}

	function _setOwner(bytes32 node, address owner) internal {
		records[node].owner = owner;
	}

	function _setResolverAndTTL(bytes32 node, address resolver, uint64 ttl) internal {
		if(resolver != records[node].resolver) {
			records[node].resolver = resolver;
			emit NewResolver(node, resolver);
		}

		if(ttl != records[node].ttl) {
			records[node].ttl = ttl;
			emit NewTTL(node, ttl);
		}
	}
}

/**
 * A registrar that allocates subdomains to the first person to claim them.
 */
contract FIFSRegistrar {
	ENS ens;
	bytes32 rootNode;

	modifier only_owner(bytes32 label) {
		address currentOwner = ens.owner(keccak256(abi.encodePacked(rootNode, label)));
		require(currentOwner == address(0x0) || currentOwner == msg.sender);
		_;
	}

	/**
	 * Constructor.
	 * @param ensAddr The address of the ENS registry.
	 * @param node The node that this registrar administers.
	 */
	constructor(ENS ensAddr, bytes32 node) public {
		ens = ensAddr;
		rootNode = node;
	}

	/**
	 * Register a name, or change the owner of an existing registration.
	 * @param label The hash of the label to register.
	 * @param owner The address of the new owner.
	 */
	function register(bytes32 label, address owner) public only_owner(label) {
		ens.setSubnodeOwner(rootNode, label, owner);
	}
}

contract ReverseRegistrar {
	// namehash('addr.reverse')
	bytes32 public constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

	ENS public ens;
	NameResolver public defaultResolver;

	/**
	 * @dev Constructor
	 * @param ensAddr The address of the ENS registry.
	 * @param resolverAddr The address of the default reverse resolver.
	 */
	constructor(ENS ensAddr, NameResolver resolverAddr) public {
		ens = ensAddr;
		defaultResolver = resolverAddr;

		// Assign ownership of the reverse record to our deployer
		ReverseRegistrar oldRegistrar = ReverseRegistrar(ens.owner(ADDR_REVERSE_NODE));
		if (address(oldRegistrar) != address(0x0)) {
			oldRegistrar.claim(msg.sender);
		}
	}

	/**
	 * @dev Transfers ownership of the reverse ENS record associated with the
	 *	  calling account.
	 * @param owner The address to set as the owner of the reverse record in ENS.
	 * @return The ENS node hash of the reverse record.
	 */
	function claim(address owner) public returns (bytes32) {
		return claimWithResolver(owner, address(0x0));
	}

	/**
	 * @dev Transfers ownership of the reverse ENS record associated with the
	 *	  calling account.
	 * @param owner The address to set as the owner of the reverse record in ENS.
	 * @param resolver The address of the resolver to set; 0 to leave unchanged.
	 * @return The ENS node hash of the reverse record.
	 */
	function claimWithResolver(address owner, address resolver) public returns (bytes32) {
		bytes32 label = sha3HexAddress(msg.sender);
		bytes32 node = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, label));
		address currentOwner = ens.owner(node);

		// Update the resolver if required
		if (resolver != address(0x0) && resolver != ens.resolver(node)) {
			// Transfer the name to us first if it's not already
			if (currentOwner != address(this)) {
				ens.setSubnodeOwner(ADDR_REVERSE_NODE, label, address(this));
				currentOwner = address(this);
			}
			ens.setResolver(node, resolver);
		}

		// Update the owner if required
		if (currentOwner != owner) {
			ens.setSubnodeOwner(ADDR_REVERSE_NODE, label, owner);
		}

		return node;
	}

	/**
	 * @dev Sets the `name()` record for the reverse ENS record associated with
	 * the calling account. First updates the resolver to the default reverse
	 * resolver if necessary.
	 * @param name The name to set for this address.
	 * @return The ENS node hash of the reverse record.
	 */
	function setName(string memory name) public returns (bytes32) {
		bytes32 node = claimWithResolver(address(this), address(defaultResolver));
		defaultResolver.setName(node, name);
		return node;
	}

	/**
	 * @dev Returns the node hash for a given account's reverse records.
	 * @param addr The address to hash
	 * @return The ENS node hash.
	 */
	function node(address addr) public pure returns (bytes32) {
		return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr)));
	}

	/**
	 * @dev An optimised function to compute the sha3 of the lower-case
	 *	  hexadecimal representation of an Ethereum address.
	 * @param addr The address to hash
	 * @return The SHA3 hash of the lower-case hexadecimal encoding of the
	 *		 input address.
	 */
	function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
		addr;
		ret; // Stop warning us about unused variables
		assembly {
			let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000

			for { let i := 40 } gt(i, 0) { } {
				i := sub(i, 1)
				mstore8(i, byte(and(addr, 0xf), lookup))
				addr := div(addr, 0x10)
				i := sub(i, 1)
				mstore8(i, byte(and(addr, 0xf), lookup))
				addr := div(addr, 0x10)
			}

			ret := keccak256(0, 40)
		}
	}
}
