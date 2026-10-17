import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxMochaEthersPlugin],
  solidity: {
    profiles: {
      default: { version: "0.8.28", settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: "shanghai" } },
      production: { version: "0.8.28", settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: "shanghai" } },
    },
  },
  networks: {
    hardhat: { type: "edr-simulated", chainType: "l1", chainId: 31337 },
    hardhatMainnet: { type: "edr-simulated", chainType: "l1" },
    hardhatOp: { type: "edr-simulated", chainType: "op" },
    sepolia: {
      type: "http", chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
  verify: { etherscan: { apiKey: configVariable("ETHERSCAN_API_KEY") } },
});
