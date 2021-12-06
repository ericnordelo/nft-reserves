const ReserveMarketplace = artifacts.require('ReserveMarketplace');
const CollectionMock = artifacts.require('CollectionMock');
const USDTMock = artifacts.require('USDTMock');

const { constants, expectRevert, expectEvent, time } = require('@openzeppelin/test-helpers');

describe('ReserveMarketplace', function () {
  beforeEach(async () => {
    await deployments.fixture(['reserves_manager', 'collection_mock', 'usdt_mock']);
    let deployment = await deployments.get('ReserveMarketplace');
    this.marketplace = await ReserveMarketplace.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.marketplace.address);
  });

  describe('approveReserveToSell method', () => {
    beforeEach(async () => {
      const { user } = await getNamedAccounts();

      let deployment = await deployments.get('CollectionMock');
      this.collection = await CollectionMock.at(deployment.address);

      // mint the token
      await this.collection.safeMint(user);
    });

    describe('using the payment token', () => {
      beforeEach(async () => {
        let deployment = await deployments.get('USDTMock');
        this.usdt = await USDTMock.at(deployment.address);
      });

      it('emits SaleReserveProposed if match not found', async () => {
        const { user } = await getNamedAccounts();

        let tx = await this.marketplace.approveReserveToSell(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          user,
          1000, // ten percent
          time.duration.weeks(1),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          {
            from: user,
          }
        );

        expectEvent(tx, 'SaleReserveProposed', {
          collection: this.collection.address,
          tokenId: '0',
          paymentToken: this.usdt.address,
          collateralToken: this.usdt.address,
          price: '1000',
          collateralPercent: '1000',
          reservePeriod: time.duration.weeks(1),
        });
      });

      it('getter returns the right params after SaleReserveProposed', async () => {
        const { user } = await getNamedAccounts();

        // create the proposal
        await this.marketplace.approveReserveToSell(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          user,
          1000,
          time.duration.weeks(1),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          {
            from: user,
          }
        );

        // use the getter to consult
        const { proposal, id } = await this.marketplace.getSaleReserveProposal(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          1000,
          time.duration.weeks(1),
          user
        );

        let expectedId = web3.utils.keccak256(
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'address', 'address', 'uint256', 'uint80', 'uint64', 'address'],
            [this.collection.address, 0, this.usdt.address, this.usdt.address, 1000, 1000, time.duration.weeks(1), user]
          )
        );

        assert.strictEqual(id, expectedId, 'Invalid hash id');
        assert.strictEqual(proposal.collection, this.collection.address, 'Invalid proposal collection');
        assert.strictEqual(proposal.tokenId, '0', 'Invalid proposal token id');
        assert.strictEqual(proposal.paymentToken, this.usdt.address, 'Invalid proposal payment token');
        assert.strictEqual(proposal.collateralToken, this.usdt.address, 'Invalid proposal collateral token');
        assert.strictEqual(proposal.price, '1000', 'Invalid proposal price');
        assert.strictEqual(proposal.owner, user, 'Invalid proposal owner');
        assert.strictEqual(proposal.beneficiary, user, 'Invalid proposal beneficiary');
      });

      it('getter reverts for non-existent proposal', async () => {
        // use the getter to consult
        await expectRevert(
          this.marketplace.getSaleReserveProposal(
            this.collection.address,
            0,
            this.usdt.address,
            this.usdt.address,
            1000,
            1000,
            time.duration.weeks(1),
            this.usdt.address
          ),
          'Non-existent proposal'
        );
      });

      describe('test match found', () => {
        let purchasePriceOffer = 1000;

        beforeEach(async () => {
          const { user } = await getNamedAccounts();

          // transfer the balance first
          await this.usdt.transfer(user, purchasePriceOffer);

          // create the purchase proposal
          await this.marketplace.approveReserveToBuy(
            this.collection.address,
            0,
            this.usdt.address,
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
        });

        describe('tryToSellReserve method', () => {
          it('emits SaleReserved if match found and allowance is enough for collateral', async () => {
            const { user, bob, alice } = await getNamedAccounts();

            // transfer the balances first
            await this.usdt.transfer(bob, purchasePriceOffer);
            await this.collection.transferFrom(user, bob, 0, { from: user });

            // set the allowances
            await this.usdt.approve(this.marketplace.address, purchasePriceOffer, { from: user });
            await this.collection.approve(this.marketplace.address, 0, { from: bob });

            // sale with enough price
            let tx = await this.marketplace.approveReserveToSell(
              this.collection.address,
              0,
              this.usdt.address,
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

            let manager = await this.marketplace.reservesManagerAddress();

            // manager should have received the collateral
            assert.strictEqual(
              (await this.usdt.balanceOf(manager)).toNumber(),
              (purchasePriceOffer * 10) / 100,
              'Invalid locked balance in marketplace'
            );

            // manager should have received the nft
            assert.strictEqual(await this.collection.ownerOf(0), manager, 'Invalid locked nft in marketplace');

            expectEvent.notEmitted(tx, 'SaleReserveProposed');
            expectEvent(tx, 'SaleReserved', {
              collection: this.collection.address,
              tokenId: '0',
              paymentToken: this.usdt.address,
              collateralToken: this.usdt.address,
              price: String(purchasePriceOffer),
              collateralPercent: '1000',
              reservePeriod: time.duration.weeks(1),
            });
          });

          it('emits SaleReserveProposed if match found and not enough allowance for collateral', async () => {
            const { user } = await getNamedAccounts();

            // sale with enough price
            let tx = await this.marketplace.approveReserveToSell(
              this.collection.address,
              0,
              this.usdt.address,
              this.usdt.address,
              purchasePriceOffer,
              user,
              1000,
              time.duration.weeks(1),
              time.duration.weeks(1),
              user,
              {
                from: user,
              }
            );

            expectEvent(tx, 'SaleReserveProposed', {
              collection: this.collection.address,
              tokenId: '0',
              paymentToken: this.usdt.address,
              collateralToken: this.usdt.address,
              price: String(purchasePriceOffer),
              collateralPercent: '1000',
              reservePeriod: time.duration.weeks(1),
            });
          });

          it('return false if expirationTimesamp is passed', async () => {
            const { user, bob, alice } = await getNamedAccounts();

            // transfer the balances first
            await this.usdt.transfer(bob, purchasePriceOffer);
            await this.collection.transferFrom(user, bob, 0, { from: user });

            // set the allowances
            await this.usdt.approve(this.marketplace.address, purchasePriceOffer, { from: user });
            await this.collection.approve(this.marketplace.address, 0, { from: bob });

            await time.increase(time.duration.weeks(2));

            // sale after expiration time
            await this.marketplace.approveReserveToSell(
              this.collection.address,
              0,
              this.usdt.address,
              this.usdt.address,
              purchasePriceOffer,
              alice,
              1000,
              time.duration.weeks(1),
              0,
              user,
              {
                from: bob,
              }
            );
          });
        });
      });
    });

    it("should't allow to approve with reserve period under governance minimum", async () => {
      const { user } = await getNamedAccounts();

      await expectRevert(
        this.marketplace.approveReserveToSell(
          this.collection.address,
          0,
          constants.ZERO_ADDRESS,
          constants.ZERO_ADDRESS,
          100,
          constants.ZERO_ADDRESS,
          1000,
          time.duration.seconds(5),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          { from: user }
        ),
        'Reserve period must be greater'
      );
    });

    it("should't allow to approve with invalid collateral percent", async () => {
      const { user } = await getNamedAccounts();

      await expectRevert(
        this.marketplace.approveReserveToSell(
          this.collection.address,
          0,
          constants.ZERO_ADDRESS,
          constants.ZERO_ADDRESS,
          100,
          constants.ZERO_ADDRESS,
          10000,
          time.duration.weeks(5),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          { from: user }
        ),
        'Invalid collateral percent'
      );
    });

    it("should't allow to approve sale without ownership", async () => {
      await expectRevert(
        this.marketplace.approveReserveToSell(
          this.collection.address,
          0,
          constants.ZERO_ADDRESS,
          constants.ZERO_ADDRESS,
          100,
          constants.ZERO_ADDRESS,
          1000,
          time.duration.days(5),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS
        ),
        'Only owner can approve'
      );
    });

    it("should't allow to approve sale from unexisting token", async () => {
      await expectRevert(
        this.marketplace.approveReserveToSell(
          this.collection.address,
          1,
          constants.ZERO_ADDRESS,
          constants.ZERO_ADDRESS,
          100,
          constants.ZERO_ADDRESS,
          1000,
          time.duration.days(5),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS
        ),
        'ERC721: owner query for nonexistent token'
      );
    });
  });

  describe('approveReserveToBuy method', () => {
    beforeEach(async () => {
      const { user } = await getNamedAccounts();

      let deployment = await deployments.get('CollectionMock');
      this.collection = await CollectionMock.at(deployment.address);

      // mint the token
      await this.collection.safeMint(user);
    });

    describe('using the payment token', () => {
      beforeEach(async () => {
        let deployment = await deployments.get('USDTMock');
        this.usdt = await USDTMock.at(deployment.address);
      });

      it("should't allow to approve purchase without enough balance", async () => {
        const { user } = await getNamedAccounts();

        await expectRevert(
          this.marketplace.approveReserveToBuy(
            this.collection.address,
            1,
            this.usdt.address,
            this.usdt.address,
            100,
            constants.ZERO_ADDRESS,
            1000,
            time.duration.weeks(1),
            time.duration.weeks(1),
            constants.ZERO_ADDRESS,
            { from: user }
          ),
          'Not enough balance to pay for collateral'
        );
      });

      it('emits PurchaseReserveProposed if match not found', async () => {
        const { user } = await getNamedAccounts();

        // transfer the balance first
        await this.usdt.transfer(user, 100);

        let tx = await this.marketplace.approveReserveToBuy(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          user,
          1000,
          time.duration.weeks(1),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          {
            from: user,
          }
        );

        expectEvent(tx, 'PurchaseReserveProposed', {
          collection: this.collection.address,
          tokenId: '0',
          paymentToken: this.usdt.address,
          collateralToken: this.usdt.address,
          price: '1000',
          collateralPercent: '1000',
          reservePeriod: time.duration.weeks(1),
        });
      });

      it('getter returns the right params after PurchaseReserveProposed', async () => {
        const { user } = await getNamedAccounts();

        // transfer the balance first
        await this.usdt.transfer(user, 100);

        // create the proposal
        await this.marketplace.approveReserveToBuy(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          user,
          1000,
          time.duration.weeks(1),
          time.duration.weeks(1),
          constants.ZERO_ADDRESS,
          {
            from: user,
          }
        );

        // use the getter to consult
        const { proposal, id } = await this.marketplace.getPurchaseReserveProposal(
          this.collection.address,
          0,
          this.usdt.address,
          this.usdt.address,
          1000,
          1000,
          time.duration.weeks(1),
          user
        );

        let expectedId = web3.utils.keccak256(
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'address', 'address', 'uint256', 'uint80', 'uint64', 'address'],
            [this.collection.address, 0, this.usdt.address, this.usdt.address, 1000, 1000, time.duration.weeks(1), user]
          )
        );

        assert.strictEqual(id, expectedId, 'Invalid hash id');
        assert.strictEqual(proposal.collection, this.collection.address, 'Invalid proposal collection');
        assert.strictEqual(proposal.tokenId, '0', 'Invalid proposal token id');
        assert.strictEqual(proposal.paymentToken, this.usdt.address, 'Invalid proposal payment token');
        assert.strictEqual(proposal.collateralToken, this.usdt.address, 'Invalid proposal collateral token');
        assert.strictEqual(proposal.price, '1000', 'Invalid proposal price');
        assert.strictEqual(proposal.buyer, user, 'Invalid proposal buyer');
        assert.strictEqual(proposal.beneficiary, user, 'Invalid proposal beneficiary');
      });

      it('getter reverts for non-existent proposal', async () => {
        // use the getter to consult
        await expectRevert(
          this.marketplace.getPurchaseReserveProposal(
            this.collection.address,
            0,
            this.usdt.address,
            this.usdt.address,
            1000,
            1000,
            time.duration.weeks(1),
            constants.ZERO_ADDRESS
          ),
          'Non-existent proposal'
        );
      });

      describe('test match found', () => {
        let salePriceOffer = 1000;

        beforeEach(async () => {
          const { user } = await getNamedAccounts();

          // create the sale proposal
          await this.marketplace.approveReserveToSell(
            this.collection.address,
            0,
            this.usdt.address,
            this.usdt.address,
            salePriceOffer,
            user,
            1000,
            time.duration.weeks(1),
            time.duration.weeks(1),
            constants.ZERO_ADDRESS,
            {
              from: user,
            }
          );
        });

        describe('tryToBuyReserve method', () => {
          it('emits PurchaseReserved if match found and allowance is enough', async () => {
            const { user, bob, alice } = await getNamedAccounts();

            // transfer the balances first
            await this.usdt.transfer(bob, salePriceOffer);

            // set the allowances
            await this.usdt.approve(this.marketplace.address, salePriceOffer, { from: bob });
            await this.collection.approve(this.marketplace.address, 0, { from: user });

            let tx = await this.marketplace.approveReserveToBuy(
              this.collection.address,
              0,
              this.usdt.address,
              this.usdt.address,
              salePriceOffer,
              alice,
              1000,
              time.duration.weeks(1),
              time.duration.weeks(1),
              user,
              {
                from: bob,
              }
            );

            let manager = await this.marketplace.reservesManagerAddress();

            // manager should have locked the tokens
            assert.strictEqual(await this.collection.ownerOf(0), manager, 'Invalid locked token');
            assert.strictEqual(
              (await this.usdt.balanceOf(manager)).toNumber(),
              (salePriceOffer * 10) / 100,
              'Invalid locked balance in marketplace'
            );

            expectEvent.notEmitted(tx, 'PurchaseReserveProposed');
            expectEvent(tx, 'PurchaseReserved', {
              collection: this.collection.address,
              tokenId: '0',
              paymentToken: this.usdt.address,
              collateralToken: this.usdt.address,
              price: String(salePriceOffer),
              collateralPercent: '1000',
              reservePeriod: time.duration.weeks(1),
            });
          });

          it('emits PurchaseReserveProposed if match found and not enough allowance', async () => {
            const { user, bob, alice } = await getNamedAccounts();

            // transfer the balances first
            await this.usdt.transfer(bob, salePriceOffer);

            // set the allowances
            await this.usdt.approve(this.marketplace.address, salePriceOffer, { from: bob });

            // sale with greater price than the one in purchase proposal
            let tx = await this.marketplace.approveReserveToBuy(
              this.collection.address,
              0,
              this.usdt.address,
              this.usdt.address,
              salePriceOffer,
              alice,
              1000,
              time.duration.weeks(1),
              time.duration.weeks(1),
              user,
              {
                from: bob,
              }
            );

            expectEvent(tx, 'PurchaseReserveProposed', {
              collection: this.collection.address,
              tokenId: '0',
              paymentToken: this.usdt.address,
              collateralToken: this.usdt.address,
              price: String(salePriceOffer),
              collateralPercent: '1000',
              reservePeriod: time.duration.weeks(1),
            });
          });

          it('return false if expirationTimesamp is passed', async () => {
            const { user, bob, alice } = await getNamedAccounts();

            // transfer the balances first
            await this.usdt.transfer(bob, salePriceOffer);

            // set the allowances
            await this.usdt.approve(this.marketplace.address, salePriceOffer, { from: bob });
            await this.collection.approve(this.marketplace.address, 0, { from: user });

            await time.increase(time.duration.weeks(2));

            // sale after expiration time
            await this.marketplace.approveReserveToBuy(
              this.collection.address,
              0,
              this.usdt.address,
              this.usdt.address,
              salePriceOffer,
              alice,
              1000,
              time.duration.weeks(1),
              time.duration.weeks(1),
              user,
              {
                from: bob,
              }
            );
          });
        });

        it('emits PurchaseReserveProposed if match found but the amount is not enough', async () => {
          const { deployer, user } = await getNamedAccounts();

          // purchase with enough price
          let tx = await this.marketplace.approveReserveToBuy(
            this.collection.address,
            0,
            this.usdt.address,
            this.usdt.address,
            salePriceOffer - 100,
            user,
            1000,
            time.duration.weeks(1),
            time.duration.weeks(1),
            user,
            {
              from: deployer,
            }
          );

          expectEvent(tx, 'PurchaseReserveProposed', {
            collection: this.collection.address,
            tokenId: '0',
            paymentToken: this.usdt.address,
            collateralToken: this.usdt.address,
            price: String(salePriceOffer - 100),
            collateralPercent: '1000',
            reservePeriod: time.duration.weeks(1),
          });
        });
      });
    });
  });

  describe('cancelSaleReserveProposal method', () => {
    beforeEach(async () => {
      const { user } = await getNamedAccounts();

      let deployment = await deployments.get('CollectionMock');
      this.collection = await CollectionMock.at(deployment.address);

      deployment = await deployments.get('USDTMock');
      this.usdt = await USDTMock.at(deployment.address);

      // mint the token
      await this.collection.safeMint(user);

      await this.marketplace.approveReserveToSell(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        user,
        1000,
        time.duration.weeks(1),
        time.duration.weeks(1),
        constants.ZERO_ADDRESS,
        {
          from: user,
        }
      );
    });

    it('reverts if caller is not the owner', async () => {
      const { user, bob } = await getNamedAccounts();

      let tx = this.marketplace.cancelSaleReserveProposal(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        1000,
        time.duration.weeks(1),
        user,
        {
          from: bob,
        }
      );

      await expectRevert(tx, 'Only owner can cancel');
    });

    it('emit SaleReserveProposalCanceled when the owner cancels', async () => {
      const { user } = await getNamedAccounts();

      let tx = await this.marketplace.cancelSaleReserveProposal(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        1000,
        time.duration.weeks(1),
        user,
        {
          from: user,
        }
      );

      expectEvent(tx, 'SaleReserveProposalCanceled', {
        collection: this.collection.address,
        tokenId: '0',
        paymentToken: this.usdt.address,
        collateralToken: this.usdt.address,
        price: '1000',
        collateralPercent: '1000',
        reservePeriod: time.duration.weeks(1),
      });
    });
  });

  describe('cancelPurchaseReserveProposal method', () => {
    beforeEach(async () => {
      const { user } = await getNamedAccounts();

      let deployment = await deployments.get('CollectionMock');
      this.collection = await CollectionMock.at(deployment.address);

      deployment = await deployments.get('USDTMock');
      this.usdt = await USDTMock.at(deployment.address);

      // mint the token
      await this.collection.safeMint(user);

      await this.usdt.transfer(user, 1000);

      await this.marketplace.approveReserveToBuy(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        user,
        1000,
        time.duration.weeks(1),
        time.duration.weeks(1),
        constants.ZERO_ADDRESS,
        {
          from: user,
        }
      );
    });

    it('reverts if caller is not the owner', async () => {
      const { user, bob } = await getNamedAccounts();

      let tx = this.marketplace.cancelPurchaseReserveProposal(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        1000,
        time.duration.weeks(1),
        user,
        {
          from: bob,
        }
      );

      await expectRevert(tx, 'Only buyer can cancel');
    });

    it('emit PurchaseReserveProposalCanceled when the owner cancels', async () => {
      const { user } = await getNamedAccounts();

      let tx = await this.marketplace.cancelPurchaseReserveProposal(
        this.collection.address,
        0,
        this.usdt.address,
        this.usdt.address,
        1000,
        1000,
        time.duration.weeks(1),
        user,
        {
          from: user,
        }
      );

      expectEvent(tx, 'PurchaseReserveProposalCanceled', {
        collection: this.collection.address,
        tokenId: '0',
        paymentToken: this.usdt.address,
        collateralToken: this.usdt.address,
        price: '1000',
        collateralPercent: '1000',
        reservePeriod: time.duration.weeks(1),
      });
    });
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
