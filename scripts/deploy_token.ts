import { ethers, run } from "hardhat"

async function main() {
    const Token = await ethers.getContractFactory("ERC20Mock");
    const token = await Token.deploy("dummy", "dummy", 1000);
    await token.deployed()
  
    console.log("dummy deployed to:", token.address);

    await run("verify:verify", {
        address: token.address,
        constructorArguments: ["dummy", "dummy", 1000],
    })
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });