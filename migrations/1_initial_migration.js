const NFTReservalManager = artifacts.require("NFTReservalManager");

module.exports = function (deployer) {
  deployer.deploy(NFTReservalManager,
  [
    "0x110a13fc3efe6a245b50102d2d79b3e76125ae83",
    "0xf76d4a441e4ba86a923ce32b89aff89dbccaa075",
    "0x07865c6e87b9f70255377e024ace6630c1eaa37f",
    "0xad6d458402f60fd3bd25163575031acdce07538d"
  ],
    "0xad6d458402f60fd3b000000000031acdce07538d",
    "0xad6d458402f60fd3b111111111131acdce07538d"
  );
};
