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
end
