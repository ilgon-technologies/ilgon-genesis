const log = require("npmlog");
const fsSync = require("fs");
const fs = fsSync.promises;
const path = require("path");
const { exit } = require("process");
const abiCodec = require("ethereumjs-abi");
const solc = require("solc");
const fetch = require("node-fetch");
const semver = require("semver");
const semverSort = require("semver/functions/sort");
const readline = require("readline");

(() => {
  const argv = require("yargs")
    .scriptName("genesis-compiler")
    .usage("$0 <command> [args]")
    .command("compile [config]", "compile a genesis block", cmd => {
      cmd.option("output", {
        alias: "o",
        type: "string",
        default: "genesis.json",
        describe: "output path",
      });
      cmd.positional("config", {
        type: "string",
        describe: "path to the genesis config JSON",
      });
      cmd.demandOption("config");
    })
    .demandCommand()
    .help().argv;
  main(argv);
})();

async function main(argv) {
  if (argv._[0] !== "compile") {
    log.error("", `unknown command "${argv._[0]}"`);
    exit(1);
  }

  let config;
  try {
    config = JSON.parse(await fs.readFile(argv.config, "utf8"));
  } catch (err) {
    log.error("input", "invalid configuration file", err);
    exit(1);
  }

  const versions = await extractSolidityVersions(config);

  const compilers = await Promise.all(
    versions.map(loadCompiler)
  ).then(compilers =>
    compilers.reduce(
      (compilers, compiler, i) => ({ ...compilers, [versions[i]]: compiler }),
      {}
    )
  );

  config.accounts = await compileAccounts(compilers, config.accounts);
  await fs.writeFile(argv.output, JSON.stringify(config, undefined, 2));
  log.info("success", `the output has been written to "${argv.output}"`);
}

async function extractSolidityVersions(config) {
  const allVersions = await fetch(
    "https://binaries.soliditylang.org/bin/list.json"
  ).then(res => res.json());

  const releaseList = semverSort(Object.keys(allVersions.releases)).reverse();

  const versions = new Set();

  for (const accountInfo of Object.values(config.accounts)) {
    if (Object.prototype.hasOwnProperty.call(accountInfo, "constructor")) {
      if (typeof accountInfo.constructor !== "string") {
        versions.add(
          await extractVersion(accountInfo, allVersions.releases, releaseList)
        );
      }
    }
  }

  return Array.from(versions);
}

async function extractVersion(account, releases, releaseList) {
  if (account.constructor.compiler.version) {
    return account.constructor.compiler.version;
  }
  const fileStream = fsSync.createReadStream(
    account.constructor.compiler.file,
    { encoding: "utf-8" }
  );
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (line.startsWith("pragma solidity")) {
      fileStream.close();
      const segments = line.trim().split(/\s+/);
      const ver = segments[segments.length - 1].replace(";", "");

      for (const rel of releaseList) {
        if (semver.satisfies(rel, ver)) {
          return releases[rel].replace("soljson-", "").replace(".js", "");
        }
      }
      throw new Error(`no compiler found for version ${ver}`);
    }
  }
  fileStream.close();

  return "latest";
}

function loadCompiler(version) {
  return new Promise((resolve, reject) => {
    log.info("prepare", `downloading solidity compiler (${version})`);
    solc.loadRemoteVersion(version, (err, compiler) => {
      if (err) {
        reject(err);
        log.error("prepare", "failed to load compiler");
      } else {
        resolve(compiler);
        log.info("prepare", `compiler downloaded (${version})`);
      }
    });
  });
}

async function compileAccounts(compilers, accounts) {
  const compiledAccounts = JSON.parse(JSON.stringify(accounts));

  for (const [address, accountInfo] of Object.entries(accounts)) {
    if (typeof accountInfo === "string") {
      // Already compiled.
      continue;
    }

    let name;
    if (accountInfo.name) {
      name = ` (${accountInfo.name})`;
      // It's just metadata for us.
      delete compiledAccounts[address].name;
    }

    if (!Object.prototype.hasOwnProperty.call(accountInfo, "constructor")) {
      continue;
    }

    log.info("compile", `compiling contract "${address}"${name}`);
    const compilerInfo = accountInfo.constructor.compiler;

    let { abi, data } = await compileSolidity(compilers, compilerInfo);

    const contractConstructor = getConstructor(abi);
    if (typeof contractConstructor !== "undefined") {
      data += encodeConstructorParameters(
        address,
        accountInfo,
        contractConstructor
      );
    }

    compiledAccounts[address].constructor = data;
  }

  return compiledAccounts;
}

async function compileSolidity(compilers, compilerInfo) {
  // We require a different filename because it is included
  // in the bytecode hash and the bytecode must not change.
  const fileName = path.basename(compilerInfo.file);

  const compilerInput = {
    language: "Solidity",
    sources: {
      [fileName]: {
        content: await fs.readFile(compilerInfo.file, "utf-8"),
      },
    },
    settings: {
      outputSelection: {
        [fileName]: {
          [compilerInfo.contractName]: ["abi", "evm.bytecode"],
        },
      },
    },
  };

  if (compilerInfo.settings) {
    compilerInput.settings.optimizer = compilerInfo.settings.optimizer;
  }

  const compiler = compilers[compilerInfo.version];

  const result = JSON.parse(
    compiler.compile(JSON.stringify(compilerInput), {
      import: p => resolveSolidityImport(compilerInfo.file, p),
    })
  );

  if (
    typeof result.contracts === "undefined" ||
    typeof result.contracts[fileName] === "undefined"
  ) {
    log.error("compile", "compilation failed", result.errors);
    exit(1);
  }

  return {
    abi: result.contracts[fileName][compilerInfo.contractName].abi,
    data:
      "0x" +
      result.contracts[fileName][compilerInfo.contractName].evm.bytecode.object,
  };
}

function encodeConstructorParameters(address, accountInfo, constructorAbi) {
  const params = accountInfo.constructor.constructorParameters;
  if (typeof params === "undefined") {
    throw new Error("constructor parameter list missing");
  }

  if (constructorAbi.inputs.length !== params.length) {
    throw new Error(
      address +
        " contract constructor parameter length mismatching (" +
        constructorAbi.inputs.length +
        " but expected " +
        params.length +
        ")"
    );
  }

  const types = [];
  const values = [];
  for (let i = 0; i < constructorAbi.inputs.length; i++) {
    if (constructorAbi.inputs[i].name != params[i].name) {
      throw new Error(
        address +
          " contract constructor parameter name mismatching (" +
          constructorAbi.inputs[i].name +
          " != " +
          params[i].name +
          ")"
      );
    }
    if (constructorAbi.inputs[i].type != params[i].type) {
      throw new Error(
        address +
          " contract constructor parameter name mismatching (" +
          constructorAbi.inputs[i].type +
          " != " +
          params[i].type +
          ")"
      );
    }
    types.push(constructorAbi.inputs[i].type);
    values.push(params[i].value);
  }
  return abiCodec.rawEncode(types, values).toString("hex");
}

/**
 *
 * @param {string} rootSrcPath The path of the main source file.
 * @param {string} resolvePath The path to resolve.
 */
function resolveSolidityImport(rootSrcPath, resolvePath) {
  // We treat non-path imports as path imports as well.
  if (resolvePath.indexOf("/") === -1 && resolvePath.indexOf("\\") === -1) {
    resolvePath = path.join(path.dirname(rootSrcPath), resolvePath);
  }

  try {
    return {
      contents: fsSync.readFileSync(resolvePath, "utf8"),
    };
  } catch {
    return { error: "error reading file" };
  }
}

function getConstructor(abi) {
  for (const v of abi) {
    if (v.type === "constructor") {
      return v;
    }
  }
}
