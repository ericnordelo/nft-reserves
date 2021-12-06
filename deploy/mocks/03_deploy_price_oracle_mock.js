module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  if (network.tags.local || network.tags.testnet) {
    let oracle = await deploy('PriceOracleMock', {
      from: deployer,
      log: true,
      args: [],
    });

    if (oracle.newlyDeployed) {
      log('Initializing the oracle...');
      oracle = await ethers.getContract('PriceOracleMock');
      let tx = await oracle.setPrice(oracle.address, '1');

      await tx.wait();
    }
  }
};

module.exports.tags = ['price_oracle_mock'];
