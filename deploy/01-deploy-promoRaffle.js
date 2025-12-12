const { network, ethers } = require("hardhat")
const { developmentChains, networkConfig } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")
const { pause } = require("../utils/pause")
const { forwarder } = require('../build/gsn/Forwarder.json');
//const { ForwarderAbi } = require('../forwarder');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    const args = [
       1,
       forwarder.address,    // address _forwarder
       "0",                 // address _promoNft
       deployer
    ]
    console.log(args)

    const raffle = await deploy("PromoRaffle", {
        from: deployer,
        args,
        log: true,
    })

    pause(120000);
    if (!developmentChains.includes(network.name)) {
        console.log("Verifying....")
        await verify(raffle.address, args)
    }

    log("-------------------------------------------")
}

module.exports.tags = ["all", "promoRaffle"]
