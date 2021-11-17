const { networkConfig } = require('../../helper-hardhat-config');

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // ! IN PRODUCTION THIS ADDRESS SHOULD BE THE GOVERNANCE CONTRACT
  let governance = deployer;

  // this contract is upgradeable through uups (EIP-1822)
  await deploy('ProtocolParameters', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPSProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [...Object.values(networkConfig[chainId].defaultProtocolParameters), governance],
        },
      },
    },
    log: true,
    args: [],
  });
};

module.exports.tags = ['protocol_parameters'];
