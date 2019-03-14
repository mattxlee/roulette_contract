const truffleAssert = require("truffle-assertions");
const assert = require("chai").assert;

const Banker = artifacts.require("Banker");

const eth1 = web3.utils.toBN(web3.utils.toWei("1"));
const bigNum = eth => {
    return web3.utils.toBN(eth);
};

const generateRandomNumber = () => {
    const randNumHex = web3.utils.randomHex(32);
    const randNum = web3.utils.toBN(randNumHex);
    const hashHex = web3.utils.keccak256(randNumHex);
    return [randNum, hashHex];
};

const makeSignature = async (magicHex, blockNum, addr) => {
    // randNum connect with blockNum
    const a1 = web3.utils.hexToBytes(magicHex);
    const a2 = blockNum.toArray("be", 32);
    const data = [...a1, ...a2];
    assert.equal(data.length, 64, "The packed data size should be 64!");

    // Make hash message
    const hashHex = web3.utils.keccak256(web3.utils.bytesToHex(data));

    // Make signature
    const signHex = await web3.eth.sign(hashHex, addr);
    const signData = web3.utils.hexToBytes(signHex);
    assert.equal(signData.length, 32 * 2 + 1, "Signature data size is invalid!");

    const signR = signData.splice(0, 32);
    const signS = signData.splice(0, 32);
    const signV = signData[0] + 27;
    return {
        r: signR,
        s: signS,
        v: signV
    };
};

const generateRandomNumberAndSign = async (signV, blockNum, addr) => {
    let [randNum, hashHex] = generateRandomNumber();
    let sign = await makeSignature(hashHex, blockNum, addr);
    while (sign.v !== signV) {
        [randNum, hashHex] = generateRandomNumber();
        sign = await makeSignature(hashHex, blockNum, addr);
    }
    return {
        randNum,
        magicHex: hashHex,
        signR: sign.r,
        signS: sign.s,
        signV: sign.v
    };
};

const makeRandomBetData = () => {
    const data = [1, 100, 129];
    const paddingBytes = 32 - data.length;
    for (let i = 0; i < paddingBytes; ++i) data.push(0);
    const betDataHex = web3.utils.bytesToHex(data);
    return betDataHex;
};

const sleep = secs => {
    return new Promise(resolve => {
        setTimeout(() => {
            resolve();
        }, secs);
    });
};

contract("Banker", async accounts => {
    const ownerAddr = accounts[0];
    const bankerAddr = accounts[1];
    const playerAddr = accounts[2];

    it("Utilities verification.", async () => {
        const blockNum = web3.utils.toBN(await web3.eth.getBlockNumber());
        const signObj = await generateRandomNumberAndSign(28, blockNum, bankerAddr);
        assert.equal(signObj.signV, 28, "Signature is invalid!");
    });

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
            banker.setMaxBetWei(eth1.mul(bigNum(20))),
            "The amount of max bet is out of range!"
        );
    });

    it("Initialize max bet with a very small number should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetWei(eth1.div(bigNum(200))),
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

    it("The eth amount of an initialized contract should be zero.", async () => {
        const banker = await Banker.deployed();
        const balanceStr = await web3.eth.getBalance(banker.address);
        const balance = web3.utils.toBN(balanceStr);
        assert.isTrue(balance.eq(bigNum(0)), "The balance of an initialized contract should be zero!");
    });

    it("Deposit 10 eth to contract with player account.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.passes(banker.deposit({ from: playerAddr, value: eth1.mul(bigNum(10)) }));
    });

    it("The eth amount of the contract should be 10 eth.", async () => {
        const banker = await Banker.deployed();
        const balanceStr = await web3.eth.getBalance(banker.address);
        const balance = web3.utils.toBN(balanceStr);
        assert.isTrue(balance.eq(eth1.mul(bigNum(10))), "The balance is incorrect!");
    });

    it("Withdraw eth by a player account is not allowed.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.withdrawToOwner(eth1, { from: playerAddr }),
            "Only owner can call this function"
        );
    });

    it("Withdraw 1 eth to owner account.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.passes(banker.withdrawToOwner(eth1, { from: ownerAddr }));
    });

    let randObj;
    let blockNum;
    let betDataHex;

    it("Place bet by generating a random number.", async () => {
        const banker = await Banker.deployed();

        blockNum = web3.utils.toBN(await web3.eth.getBlockNumber()).add(web3.utils.toBN(100));
        randObj = await generateRandomNumberAndSign(28, blockNum, bankerAddr);
        betDataHex = makeRandomBetData();

        const tx = await banker.placeBet(randObj.magicHex, blockNum, betDataHex, randObj.signR, randObj.signS, {
            from: playerAddr,
            value: eth1
        });
        truffleAssert.eventEmitted(tx, "BetIsPlaced");
    });

    it("Place same bet again should fail.", async () => {
        const banker = await Banker.deployed();

        truffleAssert.reverts(
            banker.placeBet(randObj.magicHex, blockNum, betDataHex, randObj.signR, randObj.signS, {
                from: playerAddr,
                value: eth1
            }),
            "The slot is not empty."
        );
    });

    it("Wait on next block to reveal.", async () => {
        const targetBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber()).add(web3.utils.toBN(1));

        while (1) {
            await sleep(1000);
            const currBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber());
            if (currBlockNum.gte(targetBlockNum)) {
                break;
            }
        }
    });

    it("Reveal with a wrong number.", async () => {
        const banker = await Banker.deployed();

        await truffleAssert.reverts(banker.revealBet(web3.utils.toBN(123)), "The bet slot cannot be empty.");
    });

    it("Reveal bet.", async () => {
        const banker = await Banker.deployed();

        const tx = await banker.revealBet(randObj.randNum);
        truffleAssert.eventEmitted(tx, "BetIsRevealed");
    });

    it("Reveal bet again should fail.", async () => {
        const banker = await Banker.deployed();

        await truffleAssert.reverts(banker.revealBet(randObj.randNum), "The bet slot cannot be empty.");
    });
});
