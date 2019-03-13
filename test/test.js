const truffleAssert = require("truffle-assertions");
const assert = require("chai").assert;

const Banker = artifacts.require("Banker");

const eth1 = web3.utils.toBN(web3.utils.toWei("1"));
const bignum = eth => {
    return web3.utils.toBN(eth);
};

contract("Banker", async accounts => {
    const ownerAddr = accounts[0];
    const bankerAddr = accounts[1];
    const playerAddr = accounts[2];

    it("Setup banker address with normal player should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setBanker(bankerAddr, { from: playerAddr }),
            "Only owner can call this function."
        );
    });

    it("Setup banker address.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.passes(banker.setBanker(bankerAddr, { from: ownerAddr }));
    });

    it("Initialize max bet with normal player account should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetWei(eth1, { from: playerAddr }),
            "Only owner can call this function."
        );
    });

    it("Initialize max bet with a very big number should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetWei(eth1.mul(bignum(20))),
            "The amount of max bet is out of range!"
        );
    });

    it("Initialize max bet with a very small number should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetWei(eth1.div(bignum(200))),
            "The amount of max bet is out of range!"
        );
    });

    it("Initialize max bet to 1 eth.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.passes(banker.setMaxBetWei(eth1, { from: ownerAddr }));
    });

    it("Verify max bet with 1 eth.", async () => {
        const banker = await Banker.deployed();
        const val = await banker.maxBetWei.call();
        assert.isTrue(val.eq(eth1), "Max bet is not 1 eth!");
    });
});
