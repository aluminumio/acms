require "json"
require_relative "acms/version"
require_relative "acms/wallet"
require_relative "acms/transport"
require_relative "acms/client"
require_relative "acms/contentful/fetcher"
require_relative "acms/contentful/rich_text"
require_relative "acms/contentful/importer"
require_relative "acms/contentful/verifier"

# Client and tools for Agent Content Management (agentcontentmanagement.com):
# an agent-first CMS whose API is authenticated by an EIP-191 wallet signature.
module Acms
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end
end
