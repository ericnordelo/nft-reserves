const { time } = require('@openzeppelin/test-helpers');

const networkConfig = {
  1337: {
    name: 'localhost',
  },
  31337: {
    name: 'hardhat',
    defaultProtocolParameters: {
      minimumReservePeriod: String(time.duration.minutes(5)),
      sellerCancelFeePercent: '5',
      buyerCancelFeePercent: '5',
      buyerPurchaseGracePeriod: 0,
    },
  },
  56: {
    name: 'bsc',
  },
  4: {
    name: 'rinkeby',
    defaultProtocolParameters: {
      minimumReservePeriod: String(time.duration.minutes(5)),
      sellerCancelFeePercent: '5',
      buyerCancelFeePercent: '5',
      buyerPurchaseGracePeriod: 0,
    },
  },
  80001: {
    name: 'mumbai',
    defaultProtocolParameters: {
      minimumReservePeriod: String(time.duration.minutes(5)),
      sellerCancelFeePercent: '5',
      buyerCancelFeePercent: '5',
      buyerPurchaseGracePeriod: 0,
    },
  },
  137: {
    name: 'polygon',
  },
};

module.exports = {
  networkConfig,
};
