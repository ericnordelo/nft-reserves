const ProtocolParameters = artifacts.require('ProtocolParameters');

describe('ProtocolParameters', function () {
  beforeEach(async () => {
    await deployments.fixture(['protocol_parameters']);
    let deployment = await deployments.get('ProtocolParameters');

    this.protocol = await ProtocolParameters.at(deployment.address);
  });

  it('should be deployed', async () => {
    assert.isOk(this.protocol.address);
  });
});
