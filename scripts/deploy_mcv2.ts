import { ethers, run } from "hardhat"

async function main() {
    const masterchef = "0xb29e8dBF18286f6a2722352CE6D0D365AD3D07e0"
    const axo = "0xC5C24B76de65808eD1c17E411c6C5cfC78FA1A98"
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