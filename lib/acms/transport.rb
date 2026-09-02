require "net/http"
require "uri"

module Acms
  Response = Struct.new(:status, :headers, :body) do
    def success?
      (200..299).cover?(status)
    end

    def json
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  end

  # Sends one HTTP request. Anything that responds to
  # `call(method, path, headers:, body:, content_type:, query:)` and returns an
  # Acms::Response can stand in (a Rack app in tests, for instance).
  class Transport
    def initialize(base_url, open_timeout: 10, read_timeout: 120)
      @base_url = URI(base_url.to_s.sub(%r{/\z}, ""))
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call(method, path, headers: {}, body: nil, content_type: nil, query: nil)
      uri = URI.join("#{@base_url}/", path.sub(%r{\A/}, ""))
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
      headers.each { |key, value| request[key] = value }
      if body
        request.body = body
        request["Content-Type"] = content_type if content_type
      end
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(request) }
      Response.new(response.code.to_i, response.to_hash, response.body.to_s)
    end
  end
end
