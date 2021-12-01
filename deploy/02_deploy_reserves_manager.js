const { networkConfig } = require('../helper-hardhat-config');

module.exports = async ({ getNamedAccounts, deployments, network, getChainId }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // get previously deployed contracts
  let marketplace = await ethers.getContract('ReserveMarketplace');
  let protocolParameters = await ethers.getContract('ProtocolParameters');

  let priceOracleAddress = networkConfig[chainId].priceOracleAddress;

  if (network.tags.local || network.tags.testnet) {
    priceOracleAddress = (await ethers.getContract('PriceOracleMock')).address;
  }

  // ! IN PRODUCTION THE OWNERSHIP OF THIS CONTRACT SHOULD BE TRANSFERRED TO GOVERNANCE

  // this contract is upgradeable through uups (EIP-1822)
  let manager = await deploy('ReservesManager', {
    from: deployer,
    proxy: {
      proxyContract: 'UUPSProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [priceOracleAddress],
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
module.exports.dependencies = ['reserve_marketplace', 'protocol_parameters', 'price_oracle_mock'];
