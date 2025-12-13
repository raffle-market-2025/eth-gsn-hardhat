import { ethers } from "ethers";
import { defineConfig, configVariable } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

export default defineConfig({
  solidity: "0.8.20",
  plugins: [hardhatVerify],
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"), // или строкой
    },
  },
});

// const networkConfig = {
//     hardhat: {
//         name: "hardhat",
//         id: 31337,
//         vrfCoordinatorV2: "0x00", // we can't hardhatcode is since its on local network
//         vrfLinkToken: "0x00",
//         gasLane: "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
//         // enterFee: ethers.utils.parseEther("0.01"),
//         callbackGasLimit: 500000, // should be 0.0005 LINK
//         subscriptionId: 8051,
//         emailItemOwner: "andrey.installmonster@gmail.com", // _emailItemOwner",
//         dealTicker: "TEST-SOLD-RING", // deal ticker
//     },
//     mumbai: {
//         name: "mumbai",
//         id: 80001,
//         vrfCoordinatorV2: "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed",
//         vrfLinkToken: "0x326C977E6efc84E512bB9C30f76E30c160eD06FB",
//         gasLane: "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
//         //enterFee: ethers.utils.parseEther("0.01"),
//         callbackGasLimit: 500000, // should be 0.0005 LINK
//         subscriptionId: 3617,
//         emailItemOwner: "andrey.installmonster@gmail.com", // _emailItemOwner",
//         dealTicker: "TEST-SOLD-RING", // deal ticker
//     },
//     polygon: {
//         name: "polygon",
//         id: 137,
//         vrfCoordinatorV2: "0xae975071be8f8ee67addbc1a82488f1c24858067",
//         vrfLinkToken: "0xb0897686c545045afc77cf20ec7a532e3120e0f1",
//         gasLane: "0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd",
//         // enterFee: ethers.utils.parseEther("0.01"),
//         callbackGasLimit: 500000, // should be 0.0005 LINK
//         subscriptionId: 787,
//         emailItemOwner: "andrey.installmonster@gmail.com", // _emailItemOwner",
//         dealTicker: "TEST-SOLD-RING", // deal ticker
//     },
//     // 4: {
//     //     name: "rinkeby",
//     //     vrfCoordinatorV2: "0x6168499c0cFfCaCD319c818142124B7A15E857ab",
//     //     entranceFee: ethers.utils.parseEther("0.01"),
//     //     gasLane: "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc",
//     //     subscriptionId: "8051",
//     //     callbackGasLimit: "500000",
//     //     interval: "30",
//     // },
//     // 31337: {
//     //     name: "hardhat",
//     //     entranceFee: ethers.utils.parseEther("0.01"),
//     //     gasLane: "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc",
//     //     callbackGasLimit: "500000",
//     //     interval: "30",
//     // },
// }

const developmentChains = ["localhost", "hardhat"]

module.exports = { developmentChains }