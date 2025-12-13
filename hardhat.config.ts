import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configVariable, defineConfig } from "hardhat/config";

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
  // ethernal: {
  //   // optional, you can log in via ENV or interactive
  //   // email: process.env.ETHERNAL_EMAIL,
  //   // password: process.env.ETHERNAL_PASSWORD,
  //   uploadAst: true,
  //   disableSync: false,
  //   disabled: false,
  // },
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
});
