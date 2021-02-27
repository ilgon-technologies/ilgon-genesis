/*
	Ethereum Name Service interface
	ENSResolvers.sol
	v1.0.0
	Docs: https://docs.ens.domains
*/
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "ENSInterface.sol";
import "ENSDNSsec.sol";

contract ResolverBase {
	bytes4 private constant INTERFACE_META_ID = 0x01ffc9a7;

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == INTERFACE_META_ID;
	}

	function isAuthorised(bytes32 node) internal view returns(bool);

	modifier authorised(bytes32 node) {
		require(isAuthorised(node));
		_;
	}

	function bytesToAddress(bytes memory b) internal pure returns(address payable a) {
		require(b.length == 20);
		assembly {
			a := div(mload(add(b, 32)), exp(256, 12))
		}
	}

	function addressToBytes(address a) internal pure returns(bytes memory b) {
		b = new bytes(20);
		assembly {
			mstore(add(b, 32), mul(a, exp(256, 12)))
		}
	}
}
contract ABIResolver is ResolverBase {
	bytes4 constant private ABI_INTERFACE_ID = 0x2203ab56;

	event ABIChanged(bytes32 indexed node, uint256 indexed contentType);

	mapping(bytes32=>mapping(uint256=>bytes)) abis;

	/**
	 * Sets the ABI associated with an ENS node.
	 * Nodes may have one ABI of each content type. To remove an ABI, set it to
	 * the empty string.
	 * @param node The node to update.
	 * @param contentType The content type of the ABI
	 * @param data The ABI data.
	 */
	function setABI(bytes32 node, uint256 contentType, bytes calldata data) external authorised(node) {
		// Content types must be powers of 2
		require(((contentType - 1) & contentType) == 0);

		abis[node][contentType] = data;
		emit ABIChanged(node, contentType);
	}

	/**
	 * Returns the ABI associated with an ENS node.
	 * Defined in EIP205.
	 * @param node The ENS node to query
	 * @param contentTypes A bitwise OR of the ABI formats accepted by the caller.
	 * @return contentType The content type of the return value
	 * @return data The ABI data
	 */
	function ABI(bytes32 node, uint256 contentTypes) external view returns (uint256, bytes memory) {
		mapping(uint256=>bytes) storage abiset = abis[node];

		for (uint256 contentType = 1; contentType <= contentTypes; contentType <<= 1) {
			if ((contentType & contentTypes) != 0 && abiset[contentType].length > 0) {
				return (contentType, abiset[contentType]);
			}
		}

		return (0, bytes(""));
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == ABI_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract AddrResolver is ResolverBase {
	bytes4 constant private ADDR_INTERFACE_ID = 0x3b3b57de;
	bytes4 constant private ADDRESS_INTERFACE_ID = 0xf1cb7e06;
	uint constant private COIN_TYPE_ETH = 60;

	event AddrChanged(bytes32 indexed node, address a);
	event AddressChanged(bytes32 indexed node, uint coinType, bytes newAddress);

	mapping(bytes32=>mapping(uint=>bytes)) _addresses;

	/**
	 * Sets the address associated with an ENS node.
	 * May only be called by the owner of that node in the ENS registry.
	 * @param node The node to update.
	 * @param a The address to set.
	 */
	function setAddr(bytes32 node, address a) external authorised(node) {
		setAddr(node, COIN_TYPE_ETH, addressToBytes(a));
	}

	/**
	 * Returns the address associated with an ENS node.
	 * @param node The ENS node to query.
	 * @return The associated address.
	 */
	function addr(bytes32 node) public view returns (address payable) {
		bytes memory a = addr(node, COIN_TYPE_ETH);
		if(a.length == 0) {
			return address(0);
		}
		return bytesToAddress(a);
	}

	function setAddr(bytes32 node, uint coinType, bytes memory a) public authorised(node) {
		emit AddressChanged(node, coinType, a);
		if(coinType == COIN_TYPE_ETH) {
			emit AddrChanged(node, bytesToAddress(a));
		}
		_addresses[node][coinType] = a;
	}

	function addr(bytes32 node, uint coinType) public view returns(bytes memory) {
		return _addresses[node][coinType];
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == ADDR_INTERFACE_ID || interfaceID == ADDRESS_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract ContentHashResolver is ResolverBase {
	bytes4 constant private CONTENT_HASH_INTERFACE_ID = 0xbc1c58d1;

	event ContenthashChanged(bytes32 indexed node, bytes hash);

	mapping(bytes32=>bytes) hashes;

	/**
	 * Sets the contenthash associated with an ENS node.
	 * May only be called by the owner of that node in the ENS registry.
	 * @param node The node to update.
	 * @param hash The contenthash to set
	 */
	function setContenthash(bytes32 node, bytes calldata hash) external authorised(node) {
		hashes[node] = hash;
		emit ContenthashChanged(node, hash);
	}

	/**
	 * Returns the contenthash associated with an ENS node.
	 * @param node The ENS node to query.
	 * @return The associated contenthash.
	 */
	function contenthash(bytes32 node) external view returns (bytes memory) {
		return hashes[node];
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == CONTENT_HASH_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract DNSResolver is ResolverBase {
	using RRUtils for *;
	using BytesUtils for bytes;

	bytes4 constant private DNS_RECORD_INTERFACE_ID = 0xa8fa5682;
	bytes4 constant private DNS_ZONE_INTERFACE_ID = 0x5c47637c;

	// DNSRecordChanged is emitted whenever a given node/name/resource's RRSET is updated.
	event DNSRecordChanged(bytes32 indexed node, bytes name, uint16 resource, bytes record);
	// DNSRecordDeleted is emitted whenever a given node/name/resource's RRSET is deleted.
	event DNSRecordDeleted(bytes32 indexed node, bytes name, uint16 resource);
	// DNSZoneCleared is emitted whenever a given node's zone information is cleared.
	event DNSZoneCleared(bytes32 indexed node);

	// DNSZonehashChanged is emitted whenever a given node's zone hash is updated.
	event DNSZonehashChanged(bytes32 indexed node, bytes lastzonehash, bytes zonehash);

	// Zone hashes for the domains.
	// A zone hash is an EIP-1577 content hash in binary format that should point to a
	// resource containing a single zonefile.
	// node => contenthash
	mapping(bytes32=>bytes) private zonehashes;

	// Version the mapping for each zone.  This allows users who have lost
	// track of their entries to effectively delete an entire zone by bumping
	// the version number.
	// node => version
	mapping(bytes32=>uint256) private versions;

	// The records themselves.  Stored as binary RRSETs
	// node => version => name => resource => data
	mapping(bytes32=>mapping(uint256=>mapping(bytes32=>mapping(uint16=>bytes)))) private records;

	// Count of number of entries for a given name.  Required for DNS resolvers
	// when resolving wildcards.
	// node => version => name => number of records
	mapping(bytes32=>mapping(uint256=>mapping(bytes32=>uint16))) private nameEntriesCount;

	/**
	 * Set one or more DNS records.  Records are supplied in wire-format.
	 * Records with the same node/name/resource must be supplied one after the
	 * other to ensure the data is updated correctly. For example, if the data
	 * was supplied:
	 *	 a.example.com IN A 1.2.3.4
	 *	 a.example.com IN A 5.6.7.8
	 *	 www.example.com IN CNAME a.example.com.
	 * then this would store the two A records for a.example.com correctly as a
	 * single RRSET, however if the data was supplied:
	 *	 a.example.com IN A 1.2.3.4
	 *	 www.example.com IN CNAME a.example.com.
	 *	 a.example.com IN A 5.6.7.8
	 * then this would store the first A record, the CNAME, then the second A
	 * record which would overwrite the first.
	 *
	 * @param node the namehash of the node for which to set the records
	 * @param data the DNS wire format records to set
	 */
	function setDNSRecords(bytes32 node, bytes calldata data) external authorised(node) {
		uint16 resource = 0;
		uint256 offset = 0;
		bytes memory name;
		bytes memory value;
		bytes32 nameHash;
		// Iterate over the data to add the resource records
		for (RRUtils.RRIterator memory iter = data.iterateRRs(0); !iter.done(); iter.next()) {
			if (resource == 0) {
				resource = iter.dnstype;
				name = iter.name();
				nameHash = keccak256(abi.encodePacked(name));
				value = bytes(iter.rdata());
			} else {
				bytes memory newName = iter.name();
				if (resource != iter.dnstype || !name.equals(newName)) {
					setDNSRRSet(node, name, resource, data, offset, iter.offset - offset, value.length == 0);
					resource = iter.dnstype;
					offset = iter.offset;
					name = newName;
					nameHash = keccak256(name);
					value = bytes(iter.rdata());
				}
			}
		}
		if (name.length > 0) {
			setDNSRRSet(node, name, resource, data, offset, data.length - offset, value.length == 0);
		}
	}

	/**
	 * Obtain a DNS record.
	 * @param node the namehash of the node for which to fetch the record
	 * @param name the keccak-256 hash of the fully-qualified name for which to fetch the record
	 * @param resource the ID of the resource as per https://en.wikipedia.org/wiki/List_of_DNS_record_types
	 * @return the DNS record in wire format if present, otherwise empty
	 */
	function dnsRecord(bytes32 node, bytes32 name, uint16 resource) public view returns (bytes memory) {
		return records[node][versions[node]][name][resource];
	}

	/**
	 * Check if a given node has records.
	 * @param node the namehash of the node for which to check the records
	 * @param name the namehash of the node for which to check the records
	 */
	function hasDNSRecords(bytes32 node, bytes32 name) public view returns (bool) {
		return (nameEntriesCount[node][versions[node]][name] != 0);
	}

	/**
	 * Clear all information for a DNS zone.
	 * @param node the namehash of the node for which to clear the zone
	 */
	function clearDNSZone(bytes32 node) public authorised(node) {
		versions[node]++;
		emit DNSZoneCleared(node);
	}

	/**
	 * setZonehash sets the hash for the zone.
	 * May only be called by the owner of that node in the ENS registry.
	 * @param node The node to update.
	 * @param hash The zonehash to set
	 */
	function setZonehash(bytes32 node, bytes calldata hash) external authorised(node) {
		bytes memory oldhash = zonehashes[node];
		zonehashes[node] = hash;
		emit DNSZonehashChanged(node, oldhash, hash);
	}

	/**
	 * zonehash obtains the hash for the zone.
	 * @param node The ENS node to query.
	 * @return The associated contenthash.
	 */
	function zonehash(bytes32 node) external view returns (bytes memory) {
		return zonehashes[node];
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == DNS_RECORD_INTERFACE_ID ||
			   interfaceID == DNS_ZONE_INTERFACE_ID ||
			   super.supportsInterface(interfaceID);
	}

	function setDNSRRSet(
		bytes32 node,
		bytes memory name,
		uint16 resource,
		bytes memory data,
		uint256 offset,
		uint256 size,
		bool deleteRecord) private
	{
		uint256 version = versions[node];
		bytes32 nameHash = keccak256(name);
		bytes memory rrData = data.substring(offset, size);
		if (deleteRecord) {
			if (records[node][version][nameHash][resource].length != 0) {
				nameEntriesCount[node][version][nameHash]--;
			}
			delete(records[node][version][nameHash][resource]);
			emit DNSRecordDeleted(node, name, resource);
		} else {
			if (records[node][version][nameHash][resource].length == 0) {
				nameEntriesCount[node][version][nameHash]++;
			}
			records[node][version][nameHash][resource] = rrData;
			emit DNSRecordChanged(node, name, resource, rrData);
		}
	}
}
contract InterfaceResolver is ResolverBase, AddrResolver {
	bytes4 constant private INTERFACE_INTERFACE_ID = bytes4(keccak256("interfaceImplementer(bytes32,bytes4)"));
	bytes4 private constant INTERFACE_META_ID = 0x01ffc9a7;

	event InterfaceChanged(bytes32 indexed node, bytes4 indexed interfaceID, address implementer);

	mapping(bytes32=>mapping(bytes4=>address)) interfaces;

	/**
	 * Sets an interface associated with a name.
	 * Setting the address to 0 restores the default behaviour of querying the contract at `addr()` for interface support.
	 * @param node The node to update.
	 * @param interfaceID The EIP 165 interface ID.
	 * @param implementer The address of a contract that implements this interface for this node.
	 */
	function setInterface(bytes32 node, bytes4 interfaceID, address implementer) external authorised(node) {
		interfaces[node][interfaceID] = implementer;
		emit InterfaceChanged(node, interfaceID, implementer);
	}

	/**
	 * Returns the address of a contract that implements the specified interface for this name.
	 * If an implementer has not been set for this interfaceID and name, the resolver will query
	 * the contract at `addr()`. If `addr()` is set, a contract exists at that address, and that
	 * contract implements EIP165 and returns `true` for the specified interfaceID, its address
	 * will be returned.
	 * @param node The ENS node to query.
	 * @param interfaceID The EIP 165 interface ID to check for.
	 * @return The address that implements this interface, or 0 if the interface is unsupported.
	 */
	function interfaceImplementer(bytes32 node, bytes4 interfaceID) external view returns (address) {
		address implementer = interfaces[node][interfaceID];
		if(implementer != address(0)) {
			return implementer;
		}

		address a = addr(node);
		if(a == address(0)) {
			return address(0);
		}

		(bool success, bytes memory returnData) = a.staticcall(abi.encodeWithSignature("supportsInterface(bytes4)", INTERFACE_META_ID));
		if(!success || returnData.length < 32 || returnData[31] == 0) {
			// EIP 165 not supported by target
			return address(0);
		}

		(success, returnData) = a.staticcall(abi.encodeWithSignature("supportsInterface(bytes4)", interfaceID));
		if(!success || returnData.length < 32 || returnData[31] == 0) {
			// Specified interface not supported by target
			return address(0);
		}

		return a;
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == INTERFACE_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract NameResolver is ResolverBase {
	bytes4 constant private NAME_INTERFACE_ID = 0x691f3431;

	event NameChanged(bytes32 indexed node, string name);

	mapping(bytes32=>string) names;

	/**
	 * Sets the name associated with an ENS node, for reverse records.
	 * May only be called by the owner of that node in the ENS registry.
	 * @param node The node to update.
	 * @param name The name to set.
	 */
	function setName(bytes32 node, string calldata name) external authorised(node) {
		names[node] = name;
		emit NameChanged(node, name);
	}

	/**
	 * Returns the name associated with an ENS node, for reverse records.
	 * Defined in EIP181.
	 * @param node The ENS node to query.
	 * @return The associated name.
	 */
	function name(bytes32 node) external view returns (string memory) {
		return names[node];
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == NAME_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract PubkeyResolver is ResolverBase {
	bytes4 constant private PUBKEY_INTERFACE_ID = 0xc8690233;

	event PubkeyChanged(bytes32 indexed node, bytes32 x, bytes32 y);

	struct PublicKey {
		bytes32 x;
		bytes32 y;
	}

	mapping(bytes32=>PublicKey) pubkeys;

	/**
	 * Sets the SECP256k1 public key associated with an ENS node.
	 * @param node The ENS node to query
	 * @param x the X coordinate of the curve point for the public key.
	 * @param y the Y coordinate of the curve point for the public key.
	 */
	function setPubkey(bytes32 node, bytes32 x, bytes32 y) external authorised(node) {
		pubkeys[node] = PublicKey(x, y);
		emit PubkeyChanged(node, x, y);
	}

	/**
	 * Returns the SECP256k1 public key associated with an ENS node.
	 * Defined in EIP 619.
	 * @param node The ENS node to query
	 * @return x, y the X and Y coordinates of the curve point for the public key.
	 */
	function pubkey(bytes32 node) external view returns (bytes32 x, bytes32 y) {
		return (pubkeys[node].x, pubkeys[node].y);
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == PUBKEY_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract TextResolver is ResolverBase {
	bytes4 constant private TEXT_INTERFACE_ID = 0x59d1d43c;

	event TextChanged(bytes32 indexed node, string indexed indexedKey, string key);

	mapping(bytes32=>mapping(string=>string)) texts;

	/**
	 * Sets the text data associated with an ENS node and key.
	 * May only be called by the owner of that node in the ENS registry.
	 * @param node The node to update.
	 * @param key The key to set.
	 * @param value The text data value to set.
	 */
	function setText(bytes32 node, string calldata key, string calldata value) external authorised(node) {
		texts[node][key] = value;
		emit TextChanged(node, key, key);
	}

	/**
	 * Returns the text data associated with an ENS node and key.
	 * @param node The ENS node to query.
	 * @param key The text data key to query.
	 * @return The associated text data.
	 */
	function text(bytes32 node, string calldata key) external view returns (string memory) {
		return texts[node][key];
	}

	function supportsInterface(bytes4 interfaceID) public pure returns(bool) {
		return interfaceID == TEXT_INTERFACE_ID || super.supportsInterface(interfaceID);
	}
}
contract PublicResolver is ABIResolver, AddrResolver, ContentHashResolver, DNSResolver, InterfaceResolver, NameResolver, PubkeyResolver, TextResolver {
	ENS ens;

	/**
	 * A mapping of authorisations. An address that is authorised for a name
	 * may make any changes to the name that the owner could, but may not update
	 * the set of authorisations.
	 * (node, owner, caller) => isAuthorised
	 */
	mapping(bytes32=>mapping(address=>mapping(address=>bool))) public authorisations;

	event AuthorisationChanged(bytes32 indexed node, address indexed owner, address indexed target, bool isAuthorised);

	constructor(ENS _ens) public {
		ens = _ens;
	}

	/**
	 * @dev Sets or clears an authorisation.
	 * Authorisations are specific to the caller. Any account can set an authorisation
	 * for any name, but the authorisation that is checked will be that of the
	 * current owner of a name. Thus, transferring a name effectively clears any
	 * existing authorisations, and new authorisations can be set in advance of
	 * an ownership transfer if desired.
	 *
	 * @param node The name to change the authorisation on.
	 * @param target The address that is to be authorised or deauthorised.
	 * @param isAuthorised True if the address should be authorised, or false if it should be deauthorised.
	 */
	function setAuthorisation(bytes32 node, address target, bool isAuthorised) external {
		authorisations[node][msg.sender][target] = isAuthorised;
		emit AuthorisationChanged(node, msg.sender, target, isAuthorised);
	}

	function isAuthorised(bytes32 node) internal view returns(bool) {
		address owner = ens.owner(node);
		return owner == msg.sender || authorisations[node][owner][msg.sender];
	}

	function multicall(bytes[] calldata data) external returns(bytes[] memory results) {
		results = new bytes[](data.length);
		for(uint i = 0; i < data.length; i++) {
			(bool success, bytes memory result) = address(this).delegatecall(data[i]);
			require(success);
			results[i] = result;
		}
		return results;
	}
}
