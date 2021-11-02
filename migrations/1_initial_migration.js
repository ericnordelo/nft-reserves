const NFTReservalManager = artifacts.require("NFTReservalManager");

module.exports = function (deployer) {
  deployer.deploy(NFTReservalManager);
};
