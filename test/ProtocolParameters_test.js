const ProtocolParameters = artifacts.require('ProtocolParameters');
const UUPSProxy = artifacts.require('UUPSProxy');

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

  describe('Initializer branches (validations)', () => {
    it('validates', async () => {
      let deployment = await deployments.get('ProtocolParameters_Implementation');
      let proxy = await UUPSProxy.new(deployment.address, constants.ZERO_ADDRESS, []);
      let newProtocol = await ProtocolParameters.at(proxy.address);
      let governance = constants.ZERO_ADDRESS;

      let defaultProtocolParameters = {
        minimumReservePeriod: String(time.duration.minutes(0)),
        sellerCancelFeePercent: '101',
        buyerCancelFeePercent: '101',
        buyerPurchaseGracePeriod: String(time.duration.minutes(0)),
      };

      await expectRevert(
        newProtocol.initialize(...Object.values(defaultProtocolParameters), governance),
        'Invalid minimum reserve period'
      );

      defaultProtocolParameters.minimumReservePeriod = String(time.duration.weeks(1));

      await expectRevert(
        newProtocol.initialize(...Object.values(defaultProtocolParameters), governance),
        'Invalid seller cancel fee percent'
      );

      defaultProtocolParameters.sellerCancelFeePercent = '5';

      await expectRevert(
        newProtocol.initialize(...Object.values(defaultProtocolParameters), governance),
        'Invalid buyer cancel fee percent'
      );

      defaultProtocolParameters.buyerCancelFeePercent = '5';
    });
  });

  describe('default parameters', () => {
    it('has correct default minimumReservePeriod', async () => {
      let minimumReservePeriod = await this.protocol.minimumReservePeriod();

      assert.strictEqual(String(minimumReservePeriod), String(time.duration.minutes(5)));
    });

    it('has correct default sellerCancelFeePercent', async () => {
      let sellerCancelFeePercent = await this.protocol.sellerCancelFeePercent();

      assert.strictEqual(String(sellerCancelFeePercent), '5');
    });

    it('has correct default buyerCancelFeePercent', async () => {
      let buyerCancelFeePercent = await this.protocol.buyerCancelFeePercent();

      assert.strictEqual(String(buyerCancelFeePercent), '5');
    });

    it('has correct default buyerPurchaseGracePeriod', async () => {
      let buyerPurchaseGracePeriod = await this.protocol.buyerPurchaseGracePeriod();

      assert.strictEqual(String(buyerPurchaseGracePeriod), String(time.duration.minutes(15)));
    });
  });

  describe('setters', () => {
    it('minimumReservePeriod', async () => {
      // check the validations
      await expectRevert(this.protocol.setMinimumReservePeriod(0), 'Invalid minimum reserve period');

      // check the updates
      expectEvent(
        await this.protocol.setMinimumReservePeriod(time.duration.minutes(50)),
        'MinimumReservePeriodUpdated',
        { from: time.duration.minutes(5), to: time.duration.minutes(50) }
      );

      let minimumReservePeriod = await this.protocol.minimumReservePeriod();

      assert.strictEqual(String(minimumReservePeriod), String(time.duration.minutes(50)));
    });

    it('sellerCancelFeePercent', async () => {
      // check the validations
      await expectRevert(this.protocol.setSellerCancelFeePercent(101), 'Invalid seller cancel fee percent');

      // check the updates
      expectEvent(await this.protocol.setSellerCancelFeePercent(10), 'SellerCancelFeePercentUpdated', {
        from: '5',
        to: '10',
      });

      let sellerCancelFeePercent = await this.protocol.sellerCancelFeePercent();

      assert.strictEqual(String(sellerCancelFeePercent), '10');
    });

    it('buyerCancelFeePercent', async () => {
      // check the validations
      await expectRevert(this.protocol.setBuyerCancelFeePercent(101), 'Invalid buyer cancel fee percent');

      // check the updates
      expectEvent(await this.protocol.setBuyerCancelFeePercent(10), 'BuyerCancelFeePercentUpdated', {
        from: '5',
        to: '10',
      });

      let buyerCancelFeePercent = await this.protocol.buyerCancelFeePercent();

      assert.strictEqual(String(buyerCancelFeePercent), '10');
    });

    it('buyerPurchaseGracePeriod', async () => {
      // check the updates
      expectEvent(
        await this.protocol.setBuyerPurchaseGracePeriod(time.duration.minutes(50)),
        'BuyerPurchaseGracePeriodUpdated',
        { from: time.duration.minutes(15), to: time.duration.minutes(50) }
      );

      let buyerPurchaseGracePeriod = await this.protocol.buyerPurchaseGracePeriod();

      assert.strictEqual(String(buyerPurchaseGracePeriod), String(time.duration.minutes(50)));
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
