const fs = require("fs");
const Banker = require("./build/contracts/Banker.json");

const addrJson = [];

const { networks } = Banker;
if (networks) {
    Object.keys(networks).forEach(key => {
        const { address } = networks[key];
        const obj = { network: key, address };
        addrJson.push(obj);
    });
    const addrStr = JSON.stringify(addrJson);
    fs.writeFile("./build/Addresses.json", addrStr, err => {
        if (err) {
            console.err(err);
            return;
        }
        console.log("Addresses have been written.");
    });
} else {
    console.err("Cannot find entry `networks` from build/contracts/Banker.json");
}
