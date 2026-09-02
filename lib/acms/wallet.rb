require "digest/keccak"
require "rbsecp256k1"
require "securerandom"

module Acms
  # A secp256k1 key that is an identity on Agent Content Management. Requests
  # carry `Authorization: Bearer <unix-timestamp>.<130-hex EIP-191 signature>`
  # over the message "agentcontentmanagement.com:<timestamp>", valid for five
  # minutes; the server recovers the address from the signature.
  class Wallet
    DOMAIN = "agentcontentmanagement.com".freeze

    attr_reader :private_key

    def self.generate
      new(SecureRandom.hex(32))
    end

    def initialize(private_key_hex)
      @private_key = private_key_hex.to_s.sub(/\A0x/, "").downcase
      raise ArgumentError, "private key must be 32 bytes of hex" unless @private_key.match?(/\A\h{64}\z/)
    end

    def address
      @address ||= begin
        uncompressed = key_pair.public_key.uncompressed
        "0x#{Digest::Keccak.digest(uncompressed[1..], 256)[-20..].unpack1('H*')}"
      end
    end

    def auth_token(domain: DOMAIN, at: Time.now)
      timestamp = at.to_i.to_s
      message = "#{domain}:#{timestamp}"
      digest = Digest::Keccak.digest("\x19Ethereum Signed Message:\n#{message.bytesize}#{message}", 256)
      signature, recovery_id = context.sign_recoverable(key_pair.private_key, digest).compact
      "#{timestamp}.#{(signature + [ recovery_id + 27 ].pack('C')).unpack1('H*')}"
    end

    def auth_header(**options)
      { "Authorization" => "Bearer #{auth_token(**options)}" }
    end

    private

    def context
      @context ||= Secp256k1::Context.new
    end

    def key_pair
      @key_pair ||= context.key_pair_from_private_key([ private_key ].pack("H*"))
    end
  end
end
