import { ethers, run } from "hardhat"

async function main() {
    const Token = await ethers.getContractFactory("Axoswap");
    const MC = await ethers.getContractFactory("MasterChef");
    const token = await Token.deploy();
    const mc = await MC.deploy(token.address, "0x777772284e7786083eaB0911D6fAde6464F5c94A",5 , 29914736, 32506736)

    await token.deployed()
  
    console.log("Axo Token deployed to:", token.address);
    await mc.deployed();
    console.log("Masterchef deployed to", mc.address);

    await run("verify:verify", {
        address: token.address,
        constructorArguments: [],
    })
  }
  main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
  