Genesis config contract compiler based on the work of `Andor Rajci`.

## Installation

Run `yarn` to retrieve dependencies.

## Usage

Run `node compiler/index.js --help` for available commands.

Or compile based on a config: `node compiler/index.js compile -o my-genesis.json genesis.conf.json`.

The tool requires an active internet connection.

## Config format

The config is a regular genesis config, except that the `accounts[*].constructor` can be a configuration JSON object instead of bytecode that will be used to compile contracts.

The `accounts[*].name` property can also be provided for additional metadata.

### Constructor config object

```json5
{
    // Compiler options. (required)
    "compiler": {
        // Contract ".sol" source path relative to the current working directory. (required)
        "file": "my-contract.sol",
        // The name of the contract. (required)
        "contractName": "ExampleContract",
        // Full solc version. (optional)
        // If omitted, a version will be determined based on the source file.
        "version": "v0.4.26+commit.4563c3fc",
        // Solc settings. (optional)
        // Currently only the properties below are supported.
        "settings": {
            "optimizer": {
                "enabled": true,
                "runs": 200
            }
        }
    },
    // A list of parameters for the contract. (required)
    "constructorParameters": [
        {
            // Name of the parameter, must match the name in the contract. (required)
            "name":"_param",
            // Additional parameter hint. (optional)
            "hint":"Some address",
            // Type of the parameter, must match the type in the contract ABI. (required)
            "type":"address",
            // Value of the parameter. (required)
            "value":"0xFF00000000000000000000000000000000000000"
        }
    ]
}
```