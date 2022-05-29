import { ethers, run } from "hardhat"

async function main() {
    const masterchef = "0x0d6995072186C54AaCea93f112B86C125B6Ee6F3"
    const axo = "0x4beAf010A2cF3469D26D6754D65Fc5a19e8F3AA0"
    const pid = 25
    const Mcv2 = await ethers.getContractFactory("MasterChefV2");
    const mcv2 = await Mcv2.deploy(masterchef, axo, pid);
    await mcv2.deployed()
  
    console.log("mcv2 deployed to:", mcv2.address);

    await run("verify:verify", {
        address: mcv2.address,
        constructorArguments: [masterchef, axo, pid],
    })
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });