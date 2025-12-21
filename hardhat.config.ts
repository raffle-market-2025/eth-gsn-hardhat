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
      type: "edr-simulated",   // 👈 important for HH3
      chainType: "l1",
      chainId: 31337,
      forking: {
        url: "https://sepolia.infura.io/v3/c53f023f8f7848b48a452cfaaa1d3718",            // configVariable("SEPOLIA_RPC_URL"),
      },
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
      url: "https://sepolia.infura.io/v3/c53f023f8f7848b48a452cfaaa1d3718",            // configVariable("SEPOLIA_RPC_URL"),
      accounts: ["dd8a8c85dcf602d113fb6d9aa0aff7a95bd8c89335f912d05783650e818b1639"],   // [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
  verify: {
    etherscan: {
      apiKey: "KCVPNIBDSJYE11D61PCJSPT64E9HFXBMGT",   // process.env.ETHERSCAN_API_KEY, // or per-network apiKey object
    },
  },
} as any);
