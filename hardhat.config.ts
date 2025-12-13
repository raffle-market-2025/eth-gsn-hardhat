import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configVariable, defineConfig } from "hardhat/config";
//import "hardhat-ethernal";

export default defineConfig({
  plugins: [hardhatToolboxMochaEthersPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  // 👇 hardhat-ethernal config (mirrors plugin docs)
  ethernal: {
    apiToken: process.env.ETHERNAL_API_TOKEN,   // or configVariable("ETHERNAL_API_TOKEN")
    workspace: "eth-gsn-hardhat-local",        // any name you like
    uploadAst: true,                          // enables storage decoding (slower sync) 
    disableSync: false,
    disabled: false,
    // optional:
    // resetOnStart: "eth-gsn-hardhat-local",
    // serverSync: false,
    // skipFirstBlock: true,
    // verbose: true,
  },
  networks: {
    hardhat: {
      // this is an in-memory local node, no url needed
      type: "edr-simulated",
      chainType: "l1",
      chainId: 31337, // optional, but common
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
} as any);
