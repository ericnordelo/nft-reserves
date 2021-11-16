const NFTVault = artifacts.require('NFTVault');

const { constants, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

describe('NFTVault', function () {
  beforeEach(async () => {
    await deployments.fixture(['nft_vault']);
    let deployment = await deployments.get('NFTVault');

    this.vault = await NFTVault.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.vault.address);
  });

  describe('upgrade', () => {
    it("can't upgrade with wrong accounts", async () => {
      const { user } = await getNamedAccounts();

      let revertMessage = 'Ownable: caller is not the owner';
      await expectRevert(this.vault.upgradeTo(constants.ZERO_ADDRESS, { from: user }), revertMessage);
    });

    it('can upgrade with right account', async () => {
      const { deployer } = await getNamedAccounts();

      let newImplementation = await NFTVault.new();

      let tx = await this.vault.upgradeTo(newImplementation.address, { from: deployer });

      expectEvent(tx, 'Upgraded', { implementation: newImplementation.address });
    });
  });
});
