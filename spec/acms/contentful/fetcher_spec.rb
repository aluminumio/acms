RSpec.describe Acms::Contentful::Fetcher do
  it "pages through every collection and asks for all locales" do
    calls = []
    http = lambda do |path, params|
      calls << [ path, params ]
      skip = params["skip"]
      items = (skip...[ skip + 2, 3 ].min).map { |i| { "sys" => { "id" => "#{path}#{i}" } } }
      { "total" => 3, "items" => items }
    end
    data = described_class.new(space_id: "sp", access_token: "t", http: http).fetch
    expect(data.keys).to eq(%w[locales content_types entries assets])
    expect(data["entries"].size).to eq(3)
    expect(calls.find { |path, _| path == "entries" }[1]).to include("locale" => "*", "include" => 0, "skip" => 0, "limit" => 1000)
    expect(calls.count { |path, _| path == "assets" }).to eq(2)
  end
end
