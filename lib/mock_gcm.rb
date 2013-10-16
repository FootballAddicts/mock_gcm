require "mock_gcm/version"
require "mock_gcm/server"

module MockGCM
  extend self

  def new(*attrs)
    Server.new(*attrs)
  end
end
