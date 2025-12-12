const { ethers } = require("hardhat")

module.exports = (amount) => {
    return ethers.utils.parseEther(amount.toString())
}
