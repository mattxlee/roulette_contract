# Contract source files of Etheroulette Game

Here contains the test cases and contract source file. Truffle project is required for testing and deploying. Recommend to use ganache command line version to simulate the ethereum block chain.


## Requirements

* NPM installed

* Truffle

* Ganache

* Solidity compiler (solc is recommended)

## Installation

Follow the instruction below


* Execute command to install required packages

```
npm i -g solc truffle ganache-cli
```

* Clone the repository

* Run `npm i` under the repository directory

## Run test

* Start ganache command line version

```
ganache-cli --port=7545 -a 20 -b 1 -e 1000
```

* Run `truffle test` to execute test cases

