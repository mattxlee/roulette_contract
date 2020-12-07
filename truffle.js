const HDWalletProvider = require("@truffle/hdwallet-provider");

const fs = require("fs");
const mnemonicPhrase = fs.readFileSync(".mnemonic").toString().trim();

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    test: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*"
    },
    testnet: {
        provider: new HDWalletProvider({mnemonic: { phrase: mnemonicPhrase }, providerOrUrl: "https://ropsten.infura.io/v3/daad1c45f9b6487288f56ff2bac9577a"}),
        network_id: "*"
    }
  }
};
