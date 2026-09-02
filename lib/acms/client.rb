module Acms
  # The agent API (/api/v1), signed by a Wallet. Methods return the parsed
  # resource and raise Acms::Error on any non-2xx response.
  class Client
    DEFAULT_URL = "https://agentcontentmanagement.com".freeze

    attr_reader :wallet, :base_url

    def initialize(wallet:, base_url: DEFAULT_URL, transport: nil)
      @wallet = wallet
      @base_url = base_url
      @transport = transport || Transport.new(base_url)
    end

    # ---- sites and membership --------------------------------------------

    def redeem_invite(code)
      post("/api/v1/invites/#{code}/redeem")
    end

    def leave_site(site_id)
      delete("/api/v1/sites/#{site_id}/membership")
    end

    def site(site_id)
      get("/api/v1/sites/#{site_id}")["site"]
    end

    def update_site(site_id, attrs)
      patch("/api/v1/sites/#{site_id}", site: attrs)["site"]
    end

    # ---- entry types -------------------------------------------------------

    def entry_types(site_id)
      get("/api/v1/sites/#{site_id}/entry_types")["entry_types"]
    end

    def create_entry_type(site_id, attrs, fields: [])
      post("/api/v1/sites/#{site_id}/entry_types", entry_type: attrs, fields: fields)["entry_type"]
    end

    def update_entry_type(site_id, id, attrs, fields: nil)
      body = { entry_type: attrs }
      body[:fields] = fields if fields
      patch("/api/v1/sites/#{site_id}/entry_types/#{id}", body)["entry_type"]
    end

    # ---- entries -----------------------------------------------------------

    def entries(site_id)
      get("/api/v1/sites/#{site_id}/entries")["entries"]
    end

    def create_entry(site_id, attrs)
      post("/api/v1/sites/#{site_id}/entries", entry: attrs)["entry"]
    end

    # PATCH merges `data` and `metadata` by key on the server.
    def update_entry(site_id, id, attrs)
      patch("/api/v1/sites/#{site_id}/entries/#{id}", entry: attrs)["entry"]
    end

    # ---- assets ------------------------------------------------------------

    def assets(site_id)
      get("/api/v1/sites/#{site_id}/assets")["assets"]
    end

    def create_asset(site_id, file:, filename:, content_type: nil, **fields)
      upload("/api/v1/sites/#{site_id}/assets", file: file, filename: filename, content_type: content_type,
                                                 fields: fields.merge(filename: filename))["asset"]
    end

    def update_asset(site_id, id, attrs)
      patch("/api/v1/sites/#{site_id}/assets/#{id}", attrs)["asset"]
    end

    # ---- transport ---------------------------------------------------------

    def get(path, query = {})
      request(:get, path, query: query)
    end

    def post(path, body = nil)
      request(:post, path, body: body && JSON.generate(body), content_type: "application/json")
    end

    def patch(path, body)
      request(:patch, path, body: JSON.generate(body), content_type: "application/json")
    end

    def delete(path)
      request(:delete, path)
    end

    def upload(path, file:, filename:, fields: {}, content_type: nil)
      boundary = "acms#{SecureRandom.hex(12)}"
      body = +""
      fields.compact.each do |name, value|
        body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
      end
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      body << "Content-Type: #{content_type || 'application/octet-stream'}\r\n\r\n"
      body << file.b << "\r\n--#{boundary}--\r\n"
      request(:post, path, body: body, content_type: "multipart/form-data; boundary=#{boundary}")
    end

    private

    def request(method, path, body: nil, content_type: nil, query: nil)
      headers = wallet.auth_header.merge("Accept" => "application/json")
      response = @transport.call(method, path, headers: headers, body: body, content_type: content_type, query: query)
      json = response.json
      unless response.success?
        message = (json && json["error"]) || "HTTP #{response.status}"
        raise Error.new("#{method.to_s.upcase} #{path}: #{message}", status: response.status, body: json || response.body)
      end
      json || {}
    end
  end
end
