const { networkConfig } = require('../../helper-hardhat-config');

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // ! IN PRODUCTION THIS ADDRESS SHOULD BE THE GOVERNANCE CONTRACT
  let governance = deployer;

  await deploy('ProtocolParameters', {
    from: deployer,
    logs: true,
    args: [...Object.values(networkConfig[chainId].defaultProtocolParameters), governance],
  });
};

module.exports.tags = ['protocol_parameters'];
