const ProtocolParameters = artifacts.require('ProtocolParameters');

const { constants, expectRevert, expectEvent, time } = require('@openzeppelin/test-helpers');

describe('ProtocolParameters', function () {
  beforeEach(async () => {
    await deployments.fixture(['protocol_parameters']);
    let deployment = await deployments.get('ProtocolParameters');

    this.protocol = await ProtocolParameters.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.protocol.address);
  });

  describe('default parameters', () => {
    it('has correct default minimumReservePeriod', async () => {
      let minimumReservePeriod = await this.protocol.minimumReservePeriod();

      assert.strictEqual(String(minimumReservePeriod), String(time.duration.minutes(5)));
    });
  });

  describe('upgrade', () => {
    it("can't upgrade with wrong accounts", async () => {
      const { user } = await getNamedAccounts();

      let revertMessage = 'Ownable: caller is not the owner';
      await expectRevert(this.protocol.upgradeTo(constants.ZERO_ADDRESS, { from: user }), revertMessage);
    });

    it('can upgrade with right account', async () => {
      const { deployer } = await getNamedAccounts();

      let newImplementation = await ProtocolParameters.new();

      let tx = await this.protocol.upgradeTo(newImplementation.address, { from: deployer });

      expectEvent(tx, 'Upgraded', { implementation: newImplementation.address });
    });
  });
});
