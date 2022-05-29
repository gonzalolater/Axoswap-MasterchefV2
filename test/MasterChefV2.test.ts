import { ADDRESS_ZERO, deploy, getBigNumber, prepare, advanceTimeAndBlock, timestamp } from "./utilities"
import { expect } from "chai"

describe("MasterChefV2", function () {
  before(async function () {
    await prepare(this, ["MasterChef", "Axolotl", "ERC20Mock", "MasterChefV2", "ComplexRewarder"])
    //await deploy(this, [["brokenRewarder", this.RewarderBrokenMock]])
  })

  beforeEach(async function () {
    await deploy(this, [["Axo", this.SpookyToken]])

    await deploy(this, [
      ["lp", this.ERC20Mock, ["LP Token", "LPT", getBigNumber(10)]],
      ["dummy", this.ERC20Mock, ["Dummy", "DummyT", getBigNumber(10)]],
      ["chef", this.MasterChef, [this.Axo.address, this.bob.address, getBigNumber(100), getBigNumber(0)]],
    ])

    await this.Axo.transferOwnership(this.chef.address)
    await this.chef.add(100, this.lp.address)
    await this.chef.add(100, this.dummy.address)
    await this.lp.approve(this.chef.address, getBigNumber(10))
    await this.chef.deposit(0, getBigNumber(10))

    await deploy(this, [
      ["chef2", this.MasterChefV2, [this.chef.address, this.Axo.address, 1]],
      ["rlp", this.ERC20Mock, ["LP", "rLPT", getBigNumber(10)]],
      ["r", this.ERC20Mock, ["Reward", "RewardT", getBigNumber(100000)]],
      ["r2", this.ERC20Mock, ["Reward2", "RewardT2", getBigNumber(100000)]],
    ])
    await deploy(this, [["rewarder", this.ComplexRewarder, [this.r.address, getBigNumber(50), this.chef2.address]]])
    await deploy(this, [["rewarder2", this.ComplexRewarder, [this.r2.address, getBigNumber(50), this.chef2.address]]])
    await this.dummy.approve(this.chef2.address, getBigNumber(10))
    await this.chef2.init(this.dummy.address)
    await this.rlp.transfer(this.bob.address, getBigNumber(1))

  })
  
  describe("Suspicious actions", function () {
    it("Multiple deposits", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      await advanceTimeAndBlock(100)
      await expect(this.chef2.harvestFromMasterChef()).to.not.be.reverted
      await expect(this.chef2["deposit(uint256,uint256,address)"](0, getBigNumber(1), this.alice.address)).to.not.be.reverted
      await advanceTimeAndBlock(10)
      // await expect(this.chef2.set(0, 10, this.rewarder.address, false, true)).to.not.be.reverted
      await expect(this.chef2["deposit(uint256,uint256,address)"](0, getBigNumber(1), this.alice.address)).to.not.be.reverted
      await advanceTimeAndBlock(10)
      // await expect(this.chef2.set(0, 0, this.rewarder.address, false, true)).to.not.be.reverted
      await expect(this.chef2["deposit(uint256,uint256,address)"](0, getBigNumber(1), this.alice.address)).to.not.be.reverted
    })
  })

  describe("Init", function () {
    it("Balance of dummyToken should be 0 after init(), repeated execution should fail", async function () {
      await expect(this.chef2.init(this.dummy.address)).to.be.revertedWith("Balance must exceed 0")
    })
  })

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      expect(await this.chef2.poolLength()).to.be.equal(1)
    })
  })

  describe("Set", function () {
    it("Should emit event LogSetPool", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await expect(await this.chef2.set(0, 10, this.rewarder.address, false, true))
        .to.emit(this.chef2, "LogSetPool")
        .withArgs(0, 10, this.rewarder.address, false, true)
    })

    it("Should revert if invalid pool", async function () {
      await expect(this.chef2.set(3, 10, this.rewarder.address, false, false)).to.be.reverted
    })
  })

  describe("PendingTokens", function () {
    it("PendingAxo should equal ExpectedAxo", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      let log = await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)
      await advanceTimeAndBlock(10)
      let log2 = await this.chef2.updatePool(0)

      let time1 = await timestamp(log.blockNumber)
      let time2 = await timestamp(log2.blockNumber)

      let expectedAxo = getBigNumber(100)
        .mul(time2 - time1)
        .div(2)

      let pendingAXO = await this.chef2.pendingAXO(0, this.alice.address)
      expect(pendingAXO).to.be.equal(expectedAxo) // 50
    })
    it("PendingReward should equal ExpectedReward", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.rewarder.add(10, 0, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      let log = await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)
      await advanceTimeAndBlock(10)
      let log2 = await this.chef2.updatePool(0)

      let time1 = await timestamp(log.blockNumber)
      let time2 = await timestamp(log2.blockNumber)

      let expectedReward = getBigNumber(50)
        .mul(time2 - time1)

      let pendingreward = await this.rewarder.pendingToken(0, this.alice.address)
      expect(pendingreward).to.be.equal(expectedReward) // 50
    })
    it("Should give complex rewards and work properly if poolweight is 0 (no axo rewards)", async function () {
      await this.chef2.add(0, this.rlp.address, this.rewarder.address, false)
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.rewarder.add(10, 0, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      let log = await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)
      await advanceTimeAndBlock(10)
      let log2 = await this.chef2.updatePool(0)

      let time1 = await timestamp(log.blockNumber)
      let time2 = await timestamp(log2.blockNumber)

      let expectedReward = getBigNumber(50)
        .mul(time2 - time1)

      let pendingreward = await this.rewarder.pendingToken(0, this.alice.address)
      expect(pendingreward).to.be.equal(expectedReward) // 50
      expect(await this.chef2.pendingAXO(0, this.alice.address)).to.be.equal(0) //no axo rewards!
    })
  })

  describe("MassUpdatePools", function () {
    it("Should call updatePool", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await advanceTimeAndBlock(10)
      await expect(this.chef2.massUpdatePools([0])).to.not.be.reverted
    })

    it("Updating invalid pools should fail", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await advanceTimeAndBlock(10)
      await expect(this.chef2.massUpdatePools([0, 10000, 100000])).to.be.reverted
    })
  })

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef2.add(10, this.rlp.address, this.rewarder.address, false))
        .to.emit(this.chef2, "LogPoolAddition")
        .withArgs(0, 10, this.rlp.address, this.rewarder.address, false)
    })
  })

  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      await expect(this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(0), this.alice.address))
        .to.emit(this.chef2, "Deposit")
        .withArgs(this.alice.address, 0, 0, this.alice.address)
    })

    it("Depositing into non-existent pool should fail", async function () {
        await expect(this.chef2['deposit(uint256,uint256,address)'](1001, getBigNumber(0), this.alice.address)).to.be.reverted
    })
  })

  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await expect(this.chef2['withdraw(uint256,uint256,address)'](0, getBigNumber(0), this.alice.address))
        .to.emit(this.chef2, "Withdraw")
        .withArgs(this.alice.address, 0, 0, this.alice.address)
    })
  })

  describe("Harvest", function () {
    /*it("Should give back the correct amount of Axo and reward and reward2", async function () {
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.r2.transfer(this.rewarder2.address, getBigNumber(100000))
      await this.rewarder.add(10, 0, false)
      await this.rewarder2.add(10, 0, false)
      await this.chef2.add(10, this.rlp.address, [this.rewarder.address, this.rewarder2.address], false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      expect(await this.chef2.lpToken(0)).to.be.equal(this.rlp.address)
      let log = await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)
      await advanceTimeAndBlock(10)
      let log2 = await this.chef2['withdraw(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)

      let time1 = await timestamp(log.blockNumber)
      let time2 = await timestamp(log2.blockNumber)

      let expectedAxo = getBigNumber(100)
        .mul(time2 - time1)
        .div(2)

      expect(await this.Axo.balanceOf(this.alice.address))
        .to.be.equal(await this.r.balanceOf(this.alice.address))
        .to.be.equal(await this.r2.balanceOf(this.alice.address))
        .to.be.equal(expectedAxo)
    })*/
    it("Harvest with empty user balance", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.chef2['withdraw(uint256,uint256,address)'](0, 0, this.alice.address)
    })

    it("Harvest for Axo-only pool", async function () {
      await this.chef2.add(10, this.rlp.address, ADDRESS_ZERO, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      expect(await this.chef2.lpToken(0)).to.be.equal(this.rlp.address)
      let log = await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)
      await advanceTimeAndBlock(10)
      let log2 = await this.chef2['withdraw(uint256,uint256,address)'](0, getBigNumber(1), this.alice.address)

      let time1 = await timestamp(log.blockNumber)
      let time2 = await timestamp(log2.blockNumber)

      let expectedAxo = getBigNumber(100)
        .mul(time2 - time1)
        .div(2)

      expect(await this.Axo.balanceOf(this.alice.address)).to.be.equal(expectedAxo)
    })
  })

  describe("EmergencyWithdraw", function () {
    it("Should emit event EmergencyWithdraw", async function () {
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.chef2.add(10, this.rlp.address, this.rewarder.address, false)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      await this.chef2['deposit(uint256,uint256,address)'](0, getBigNumber(1), this.bob.address)
      await expect(this.chef2.connect(this.bob).emergencyWithdraw(0, this.bob.address))
        .to.emit(this.chef2, "EmergencyWithdraw")
        .withArgs(this.bob.address, 0, getBigNumber(1), this.bob.address)
    })
  })
})
