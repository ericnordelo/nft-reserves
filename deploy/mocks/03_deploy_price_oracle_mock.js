module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  if (network.tags.local || network.tags.testnet) {
    await deploy('PriceOracleMock', {
      from: deployer,
      log: true,
      args: [],
    });

    let oracle = await ethers.getContract('PriceOracleMock');
    oracle.setPrice(oracle.address, '1');
  }
};

module.exports.tags = ['price_oracle_mock'];
