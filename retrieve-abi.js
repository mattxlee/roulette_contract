const fs = require("fs");
const Banker = require("./build/contracts/Banker.json");

const { abi } = Banker;

const abiStr = JSON.stringify(abi);
fs.writeFile("./BankerABI.json", abiStr, err => {
    if (err) {
        console.err(err);
        return;
    }
    console.log("ABI has been written.");
});
