RSpec.describe Acms::Wallet do
  it "derives a stable address and signs a fresh five-minute token" do
    wallet = described_class.new("1" * 64)
    expect(wallet.address).to match(/\A0x\h{40}\z/)
    expect(described_class.new("0x#{'1' * 64}").address).to eq(wallet.address)

    token = wallet.auth_token(at: Time.at(1_800_000_000))
    timestamp, signature = token.split(".")
    expect(timestamp).to eq("1800000000")
    expect(signature).to match(/\A\h{130}\z/)
    expect(wallet.auth_header["Authorization"]).to start_with("Bearer ")
  end

  it "generates random keys and rejects bad ones" do
    expect(described_class.generate.address).not_to eq(described_class.generate.address)
    expect { described_class.new("nope") }.to raise_error(ArgumentError)
  end
end
