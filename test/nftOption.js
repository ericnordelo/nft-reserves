const NFTReservalManager = artifacts.require('NFTReservalManager')

const ADDRESS_USDT = "0x110a13fc3efe6a245b50102d2d79b3e76125ae83";
const ADDRESS_COMP = "0xf76d4a441e4ba86a923ce32b89aff89dbccaa075";
const ADDRESS_USDC = "0x07865c6e87b9f70255377e024ace6630c1eaa37f";
const ADDRESS_DAI = "0xad6d458402f60fd3bd25163575031acdce07538d";

contract('NFT Option test', async(accounts) => {
    it('test', async() => {
        const optionManager = await NFTReservalManager.deployed();
    })
})