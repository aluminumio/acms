RSpec.describe Acms::CLI do
  it "prints usage for unknown commands and makes wallets" do
    out = StringIO.new
    err = StringIO.new
    expect(described_class.run([ "nope" ], out: out, err: err)).to eq(1)
    expect(err.string).to include("Usage: acms")
    expect(described_class.run([ "wallet", "new" ], out: out, err: err)).to eq(0)
    expect(out.string).to match(/ACMS_PRIVATE_KEY=\h{64}\naddress=0x\h{40}/)
  end

  it "requires a key before talking to the API" do
    err = StringIO.new
    expect(described_class.run([ "invite", "redeem", "X", "--api-url", "http://localhost:1" ], out: StringIO.new, err: err)).to eq(1)
    expect(err.string).to include("private key")
  end
end
