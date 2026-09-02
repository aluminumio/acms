require "net/http"
require "uri"

module Acms
  module Contentful
    # Pulls a whole space from the Contentful Delivery (or Preview) API:
    # locales, content types, and every entry and asset with all locales
    # (locale=*), paged 1000 at a time. The result is the hash the Importer
    # and Verifier consume, and what `acms contentful dump` writes.
    class Fetcher
      PAGE = 1000
      MAX_REDIRECTS = 3

      def initialize(space_id:, access_token:, api_url: nil, environment: nil, http: nil)
        host = api_url.to_s.sub(%r{\Ahttps?://}, "").sub(%r{/\z}, "")
        host = "cdn.contentful.com" if host.empty?
        environment = "master" if environment.to_s.empty?
        @base = "https://#{host}/spaces/#{space_id}/environments/#{environment}"
        @access_token = access_token
        @http = http || method(:get_json)
      end

      def fetch
        {
          "locales" => items("locales"),
          "content_types" => items("content_types"),
          "entries" => items("entries", "locale" => "*", "include" => 0),
          "assets" => items("assets", "locale" => "*")
        }
      end

      def self.download(url, redirects = MAX_REDIRECTS)
        uri = URI(url)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        case response
        when Net::HTTPSuccess then response.body
        when Net::HTTPRedirection
          raise Error, "Too many redirects downloading #{url}" if redirects.zero?
          download(URI.join(url, response["location"]).to_s, redirects - 1)
        else
          raise Error, "Download of #{url} failed: HTTP #{response.code}"
        end
      end

      private

      def items(path, params = {})
        collected = []
        loop do
          page = @http.call(path, params.merge("limit" => PAGE, "skip" => collected.size))
          batch = Array(page["items"])
          collected.concat(batch)
          break if batch.empty? || collected.size >= page["total"].to_i
        end
        collected
      end

      def get_json(path, params)
        uri = URI("#{@base}/#{path}")
        uri.query = URI.encode_www_form(params)
        request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{@access_token}", "Accept" => "application/json")
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
        body = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end
        unless response.is_a?(Net::HTTPSuccess)
          detail = body["message"].to_s.empty? ? "HTTP #{response.code}" : body["message"]
          raise Error, "Contentful #{path}: #{detail} (#{body.dig('sys', 'id')})"
        end
        body
      end
    end
  end
end
