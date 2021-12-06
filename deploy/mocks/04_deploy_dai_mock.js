module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  if (network.tags.local || network.tags.testnet) {
    await deploy('DAIMock', {
      from: deployer,
      log: true,
      args: [],
    });
  }
};

module.exports.tags = ['dai_mock'];
