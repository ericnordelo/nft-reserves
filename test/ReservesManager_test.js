const ReservesManager = artifacts.require('ReservesManager');

const { constants, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

describe('ReservesManager', function () {
  beforeEach(async () => {
    await deployments.fixture(['reserves_manager']);
    let deployment = await deployments.get('ReservesManager');

    this.manager = await ReservesManager.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.manager.address);
  });

  describe('upgrade', () => {
    it("can't upgrade with wrong accounts", async () => {
      const { user } = await getNamedAccounts();

      let revertMessage = 'Ownable: caller is not the owner';
      await expectRevert(this.manager.upgradeTo(constants.ZERO_ADDRESS, { from: user }), revertMessage);
    });

    it('can upgrade with right account', async () => {
      const { deployer } = await getNamedAccounts();

      let newImplementation = await ReservesManager.new(constants.ZERO_ADDRESS, constants.ZERO_ADDRESS);

      let tx = await this.manager.upgradeTo(newImplementation.address, { from: deployer });

      expectEvent(tx, 'Upgraded', { implementation: newImplementation.address });
    });
  });
});
