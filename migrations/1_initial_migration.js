const NFTReservalManager = artifacts.require("NFTReservalManager");

module.exports = function (deployer) {
  deployer.deploy(NFTReservalManager,
    "0xad6d458402f60fd3b111111111131acdce07538d"
  );
};
