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
    const data = [1, 100, 149];
    const paddingBytes = 32 - data.length;
    for (let i = 0; i < paddingBytes; ++i) data.push(0);
    const betDataHex = web3.utils.bytesToHex(data);
    return betDataHex;
};

const sleep = msecs => {
    return new Promise(resolve => {
        setTimeout(() => {
            resolve();
        }, msecs);
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
            banker.setMaxBetEth(eth1, { from: playerAddr }),
            "Only owner can call this function."
        );
    });

    it("Initialize max bet with a very big number should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetEth(eth1.mul(bigNum(20))),
            "The amount of max bet is out of range!"
        );
    });

    it("Initialize max bet with a very small number should fail.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.reverts(
            banker.setMaxBetEth(eth1.div(bigNum(200))),
            "The amount of max bet is out of range!"
        );
    });

    it("Initialize max bet to 1 eth.", async () => {
        const banker = await Banker.deployed();
        await truffleAssert.passes(banker.setMaxBetEth(eth1, { from: ownerAddr }));
    });

    it("Verify max bet with 1 eth.", async () => {
        const banker = await Banker.deployed();
        const val = await banker.maxBetEth.call();
        assert.isTrue(val.eq(eth1), "Max bet is not 1 eth!");
    });

    it("The eth amount of an just initialized contract should be zero.", async () => {
        const banker = await Banker.deployed();
        const balanceStr = await web3.eth.getBalance(banker.address);
        const balance = web3.utils.toBN(balanceStr);
        assert.isTrue(balance.eq(bigNum(0)), "The balance of an initialized contract should be zero!");
    });

    it("The balance of the owner on an just initialized contract should be zero.", async () => {
        const banker = await Banker.deployed();
        const balance = web3.utils.toBN(await banker.getBalance.call());
        assert.isTrue(balance.eq(web3.utils.toBN(0)), "The balance of owner should be zero.");
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

    it("The balance of the owner on the contract should be 10 eth.", async () => {
        const banker = await Banker.deployed();
        const balance = web3.utils.toBN(await banker.getBalance.call());
        assert.isTrue(balance.eq(eth1.mul(bigNum(10))), "The balance of owner should be 10 eth.");
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

        // Retrieve owner balance
        const balance = await banker.getBalance.call();

        let winEth;

        const tx = await banker.revealBet(randObj.randNum);
        truffleAssert.eventEmitted(tx, "BetIsRevealed", ev => {
            winEth = ev.winAmount.div(bigNum(100)).mul(eth1);
            return true;
        });

        const currBalance = await banker.getBalance.call();
        const keys = await banker.getPlayerKeysOnCurrGame.call(playerAddr);

        const jackpotEth = await banker.getJackpotBalance.call();

        if (eth1.gt(winEth)) {
            // Player lose this round
            const loseEth = eth1.sub(winEth);

            // Calculate how many eth we earned
            const dividendsEth = loseEth.div(bigNum(38));
            const calcBalance = balance.sub(winEth).sub(dividendsEth);
            assert.isTrue(currBalance.eq(calcBalance), "The balance is added with the money we earned is wrong!");

            assert.isTrue(keys.gt(bigNum(0)), "The keys remain in player wallet should not be zero!");
            assert.isTrue(jackpotEth.gt(bigNum(0)), "Jackpot balance should not be zero!");
        } else {
            assert.isTrue(keys.eq(bigNum(0)), "The keys remain in player wallet should still be zero!");
            assert.isTrue(jackpotEth.eq(bigNum(0)), "Jackpot balance should still be zero!");
        }
    });

    it("Reveal bet again should fail.", async () => {
        const banker = await Banker.deployed();

        await truffleAssert.reverts(banker.revealBet(randObj.randNum), "The bet slot cannot be empty.");
    });

    it("Place a bet that will expire on next block should fail.", async () => {
        const banker = await Banker.deployed();

        const expireOnBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber());
        const randObj = await generateRandomNumberAndSign(28, expireOnBlockNum, bankerAddr);
        const betDataHex = makeRandomBetData();

        await truffleAssert.reverts(
            banker.placeBet(randObj.magicHex, expireOnBlockNum, betDataHex, randObj.signR, randObj.signS, {
                from: playerAddr,
                value: eth1
            }),
            "Invalid number of lastRevealBlock."
        );
    });

    it("Place a bet that will expire after 2 blocks.", async () => {
        const banker = await Banker.deployed();

        expireOnBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber()).add(web3.utils.toBN(2));
        randObj = await generateRandomNumberAndSign(28, expireOnBlockNum, bankerAddr);
        betDataHex = makeRandomBetData();

        await truffleAssert.passes(
            banker.placeBet(randObj.magicHex, expireOnBlockNum, betDataHex, randObj.signR, randObj.signS, {
                from: playerAddr,
                value: eth1
            })
        );
    });

    it("Waiting for previous bet expires.", async () => {
        let currBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber());
        while (currBlockNum.lte(expireOnBlockNum)) {
            await sleep(1000);
            currBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber());
        }
    });

    it("Now reveal previous bet should fail.", async () => {
        const banker = await Banker.deployed();

        await truffleAssert.reverts(banker.revealBet(randObj.randNum), "The bet is timeout.");
    });

    it("Refund eth to player.", async () => {
        const banker = await Banker.deployed();

        const balance = web3.utils.toBN(await web3.eth.getBalance(playerAddr));

        await truffleAssert.passes(banker.refundBet(randObj.magicHex));

        const balanceAfter = web3.utils.toBN(await web3.eth.getBalance(playerAddr));
        assert.isTrue(balanceAfter.sub(balance).eq(eth1), "The amount of return eth is wrong!");
    });

    const bets = [];

    it("Generate 10 bets and place them all.", async () => {
        const banker = await Banker.deployed();

        for (let i = 0; i < 10; ++i) {
            const bet = {};
            bet.expireOnBlockNum = web3.utils.toBN(await web3.eth.getBlockNumber()).add(web3.utils.toBN(100));
            bet.randObj = await generateRandomNumberAndSign(28, bet.expireOnBlockNum, bankerAddr);
            bet.betDataHex = makeRandomBetData();
            bets.push(bet);

            await truffleAssert.passes(
                banker.placeBet(
                    bet.randObj.magicHex,
                    bet.expireOnBlockNum,
                    bet.betDataHex,
                    bet.randObj.signR,
                    bet.randObj.signS,
                    {
                        from: playerAddr,
                        value: eth1
                    }
                )
            );
        }
    });

    it("Reveal them all.", async () => {
        const banker = await Banker.deployed();

        for (let i = 0; i < bets.length; ++i) {
            await truffleAssert.passes(banker.revealBet(bets[i].randObj.randNum));
        }
    });
});
