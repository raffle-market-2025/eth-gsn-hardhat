import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import { network } from "hardhat"
//import { Web3 } from 'web3'
import developmentChains from "../helper-hardhat-config.js";
import verify from "../utils/verify.js";
import pause from "../utils/pause.js"
const { forwarder } = require('../build/gsn/Forwarder.json');
//import { ForwarderAbi } = require('../forwarder');


const func: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    const args = [
       1,
       forwarder.address,
       deployer
    ]
    console.log(args)

    const promoRaffle = await deploy( "PromoRaffle", {
        from: deployer,
        args,
        log: true,
    })

    // pause(120000);
    // if (!developmentChains.includes(network.name)) {
    //     console.log("Verifying PromoRaffle ....")
    //     await verify(promoRaffle.address, args)
    // }


    const baseTokenURI = "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json"; 

    const argsNFT = [
        baseTokenURI,
        promoRaffle.address
    ]

    const promoRaffleNFT = await deploy( "PromoNFT", {
        from: deployer,
        args,
        log: true,
    })

    console.log(`NFT Storage for PromoRaffle smart contract deployed to ${promoRaffleNFT.address}`)

    // pause(120000);
    // if (!developmentChains.includes(network.name)) {
    //     console.log("Verifying promoRaffleNFT storage ....")
    //     await verify(promoRaffleNFT.address, args)
    // }

    log("----- PromoRaffle deployed ---------------------------------------")


    // Use an HTTP provider for read-only operations (view/pure functions)
    const providerUrl = 'http://127.0.0.1:8545/'; // e.g., an Infura URL
    // const web3 = new Web3(providerUrl);

    // const contractABI = [ /* paste your contract's ABI array here */ ];
    // const contractAddress = 'YOUR_CONTRACT_ADDRESS'; // e.g., 0x123...

    // const myContract = new web3.eth.Contract(contractABI, contractAddress);



    // let provider = new ethers.providers.Web3Provider(window.ethereum);
    // let signer = provider.getSigner();
  
    // const myRecipient = new ethers.Contract(PromoRaffle, promoRaffleAbi, signer);    
    // const gsnContract = await wrapContract(myRecipient, config); 
    // const tx = await gsnContract.enterRaffle();
    // console.log("TX:  ", tx);
}

func.tags = ["all", "promoRaffle"]

export default func;