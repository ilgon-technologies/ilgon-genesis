/*
	ENS Deployer
	ENSDeployer.sol
	v1.0.0
	Docs: https://docs.ens.domains
*/
pragma solidity 0.5.17;

import "ENS.sol";
import "ENSResolvers.sol";

// Construct a set of test ENS contracts.
contract ENSDeployer {
	bytes32 constant TLD_LABEL = keccak256("ilg");
	bytes32 constant RESOLVER_LABEL = keccak256("resolver");
	bytes32 constant REVERSE_REGISTRAR_LABEL = keccak256("reverse");
	bytes32 constant ADDR_LABEL = keccak256("addr");

	ENSRegistry public ens;
	FIFSRegistrar public fifsRegistrar;
	ReverseRegistrar public reverseRegistrar;
	PublicResolver public publicResolver;

	constructor() public {
		ens = new ENSRegistry();
		publicResolver = new PublicResolver(ens);

		// Set up the resolver
		bytes32 resolverNode = namehash(bytes32(0), RESOLVER_LABEL);

		ens.setSubnodeOwner(bytes32(0), RESOLVER_LABEL, address(this));
		ens.setResolver(resolverNode, address(publicResolver));
		publicResolver.setAddr(resolverNode, address(publicResolver));

		// Create a FIFS registrar for the TLD
		fifsRegistrar = new FIFSRegistrar(ens, namehash(bytes32(0), TLD_LABEL));

		ens.setSubnodeOwner(bytes32(0), TLD_LABEL, address(fifsRegistrar));

		// Construct a new reverse registrar and point it at the public resolver
		reverseRegistrar = new ReverseRegistrar(ens, PublicResolver(address(publicResolver)));

		// Set up the reverse registrar
		ens.setSubnodeOwner(bytes32(0), REVERSE_REGISTRAR_LABEL, address(this));
		ens.setSubnodeOwner(namehash(bytes32(0), REVERSE_REGISTRAR_LABEL), ADDR_LABEL, address(reverseRegistrar));
	}
	function namehash(bytes32 node, bytes32 label) internal pure returns (bytes32) {
		return keccak256(abi.encodePacked(node, label));
	}
}
