import { ethers, run } from "hardhat"

const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"

async function main() {

    // Edit these before deployment
    const rewardToken = "0x4beAf010A2cF3469D26D6754D65Fc5a19e8F3AA0"
    const rewardPerBlock = 0
    // end of edit

    const masterchefv2 = "0xFfDCb4e461130889908444221a8714bbF04D18cA"
    const Rewarder = await ethers.getContractFactory("ComplexRewarder");
    const rewarder = await Rewarder.deploy(rewardToken, rewardPerBlock, masterchefv2);
    await rewarder.deployed()
  
    console.log("rewarder deployed to:", rewarder.address);

    await run("verify:verify", {
        address: rewarder.address,
        constructorArguments: [rewardToken, rewardPerBlock, masterchefv2],
    })
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });