# Contract source files of Etheroulette Game

Here contains the test cases and contract source file. Truffle project is required for testing and deploying. Recommend
to use ganache command line version to simulate the ethereum block chain.

## Live

The game now is deployed on **ROPSTEN** at address
[0x2A6DFc26999c389Ae7fa22D5C9F3bD82c67DD8AE](https://ropsten.etherscan.io/address/0x2A6DFc26999c389Ae7fa22D5C9F3bD82c67DD8AE).
You can visit [Etheroulette.com](https://etheroulette.com) to play the game.

## Requirements

* NPM installed

* Truffle

* Ganache

* Solidity compiler (solc is recommended)

## Installation

Follow the instructions below

* Execute command to install required packages

```
npm i -g truffle ganache-cli
```

* Clone the repository

* Run `npm i` under the repository directory

## Build contract

We are using Truffle to compile and deploy the contract. So please make sure that the truffle and ganache-cli are all
installed on your system.

To compile the contract, you just use `truffle build`. However, there is a script available named `build.sh` to build
the contract for your convinence. This script also will retrieve the ABI information from Banker.json and the ABI will
be written into build/BankerABI.json file. Copy the ABI json file to other projects to update the contract ABI
information.

## Start Ganache cli

Before the procedures of deploying and testing, you must ensure that the network is available. Make sure Ganache cli is
installed and execute the following instruction.

```
ganache-cli --port=7545 -a 20 -b 1 -e 1000 -i 1
```

## Deploy contract

Like the build procedure, we also provide a script named `deploy.sh` to help the deploying procedure. You need to
provide the network name and the script will deploy the contract to the related network.

For example, you just run `./deploy.sh development`, the script will deploy the compiled ABI information to the network
which is specified in file `truffle.js`. Before the deploying, you need to ensure that the network is available or the
deploying procedure will be failed.

## Run test

* Run `truffle test` to execute test cases

