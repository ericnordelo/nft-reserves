const ReserveMarketplace = artifacts.require('ReserveMarketplace');

const { constants, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

describe('ReserveMarketplace', function () {
  beforeEach(async () => {
    await deployments.fixture(['reserve_marketplace']);
    let deployment = await deployments.get('ReserveMarketplace');

    this.marketplace = await ReserveMarketplace.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.marketplace.address);
  });

  describe('upgrade', () => {
    it("can't upgrade with wrong accounts", async () => {
      const { user } = await getNamedAccounts();

      let revertMessage = 'Ownable: caller is not the owner';
      await expectRevert(this.marketplace.upgradeTo(constants.ZERO_ADDRESS, { from: user }), revertMessage);
    });

    it('can upgrade with right account', async () => {
      const { deployer } = await getNamedAccounts();

      let newImplementation = await ReserveMarketplace.new(constants.ZERO_ADDRESS);

      let tx = await this.marketplace.upgradeTo(newImplementation.address, { from: deployer });

      expectEvent(tx, 'Upgraded', { implementation: newImplementation.address });
    });
  });
});
