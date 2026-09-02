require "acms"
require "acms/cli"

# A transport that answers from a table of [method, path] → Response and
# records every request, so client behaviour is checked without a server.
class FakeTransport
  Request = Struct.new(:method, :path, :headers, :body, :content_type, :query)

  attr_reader :requests

  def initialize(responses = {})
    @responses = responses
    @requests = []
  end

  def call(method, path, headers: {}, body: nil, content_type: nil, query: nil)
    @requests << Request.new(method, path, headers, body, content_type, query)
    status, payload = @responses.fetch([ method, path ]) { [ 200, {} ] }
    Acms::Response.new(status, {}, JSON.generate(payload))
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
