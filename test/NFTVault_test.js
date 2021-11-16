const NFTVault = artifacts.require('NFTVault');

describe('NFTVault', function () {
  beforeEach(async () => {
    await deployments.fixture(['nft_vault']);
    let deployment = await deployments.get('NFTVault');

    this.vault = await NFTVault.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.vault.address);
  });
});
