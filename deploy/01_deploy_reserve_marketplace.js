module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // get previously deployed contracts
  let protocolParameters = await ethers.getContract('ProtocolParameters');

  // ! IN PRODUCTION THE OWNERSHIP OF THIS CONTRACT SHOULD BE TRANSFERRED TO GOVERNANCE

  // this contract is upgradeable through uups (EIP-1822)
  await deploy('ReserveMarketplace', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPSProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [],
        },
      },
    },
    log: true,
    args: [protocolParameters.address],
  });
};

module.exports.tags = ['reserve_marketplace'];
module.exports.dependencies = ['protocol_parameters'];
