const { time } = require('@openzeppelin/test-helpers');

const networkConfig = {
  1337: {
    name: 'localhost',
  },
  31337: {
    name: 'hardhat',
    defaultProtocolParameters: {
      minimumReservePeriod: String(time.duration.minutes(5)),
    },
  },
  56: {
    name: 'bsc',
  },
  80001: {
    name: 'mumbai',
  },
  137: {
    name: 'polygon',
  },
};

module.exports = {
  networkConfig,
};
