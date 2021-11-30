const ReservesManager = artifacts.require('ReservesManager');
const ReserveMarketplace = artifacts.require('ReserveMarketplace');
const CollectionMock = artifacts.require('CollectionMock');
const USDTMock = artifacts.require('USDTMock');

const { constants, expectRevert, expectEvent, time } = require('@openzeppelin/test-helpers');

describe.only('ReservesManager', function () {
  let purchasePriceOffer = 1000;

  beforeEach(async () => {
    const { user, bob, alice } = await getNamedAccounts();

    await deployments.fixture(['reserves_manager', 'collection_mock', 'usdt_mock']);
    let deployment = await deployments.get('ReservesManager');

    this.manager = await ReservesManager.at(deployment.address);

    deployment = await deployments.get('ReserveMarketplace');
    this.marketplace = await ReserveMarketplace.at(deployment.address);

    deployment = await deployments.get('CollectionMock');
    this.collection = await CollectionMock.at(deployment.address);

    // mint the token
    await this.collection.safeMint(user);

    deployment = await deployments.get('USDTMock');
    this.usdt = await USDTMock.at(deployment.address);

    // transfer the balance first
    await this.usdt.transfer(user, purchasePriceOffer);

    // create the purchase proposal
    await this.marketplace.approveReserveToBuy(
      this.collection.address,
      0,
      this.usdt.address,
      purchasePriceOffer,
      user,
      1000,
      time.duration.weeks(1),
      time.duration.weeks(1),
      constants.ZERO_ADDRESS,
      {
        from: user,
      }
    );

    // transfer the balances first
    await this.usdt.transfer(bob, purchasePriceOffer);
    await this.collection.transferFrom(user, bob, 0, { from: user });

    // set the allowances
    await this.usdt.approve(this.marketplace.address, purchasePriceOffer, { from: user });
    await this.collection.approve(this.marketplace.address, 0, { from: bob });

    // sale with enough price
    await this.marketplace.approveReserveToSell(
      this.collection.address,
      0,
      this.usdt.address,
      purchasePriceOffer,
      alice,
      1000,
      time.duration.weeks(1),
      time.duration.weeks(1),
      user,
      {
        from: bob,
      }
    );

    this.reserveId = web3.utils.keccak256(
      web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'address', 'address'],
        [this.collection.address, 0, bob, user]
      )
    );
  });

  it('should be deployed', async () => {
    assert.isOk(this.manager.address);
  });

  describe('canceling a reserve', () => {
    it('fails to cancel non active reserve', async () => {
      const { user, bob } = await getNamedAccounts();

      await expectRevert(
        this.manager.cancelReserve(
          web3.utils.keccak256(
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'address', 'address'],
              [this.collection.address, 1, bob, user]
            )
          )
        ),
        'Non-existent active proposal'
      );
    });

    it('fails to cancel expired reserve', async () => {
      // advance the time
      await time.increase(time.duration.weeks(1));

      await expectRevert(this.manager.cancelReserve(this.reserveId), 'Reserve expired. Pay or liquidate');
    });

    it('fails to cancel from invalid account', async () => {
      await expectRevert(this.manager.cancelReserve(this.reserveId), 'Invalid caller. Should be buyer or seller');
    });

    it('fails to cancel without enough allowance', async () => {
      const { user, bob } = await getNamedAccounts();

      // buyer
      await expectRevert(
        this.manager.cancelReserve(this.reserveId, { from: user }),
        'ERC20: transfer amount exceeds allowance'
      );

      // seller
      await expectRevert(
        this.manager.cancelReserve(this.reserveId, { from: bob }),
        'ERC20: transfer amount exceeds allowance'
      );
    });

    it('should allow to cancel from buyer', async () => {
      const { deployer, user, bob } = await getNamedAccounts();

      // compute cancel fee
      let cancelFee = (purchasePriceOffer * 5) / 100;

      // get and approve the funds for the fee
      this.usdt.transfer(user, cancelFee, { from: deployer });
      this.usdt.approve(this.manager.address, cancelFee, { from: user });

      let tx = await this.manager.cancelReserve(this.reserveId, { from: user });

      expectEvent(tx, 'ReserveCanceled', {
        collection: this.collection.address,
        tokenId: '0',
        paymentToken: this.usdt.address,
        price: String(purchasePriceOffer),
        collateralPercent: '1000',
        seller: bob,
        buyer: user,
        executor: user,
      });
    });

    it('should allow to cancel from seller', async () => {
      const { deployer, user, bob } = await getNamedAccounts();

      // compute cancel fee
      let cancelFee = (purchasePriceOffer * 5) / 100;

      // get and approve the funds for the fee
      this.usdt.transfer(bob, cancelFee, { from: deployer });
      this.usdt.approve(this.manager.address, cancelFee, { from: bob });

      let tx = await this.manager.cancelReserve(this.reserveId, { from: bob });

      expectEvent(tx, 'ReserveCanceled', {
        collection: this.collection.address,
        tokenId: '0',
        paymentToken: this.usdt.address,
        price: String(purchasePriceOffer),
        collateralPercent: '1000',
        seller: bob,
        buyer: user,
        executor: bob,
      });
    });
  });

  describe('liquidate a reserve', () => {
    it('fails to liquidate a non active reserve', async () => {
      const { user, bob } = await getNamedAccounts();

      await expectRevert(
        this.manager.liquidateReserve(
          web3.utils.keccak256(
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'address', 'address'],
              [this.collection.address, 1, bob, user]
            )
          )
        ),
        'Non-existent active proposal'
      );
    });

    it('fails to liquidate not expired reserve from buyer', async () => {
      const { user } = await getNamedAccounts();

      await expectRevert(
        this.manager.liquidateReserve(this.reserveId, { from: user }),
        'Reserve period not finished yet'
      );
    });

    it('fails to liquidate not expired reserve from seller', async () => {
      const { bob } = await getNamedAccounts();

      await expectRevert(
        this.manager.liquidateReserve(this.reserveId, { from: bob }),
        'Buyer period to pay not finished yet'
      );
    });

    it('fails to purchase from invalid account', async () => {
      await expectRevert(this.manager.liquidateReserve(this.reserveId), 'Invalid caller. Should be buyer or seller');
    });

    it('should allow to liquidate a non paid reserve', async () => {
      const { user, bob } = await getNamedAccounts();

      // advance the time
      await time.increase(time.duration.weeks(2));

      // compute collateral
      const { collateral } = await this.manager.reserveAmounts(this.reserveId);

      let tx = await this.manager.liquidateReserve(this.reserveId, { from: user });

      expectEvent(tx, 'PurchaseCanceled', {
        collection: this.collection.address,
        tokenId: '0',
        paymentToken: this.usdt.address,
        collateralToken: this.usdt.address,
        price: String(purchasePriceOffer),
        collateralPercent: '1000',
        seller: bob,
        buyer: user,
      });

      await expectEvent.inTransaction(tx.tx, this.usdt, 'Transfer', {
        from: this.manager.address,
        to: bob,
        value: collateral,
      });

      await expectEvent.inTransaction(tx.tx, this.collection, 'Transfer', {
        from: this.manager.address,
        to: bob,
        tokenId: '0',
      });
    });

    describe('pay the price and paid liquidation', () => {
      describe('payThePrice method', () => {
        it('fails to pay from non buyer', async () => {
          await expectRevert(this.manager.payThePrice(this.reserveId), 'Only proposal buyer allowed');
        });

        it('fails to pay after valid period', async () => {
          const { user } = await getNamedAccounts();

          // advance the time
          await time.increase(time.duration.weeks(2));

          await expectRevert(this.manager.payThePrice(this.reserveId, { from: user }), 'Period to pay finished');
        });

        it('allows to pay the price', async () => {
          const { deployer, bob, user } = await getNamedAccounts();

          // approve funds
          await this.usdt.transfer(user, 1000, { from: deployer });
          await this.usdt.approve(this.manager.address, 1000, { from: user });

          let tx = await this.manager.payThePrice(this.reserveId, { from: user });

          expectEvent(tx, 'ReservePricePaid', {
            collection: this.collection.address,
            tokenId: '0',
            paymentToken: this.usdt.address,
            collateralToken: this.usdt.address,
            price: String(purchasePriceOffer),
            collateralPercent: '1000',
            seller: bob,
            buyer: user,
          });

          // validate double payment attempt
          await expectRevert(this.manager.payThePrice(this.reserveId, { from: user }), 'Already paid');
        });
      });

      it('allows to liquidate paid reserve', async () => {
        const { deployer, user, bob } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        await this.manager.payThePrice(this.reserveId, { from: user });

        // advance the time
        await time.increase(time.duration.weeks(2));

        // compute collateral
        const { collateral, payment } = await this.manager.reserveAmounts(this.reserveId);

        let tx = await this.manager.liquidateReserve(this.reserveId, { from: bob });

        expectEvent(tx, 'PurchaseExecuted', {
          collection: this.collection.address,
          tokenId: '0',
          paymentToken: this.usdt.address,
          collateralToken: this.usdt.address,
          price: String(purchasePriceOffer),
          collateralPercent: '1000',
          seller: bob,
          buyer: user,
        });

        await expectEvent.inTransaction(tx.tx, this.usdt, 'Transfer', {
          from: this.manager.address,
          to: bob,
          value: payment,
        });

        await expectEvent.inTransaction(tx.tx, this.usdt, 'Transfer', {
          from: this.manager.address,
          to: user,
          value: collateral,
        });

        await expectEvent.inTransaction(tx.tx, this.collection, 'Transfer', {
          from: this.manager.address,
          to: user,
          tokenId: '0',
        });
      });
    });
  });

  describe('increasing and decreasing collateral', () => {
    describe('increaseReserveCollateral method', () => {
      it('fails for non existent reserve', async () => {
        const { bob, user } = await getNamedAccounts();

        await expectRevert(
          this.manager.increaseReserveCollateral(
            web3.utils.keccak256(
              web3.eth.abi.encodeParameters(
                ['address', 'uint256', 'address', 'address'],
                [this.collection.address, 1, bob, user]
              )
            ),
            1000
          ),
          'Non-existent active reserve'
        );
      });

      it('fails from non buyer account', async () => {
        await expectRevert(this.manager.increaseReserveCollateral(this.reserveId, 1000), 'Only buyer allowed');
      });

      it('fails if reserve was already paid', async () => {
        const { deployer, user } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        await this.manager.payThePrice(this.reserveId, { from: user });

        await expectRevert(
          this.manager.increaseReserveCollateral(this.reserveId, 1000, { from: user }),
          'Price already paid'
        );
      });

      it('allows to increase collateral', async () => {
        const { deployer, user } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        let tx = await this.manager.increaseReserveCollateral(this.reserveId, 1000, { from: user });

        expectEvent(tx, 'CollateralIncreased', {
          reserveId: this.reserveId,
          amount: '1000',
        });
      });
    });

    describe('decreaseReserveCollateral method', () => {
      it('fails for non existent reserve', async () => {
        const { bob, user } = await getNamedAccounts();

        await expectRevert(
          this.manager.decreaseReserveCollateral(
            web3.utils.keccak256(
              web3.eth.abi.encodeParameters(
                ['address', 'uint256', 'address', 'address'],
                [this.collection.address, 1, bob, user]
              )
            ),
            1000
          ),
          'Non-existent active reserve'
        );
      });

      it('fails from non buyer account', async () => {
        await expectRevert(this.manager.decreaseReserveCollateral(this.reserveId, 1000), 'Only buyer allowed');
      });

      it('fails if paid but amount is to much', async () => {
        const { deployer, user } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        await this.manager.payThePrice(this.reserveId, { from: user });

        await expectRevert(
          this.manager.decreaseReserveCollateral(this.reserveId, 10000, { from: user }),
          'Insufficient amount for request'
        );
      });

      it('succeed if reserve was already paid', async () => {
        const { deployer, user } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        await this.manager.payThePrice(this.reserveId, { from: user });

        let tx = await this.manager.decreaseReserveCollateral(this.reserveId, 100, { from: user });

        expectEvent(tx, 'CollateralDecreased', {
          reserveId: this.reserveId,
          amount: '100',
        });
      });

      it('fails in undercollateralization attempt', async () => {
        const { user } = await getNamedAccounts();

        await expectRevert(
          this.manager.decreaseReserveCollateral(this.reserveId, 100, { from: user }),
          'Attemp to uncollateralize reserve'
        );
      });

      it('succeed even if is not paid yet', async () => {
        const { deployer, user } = await getNamedAccounts();

        // approve funds
        await this.usdt.transfer(user, 1000, { from: deployer });
        await this.usdt.approve(this.manager.address, 1000, { from: user });

        await this.manager.increaseReserveCollateral(this.reserveId, 1000, { from: user });

        let tx = await this.manager.decreaseReserveCollateral(this.reserveId, 100, { from: user });

        expectEvent(tx, 'CollateralDecreased', {
          reserveId: this.reserveId,
          amount: '100',
        });
      });
    });
  });

  it('validates onlyMarketplace modifier', async () => {
    const { bob, user } = await getNamedAccounts();

    await expectRevert(
      this.manager.startReserve(
        this.collection.address,
        0,
        this.usdt.address,
        String(purchasePriceOffer),
        1000,
        1000,
        bob,
        user
      ),
      'Only callable from the marketplace'
    );
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
