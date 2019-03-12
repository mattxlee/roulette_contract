const truffleAssert = require("truffle-assertions");

const Banker = artifacts.require("Banker");

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
});
