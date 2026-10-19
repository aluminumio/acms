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

RSpec.describe Acms::CLI, "sites commands" do
  let(:key) { Acms::Wallet.generate.private_key }
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:export) { { "id" => "e1", "name" => "demo-20261011T120000Z", "status" => "completed", "byte_size" => 4, "download_url" => "https://acm.test/blob", "created_at" => "2026-10-11T12:00:00Z" } }
  let(:transport) do
    FakeTransport.new(
      [ :post, "/api/v1/sites/s1/exports" ] => [ 201, { "export" => export.merge("status" => "pending", "download_url" => nil) } ],
      [ :get, "/api/v1/sites/s1/exports/e1" ] => [ 200, { "export" => export } ],
      [ :get, "/api/v1/sites/s1/exports" ] => [ 200, { "exports" => [ export, export.merge("name" => "demo-20261010T090000Z", "created_at" => "2026-10-10T09:00:00Z") ] } ],
      [ :get, "/api/v1/sites/s1" ] => [ 200, { "site" => { "id" => "s1", "name" => "Demo", "slug" => "demo" } } ],
      [ :delete, "/api/v1/sites/s1" ] => [ 200, { "deleted" => true, "id" => "s1", "slug" => "demo" } ],
      [ :get, "https://acm.test/blob" ] => [ 200, "PK!!" ]
    )
  end

  def run(*argv, input: "")
    described_class.run([ *argv, "--key", key ], out: out, err: err, input: StringIO.new(input), transport: transport)
  end

  before { allow_any_instance_of(described_class).to receive(:sleep) }

  it "exports, waits for completion and saves the file" do
    path = File.join(Dir.mktmpdir, "demo.zip")
    expect(run("sites:export", "s1", "-o", path)).to eq(0)
    expect(out.string).to include("name=demo-20261011T120000Z", "download_url=https://acm.test/blob", "saved=#{path} (4 bytes)")
    expect(File.binread(path)).to eq("PK!!")
  end

  it "lists exports newest first" do
    expect(run("sites:exports", "s1")).to eq(0)
    expect(out.string.lines.map { |l| l.split.first }).to eq(%w[demo-20261011T120000Z demo-20261010T090000Z])
  end

  it "requires --confirm-export to delete" do
    expect(run("sites:delete", "s1")).to eq(1)
    expect(err.string).to include("--confirm-export", "acms sites:exports s1")
    expect(transport.requests).to be_empty
  end

  it "deletes only after the user types the slug" do
    expect(run("sites:delete", "s1", "--confirm-export", "demo-20261011T120000Z", input: "nope\n")).to eq(1)
    expect(err.string).to include("did not match")
    expect(transport.requests.map(&:method)).not_to include(:delete)

    expect(run("sites:delete", "s1", "--confirm-export", "demo-20261011T120000Z", input: "demo\n")).to eq(0)
    expect(out.string).to include("Deleted site demo (s1)")
    expect(transport.requests.last.query).to eq(confirm_export: "demo-20261011T120000Z")
  end

  it "skips the prompt with --yes and reports the server's refusal" do
    transport = FakeTransport.new([ :delete, "/api/v1/sites/s1" ] => [ 422, { "error" => "Export the site first: acms sites:export s1, then delete with --confirm-export <name>" } ])
    code = described_class.run([ "sites:delete", "s1", "--confirm-export", "x", "--yes", "--key", key ], out: out, err: err, input: StringIO.new, transport: transport)
    expect(code).to eq(1)
    expect(err.string).to include("Export the site first: acms sites:export s1")
  end
end

RSpec.describe Acms::CLI, "connect:approve" do
  let(:key) { Acms::Wallet.generate.private_key }
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:pending) { { "user_code" => "QXRT-KMPB", "client_name" => "Enable", "scopes" => [ "analytics:read" ], "status" => "pending" } }
  let(:transport) do
    FakeTransport.new(
      [ :get, "/api/v1/device_approvals/QXRT-KMPB" ] => [ 200, { "device_authorization" => pending } ],
      [ :post, "/api/v1/device_approvals" ] => [ 200, { "device_authorization" => pending.merge("status" => "approved", "site_id" => "s1", "grant_id" => "g1") } ]
    )
  end

  def run(*argv, input: "")
    described_class.run([ *argv, "--key", key ], out: out, err: err, input: StringIO.new(input), transport: transport)
  end

  it "shows the client and scopes, and approves only after a yes" do
    expect(run("connect:approve", "QXRT-KMPB", "--site", "s1", input: "n\n")).to eq(1)
    expect(err.string).to include("Enable", "analytics:read", "s1")
    expect(transport.requests.map(&:method)).not_to include(:post)

    expect(run("connect:approve", "QXRT-KMPB", "--site", "s1", input: "y\n")).to eq(0)
    expect(JSON.parse(transport.requests.last.body)).to eq("user_code" => "QXRT-KMPB", "site_id" => "s1", "decision" => "approve")
    expect(out.string).to include("approved", "grant g1")
  end

  it "approves without asking with --yes, and denies with --deny" do
    expect(run("connect:approve", "QXRT-KMPB", "--site", "s1", "--yes")).to eq(0)
    expect(run("connect:approve", "QXRT-KMPB", "--site", "s1", "--deny", "--yes")).to eq(0)
    expect(JSON.parse(transport.requests.last.body)).to include("decision" => "deny")
  end

  it "requires --site" do
    expect(run("connect:approve", "QXRT-KMPB")).to eq(1)
    expect(err.string).to include("--site")
    expect(transport.requests).to be_empty
  end

  it "shows ACM's refusal" do
    transport = FakeTransport.new([ :post, "/api/v1/device_approvals" ] => [ 403, { "error" => "Only an owner or admin of the site's organization can decide." } ])
    code = described_class.run([ "connect:approve", "QXRT-KMPB", "--site", "s1", "--yes", "--key", key ], out: out, err: err, input: StringIO.new, transport: transport)
    expect(code).to eq(1)
    expect(err.string).to include("owner or admin")
  end
end
