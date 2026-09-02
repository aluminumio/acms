require "optparse"

module Acms
  # acms wallet new
  # acms invite redeem CODE
  # acms contentful dump   --file space.json
  # acms contentful import --site SITE [--file space.json]
  # acms contentful verify --site SITE [--file space.json]
  #
  # ACMS: --api-url / ACMS_API_URL, --key / ACMS_PRIVATE_KEY.
  # Contentful: CONTENTFUL_SPACE_ID, CONTENTFUL_ACCESS_TOKEN, CONTENTFUL_API_URL,
  # CONTENTFUL_ENVIRONMENT, or the matching --space/--token/--contentful-url/--environment.
  class CLI
    USAGE = <<~TEXT.freeze
      Usage: acms <command> [options]

        acms wallet new                       print a fresh private key and address
        acms invite redeem CODE               accept an invite with your key
        acms contentful dump   --file F       pull a Contentful space into a JSON file
        acms contentful import --site S       import a Contentful space (API or --file) into site S
        acms contentful verify --site S       diff a Contentful space against site S's delivery API

      Options:
        --api-url URL        ACMS API base URL (ACMS_API_URL, default #{Client::DEFAULT_URL})
        --key HEX            ACMS private key (ACMS_PRIVATE_KEY)
        --site ID            ACMS site id
        --file PATH          Contentful dump to read (import/verify) or write (dump)
        --space ID           Contentful space (CONTENTFUL_SPACE_ID)
        --token TOKEN        Contentful delivery token (CONTENTFUL_ACCESS_TOKEN)
        --contentful-url H   Contentful host (CONTENTFUL_API_URL, default cdn.contentful.com)
        --environment ENV    Contentful environment (CONTENTFUL_ENVIRONMENT, default master)
    TEXT

    def self.run(argv, out: $stdout, err: $stderr)
      new(out, err).run(argv.dup)
    rescue Acms::Error, OptionParser::ParseError, ArgumentError => e
      err.puts "acms: #{e.message}"
      1
    end

    def initialize(out, err)
      @out = out
      @err = err
    end

    def run(argv)
      options = parse(argv)
      case argv
      in [ "wallet", "new" ] then wallet_new
      in [ "invite", "redeem", code ] then invite_redeem(code, options)
      in [ "contentful", "dump" ] then contentful_dump(options)
      in [ "contentful", "import" ] then contentful_import(options)
      in [ "contentful", "verify" ] then contentful_verify(options)
      else
        @err.puts USAGE
        1
      end
    end

    private

    def parse(argv)
      options = {
        api_url: ENV.fetch("ACMS_API_URL", Client::DEFAULT_URL), key: ENV["ACMS_PRIVATE_KEY"],
        space: ENV["CONTENTFUL_SPACE_ID"], token: ENV["CONTENTFUL_ACCESS_TOKEN"],
        contentful_url: ENV["CONTENTFUL_API_URL"], environment: ENV["CONTENTFUL_ENVIRONMENT"]
      }
      OptionParser.new do |o|
        o.on("--api-url URL") { |v| options[:api_url] = v }
        o.on("--key HEX") { |v| options[:key] = v }
        o.on("--site ID") { |v| options[:site] = v }
        o.on("--file PATH") { |v| options[:file] = v }
        o.on("--space ID") { |v| options[:space] = v }
        o.on("--token TOKEN") { |v| options[:token] = v }
        o.on("--contentful-url HOST") { |v| options[:contentful_url] = v }
        o.on("--environment ENV") { |v| options[:environment] = v }
        o.on("-h", "--help") { @out.puts USAGE; exit 0 }
      end.parse!(argv)
      options
    end

    def wallet_new
      wallet = Wallet.generate
      @out.puts "ACMS_PRIVATE_KEY=#{wallet.private_key}"
      @out.puts "address=#{wallet.address}"
      0
    end

    def invite_redeem(code, options)
      result = client(options).redeem_invite(code)
      @out.puts "Redeemed: #{result['role']} on #{result['site_name']} (site #{result['site_id']})"
      0
    end

    def contentful_dump(options)
      raise ArgumentError, "--file is required" unless options[:file]

      data = fetch(options)
      File.write(options[:file], JSON.pretty_generate(data))
      @out.puts data.transform_values(&:size).map { |k, v| "#{v} #{k}" }.join(", ")
      0
    end

    def contentful_import(options)
      site_id = options[:site] or raise ArgumentError, "--site is required"
      data = contentful_data(options)
      counts = Importer.new(client(options), site_id, data, logger: ->(m) { @err.puts m }).import!
      @out.puts counts.map { |k, v| "#{v} #{k}" }.join(", ")
      0
    end

    def contentful_verify(options)
      site_id = options[:site] or raise ArgumentError, "--site is required"
      data = contentful_data(options)
      delivery = client(options).site(site_id)["contentful"] or raise Error, "The site returned no delivery credentials"
      result = Verifier.new(data, delivery: delivery).verify
      @out.puts "Compared #{result.content_types} content types and #{result.entries_compared}/#{result.entries_total} entries."
      @out.puts(result.ok? ? "No mismatches." : "#{result.mismatches.size} mismatches:\n#{result.mismatches.first(50).join("\n")}")
      result.ok? ? 0 : 2
    end

    def contentful_data(options)
      options[:file] ? JSON.parse(File.read(options[:file])) : fetch(options)
    end

    def fetch(options)
      raise ArgumentError, "Contentful space and token are required (--space/--token or CONTENTFUL_SPACE_ID/CONTENTFUL_ACCESS_TOKEN)" if options[:space].to_s.empty? || options[:token].to_s.empty?

      Contentful::Fetcher.new(space_id: options[:space], access_token: options[:token],
                              api_url: options[:contentful_url], environment: options[:environment]).fetch
    end

    def client(options)
      raise ArgumentError, "an ACMS private key is required (--key or ACMS_PRIVATE_KEY); `acms wallet new` makes one" if options[:key].to_s.empty?

      Client.new(wallet: Wallet.new(options[:key]), base_url: options[:api_url])
    end
  end
end
