var Banker = artifacts.require("./Banker.sol");
var Rou = artifacts.require('./Rou.sol');
var SafeMath = artifacts.require('./SafeMath.sol');

module.exports = function(deployer) {
  deployer.deploy(Rou);
  deployer.deploy(SafeMath);

  deployer.link(Rou, Banker);
  deployer.link(SafeMath, Banker);

  deployer.deploy(Banker);
};
