module Acms
  module Contentful
    # Compares a Contentful space (Fetcher output) against a site's
    # Contentful-compatible delivery API, field by field, in the default
    # locale. Asset ids differ between the two systems, links to entries the
    # space never returned are dropped (Contentful drops them from resolved
    # responses too), empty text nodes are noise, and marks compare as a
    # sorted list of types.
    class Verifier
      Result = Struct.new(:content_types, :entries_compared, :entries_total, :mismatches) do
        def ok?
          mismatches.empty?
        end
      end

      # delivery: { "api_url" =>, "space_id" =>, "access_token" => } as returned
      # under `contentful` by GET /api/v1/sites/:id
      def initialize(data, delivery:, http: nil)
        @data = data
        @delivery = delivery
        @http = http || method(:get_json)
      end

      def verify
        mismatches = []
        types = Array(@data["content_types"])
        ours_types = paged("content_types").to_h { |ct| [ ct.dig("sys", "id"), ct ] }
        types.each do |ct|
          id = ct.dig("sys", "id")
          next mismatches << "content type #{id}: missing" unless ours_types[id]

          theirs = ct["fields"].reject { |f| f["omitted"] }.to_h { |f| [ f["id"], f.slice("type", "linkType", "items") ] }
          mine = ours_types[id]["fields"].to_h { |f| [ f["id"], f.slice("type", "linkType", "items") ] }
          theirs.each { |fid, spec| mismatches << "content type #{id}.#{fid}: #{spec} vs #{mine[fid].inspect}" unless mine[fid] == spec }
        end

        default_locale = (@data["locales"].find { |l| l["default"] } || @data["locales"].first || {})["code"]
        known = Array(@data["entries"]).map { |e| e.dig("sys", "id") }
        ours = {}
        types.each do |ct|
          paged("entries", "content_type" => ct.dig("sys", "id"), "include" => 0).each { |e| ours[e.dig("sys", "id")] = e }
        end

        compared = 0
        Array(@data["entries"]).each do |entry|
          id = entry.dig("sys", "id")
          next mismatches << "entry #{id}: missing" unless ours[id]

          compared += 1
          mine = ours[id]["fields"]
          entry["fields"].each do |field_id, by_locale|
            next unless by_locale.is_a?(Hash) && by_locale.key?(default_locale)

            expected = normalize(by_locale[default_locale], known)
            actual = normalize(mine[field_id], known)
            mismatches << "entry #{id}.#{field_id}: expected #{truncate(expected.inspect)} got #{truncate(actual.inspect)}" unless expected == actual
          end
        end

        Result.new(types.size, compared, Array(@data["entries"]).size, mismatches)
      end

      private

      def normalize(value, known)
        case value
        when Hash
          if value.dig("sys", "linkType") == "Asset" then { "asset" => true }
          elsif value.dig("sys", "linkType") == "Entry" && !known.include?(value.dig("sys", "id")) then nil
          elsif value["nodeType"] == "text" && value["value"].to_s.empty? then nil
          elsif value["nodeType"]
            node = value.reject { |k, _| k == "data" }
            node["content"] = Array(value["content"]).map { |c| normalize(c, known) }.compact
            node["marks"] = Array(value["marks"]).map { |m| m["type"] }.sort if value.key?("marks")
            node.compact
          else value.transform_values { |v| normalize(v, known) }
          end
        when Array then value.map { |v| normalize(v, known) }.compact
        else value
        end
      end

      def truncate(text, max = 160)
        text.length > max ? "#{text[0, max]}…" : text
      end

      def paged(path, params = {})
        collected = []
        loop do
          page = @http.call(path, params.merge("limit" => 1000, "skip" => collected.size))
          batch = Array(page["items"])
          collected.concat(batch)
          break if batch.empty? || collected.size >= page["total"].to_i
        end
        collected
      end

      def get_json(path, params)
        base = @delivery["api_url"].to_s
        base = "https://#{base}" unless base.start_with?("http")
        uri = URI("#{base}/spaces/#{@delivery['space_id']}/#{path}")
        uri.query = URI.encode_www_form(params)
        request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{@delivery['access_token']}")
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
        raise Error, "#{uri}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      end
    end
  end
end
