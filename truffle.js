/*
 * NB: since truffle-hdwallet-provider 0.0.5 you must wrap HDWallet providers in a
 * function when declaring them. Failure to do so will cause commands to hang. ex:
 * ```
 * mainnet: {
 *     provider: function() {
 *       return new HDWalletProvider(mnemonic, 'https://mainnet.infura.io/<infura-key>')
 *     },
 *     network_id: '1',
 *     gas: 4500000,
 *     gasPrice: 10000000000,
 *   },
 */

const HDWalletProvider = require("truffle-hdwallet-provider");

const fs = require("fs");
const mnemonic = fs.readFileSync(".mnemonic");

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    ganache: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*"
    },
    rinkeby: {
        provider: () => {
            return new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/v3/daad1c45f9b6487288f56ff2bac9577a");
        },
        network_id: "*"
    },
    ropsten: {
        provider: () => {
            return new HDWalletProvider(mnemonic, "https://ropsten.infura.io/v3/daad1c45f9b6487288f56ff2bac9577a");
        },
        network_id: "*"
    },
    kovan: {
        provider: () => {
            return new HDWalletProvider(mnemonic, "https://kovan.infura.io/v3/daad1c45f9b6487288f56ff2bac9577a");
        },
        network_id: "*"
    },
    goerli: {
        provider: () => {
            return new HDWalletProvider(mnemonic, "https://goerli.infura.io/v3/daad1c45f9b6487288f56ff2bac9577a");
        },
        network_id: "*"
    }
  }
};
