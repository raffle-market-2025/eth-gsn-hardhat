// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const { network, ethers } = require("hardhat")
const { developmentChains, networkConfig } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")
const { pause } = require("../utils/pause")


module.exports = async ({ getNamedAccounts, deployments }) =>  {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const chainName = "polygon"

  const promoRaffleAddress = "0x76Ba00B59c352f6187742861bE4bAdFB422d0523";
  const baseTokenURI = "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json"; 

  const args = [
    baseTokenURI,
    promoRaffleAddress
  ]

  const raffleNFT = await deploy("PromoRaffleNFTs", {
      from: deployer,
      args,
      log: true,
      
  })


  console.log(
  `NFT Promo smart contract deployed to ${raffleNFT.address}`
  );

  pause(120000);

  if (!developmentChains.includes(network.name)) {
      console.log("Verifying....")
      await verify(raffleNFT.address, args)
  }


}

module.exports.tags = ["all", "RafflePromoNFTs"]

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
/*
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
*/
