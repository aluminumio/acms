RSpec.describe Acms::Client do
  let(:transport) { FakeTransport.new([ :get, "/api/v1/sites/s1" ] => [ 200, { "site" => { "id" => "s1" } } ], [ :post, "/api/v1/sites/s1/entries" ] => [ 422, { "error" => "Title can't be blank" } ]) }
  let(:client) { described_class.new(wallet: Acms::Wallet.generate, base_url: "http://localhost:3000", transport: transport) }

  it "signs every request and unwraps the resource" do
    expect(client.site("s1")).to eq("id" => "s1")
    request = transport.requests.last
    expect(request.headers["Authorization"]).to match(/\ABearer \d+\.\h{130}\z/)
    expect(request.headers["Accept"]).to eq("application/json")
  end

  it "sends JSON bodies and raises on errors with the server's message" do
    expect { client.create_entry("s1", title: "") }.to raise_error(Acms::Error) { |e|
      expect(e.status).to eq(422)
      expect(e.message).to include("Title can't be blank")
    }
    expect(JSON.parse(transport.requests.last.body)).to eq("entry" => { "title" => "" })
    expect(transport.requests.last.content_type).to eq("application/json")
  end

  it "uploads assets as multipart with the extra fields" do
    client.create_asset("s1", file: "\x89PNG".b, filename: "a.png", content_type: "image/png", alt_text: "A")
    request = transport.requests.last
    expect(request.content_type).to start_with("multipart/form-data; boundary=")
    expect(request.body).to include('name="alt_text"', "A", 'name="filename"', 'filename="a.png"', "Content-Type: image/png", "\x89PNG".b)
  end

  it "maps membership and invite endpoints" do
    client.redeem_invite("CODE")
    client.leave_site("s1")
    expect(transport.requests.map { |r| [ r.method, r.path ] }).to eq([ [ :post, "/api/v1/invites/CODE/redeem" ], [ :delete, "/api/v1/sites/s1/membership" ] ])
  end

  it "maps site export and delete endpoints" do
    client.export_site("s1")
    client.site_exports("s1")
    client.site_export("s1", "e1")
    client.delete_site("s1", confirm_export: "demo-20261011T120000Z")
    expect(transport.requests.map { |r| [ r.method, r.path ] }).to eq([
      [ :post, "/api/v1/sites/s1/exports" ], [ :get, "/api/v1/sites/s1/exports" ],
      [ :get, "/api/v1/sites/s1/exports/e1" ], [ :delete, "/api/v1/sites/s1" ]
    ])
    expect(transport.requests.last.query).to eq(confirm_export: "demo-20261011T120000Z")
  end

  it "downloads a file across a redirect without the wallet header" do
    transport = FakeTransport.new([ :get, "https://acm.test/blob" ] => [ 302, "", { "location" => [ "https://s3.test/f.zip" ] } ],
                                  [ :get, "https://s3.test/f.zip" ] => [ 200, "PK\x03\x04" ])
    client = described_class.new(wallet: Acms::Wallet.generate, transport: transport)
    expect(client.download("https://acm.test/blob")).to eq("PK\x03\x04")
    expect(transport.requests.map(&:headers)).to all(be_empty)
  end
end
