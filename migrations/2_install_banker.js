var Banker = artifacts.require("./Banker.sol");

module.exports = function(deployer) {
  deployer.deploy(Banker);
};
