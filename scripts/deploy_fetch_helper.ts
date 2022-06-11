import { ethers, run } from "hardhat"

async function main() {
    const FetchHelper = await ethers.getContractFactory("SpookyFetchHelper");
    const fetchHelper = await FetchHelper.deploy();
    await fetchHelper.deployed()
  
    console.log("fetch helper deployed to:", fetchHelper.address);

    await run("verify:verify", {
        address: fetchHelper.address
    })
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });