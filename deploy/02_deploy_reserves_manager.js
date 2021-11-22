module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  // get previously deployed contracts
  let marketplace = await ethers.getContract('ReserveMarketplace');
  let protocolParameters = await ethers.getContract('ProtocolParameters');

  // ! IN PRODUCTION THE OWNERSHIP OF THIS CONTRACT SHOULD BE TRANSFERRED TO GOVERNANCE

  // this contract is upgradeable through uups (EIP-1822)
  let manager = await deploy('ReservesManager', {
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
    args: [marketplace.address, protocolParameters.address],
  });

  if (manager.newlyDeployed) {
    log('Initializing the Marketplace...');
    await marketplace.initialize(manager.address);
  }
};

module.exports.tags = ['reserves_manager'];
module.exports.dependencies = ['reserve_marketplace', 'protocol_parameters'];
