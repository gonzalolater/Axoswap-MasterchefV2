import { task, types } from "hardhat/config"
import "dotenv/config"
import "ethers"
import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-solhint"
import "@nomiclabs/hardhat-ethers"
import "hardhat-abi-exporter"
import "solidity-coverage"
import "hardhat-spdx-license-identifier"
import { HardhatUserConfig } from "hardhat/types"
import "hardhat-gas-reporter"
import { clear } from "console"

const MASTER_PID = 25
const MCV1 = "0xC5C24B76de65808eD1c17E411c6C5cfC78FA1A98"
const MCV2 = "0xb80d90DA1231C84DD1327CcaFD9b750e03a0264E"

task("addpool", "Adds pool to MCv2").addParam("allocPoint", "Amount of points to allocate to the new pool", undefined, types.int).addParam("lpToken", "Address of the LP tokens for the farm").addOptionalParam("update", "true if massUpdateAllPools should be called", false, types.boolean).addParam("sleep", "Time in seconds to sleep between adding and setting up the pool", undefined, types.int).setAction(async (taskArgs, hre) => {
  const wait = (milliseconds) => {
    return new Promise(resolve => setTimeout(resolve, milliseconds))
  }

  let allocPoint, lpToken, tx
  allocPoint = hre.ethers.utils.parseUnits((taskArgs.allocPoint).toString(), 0)

  try {
    lpToken = hre.ethers.utils.getAddress(taskArgs.lpToken)
  } catch {
    console.log("ERROR: LP token address not valid")
    return
  }

  //set this manually here when needed
  let rewarders = []
  let overwrite = true

  let MCv1 = await hre.ethers.getContractAt("MasterChef", MCV1)
  let MCv2 = await hre.ethers.getContractAt("MasterChefV2", MCV2)

  console.log("Adding pool...")
  tx = await MCv2.add(0, lpToken, rewarders, taskArgs.update)
  await tx.wait();

  console.log("Sleeping for " + taskArgs.sleep + " seconds...")
  await wait(taskArgs.sleep * 1000)

  console.log("Adjusting MCv1 allocation...")
  let newAlloc = Number(hre.ethers.utils.formatUnits((await MCv1.poolInfo(MASTER_PID)).allocPoint, 0)) + Number(taskArgs.allocPoint)
  tx = await MCv1.set(MASTER_PID, newAlloc)
  await tx.wait();

  console.log("Setting new MCv2 pool allocation...")
  let pid = (await MCv2.poolInfoAmount) - 1
  tx = await MCv2.set(pid, allocPoint, rewarders, overwrite, taskArgs.update)
  await tx.wait();
});

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html

const getAccounts = (network: string) => {
  const accounts = {
    goerli: process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY : [],
    polygon: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
  };
  if (!accounts[network]) {
    throw new Error(`Your account environment variables for ${network} are not set`);
  }
  return accounts[network];
};
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const config: HardhatUserConfig = {
  mocha: {
    timeout: 40000,
  },
  etherscan: {
    apiKey: process.env.API_KEY
  },
  defaultNetwork: "goerli",
  networks: {
    hardhat: {
    },
    goerli: {
      url: process.env.GOERLI_URL,
      accounts: getAccounts("goerli"),
      chainId: 5,
      gasPrice: 45000000000,
    },
    polygon: {
      url: process.env.GOERLI_URL,
      accounts: getAccounts("polygon"),
      chainId: 137,
      gasPrice: 45000000000,

    },
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
}
export default config