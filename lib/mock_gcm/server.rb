require 'xmlrpc/httpserver'
require 'json'
require 'thread'
require 'forwardable'

module MockGCM
  class Server
    extend Forwardable

    DEFAULT_HOST = 'localhost'

    def initialize(api_key, port)
      @api_key = api_key

      @received_messages = []
      @mutex = Mutex.new

      @server = HttpServer.new(self, port, DEFAULT_HOST, 1, File.open("/dev/null"), false, false)

      # Configurable error behaviour
      @next_request_errno = nil
      @canonicals        = {}
      @errors            = {}
    end

    # Manage server state

    def_delegators :@server, :start, :stop, :stopped?

    def mock_next_request_failure(errno)
      @mutex.synchronize { @next_request_errno = Integer(errno) }
    end

    def mock_canonical_id(reg_id, canonical_reg_id)
      @mutex.synchronize { @canonicals[reg_id] = canonical_reg_id }
    end

    def mock_error(reg_id, error, options = {})
      @mutex.synchronize { @errors[reg_id] = { :error => error, :times => options[:times] || -1 } }
    end

    # Check server state from request thread

    def error_for(reg_id)
      @mutex.synchronize {
        return unless hsh = @errors[reg_id]
        return unless hsh[:times] != 0

        hsh[:times] -= 1 if hsh[:times] >= 1
        hsh[:error]
      }
    end

    def canonical_id_for(reg_id)
      @mutex.synchronize { @canonicals[reg_id] }
    end

    # Message log

    def received_messages
      @mutex.synchronize { @received_messages.dup }
    end

    def add_received(reg_id, collapse_key, time_to_live, delay_while_idle, data)
      hsh = {
        'registration_id'  => reg_id.freeze,
        'collapse_key'     => collapse_key.freeze,
        'time_to_live'     => time_to_live.freeze,
        'delay_while_idle' => delay_while_idle.freeze,
        'data'             => data.freeze,
      }.freeze
      @mutex.synchronize { @received_messages << hsh }
    end

    # Check stuff

    def check_fail_next_request(request, response, req_data)
      next_request_errno = @mutex.synchronize do
        @next_request_errno.tap { @next_request_errno = nil }
      end

      if next_request_errno
        response.status = next_request_errno
        false
      else
        true
      end
    end

    def check_authorization_header(request, response, req_data)
      if request.header['Authorization'] == "key=#{@api_key}"
        true
      else
        response.status = 401
        false
      end
    end

    def check_content_type(request, response, req_data)
      if request.header['Content-Type'] == "application/json"
        true
      else
        response.status = 400
        false
      end
    end

    def check_data_format(request, response, req_data)
      fail = Proc.new do
        response.status = 400
        return false
      end
      json = JSON.parse(req_data) rescue fail.call

      # Required
      fail.call unless json["data"].is_a?(Hash)
      fail.call unless json["registration_ids"].is_a?(Array) && json["registration_ids"].all? { |reg_id| reg_id.is_a?(String) } && json["registration_ids"].size <= 1000
      # Optional
      fail.call unless json.fetch("collapse_key", "").is_a?(String)
      fail.call unless json.fetch("time_to_live", 1).is_a?(Integer)
      fail.call unless [true,false].include?(json.fetch("delay_while_idle", false))

      valid_fields = ["data", "registration_ids", "collapse_key", "time_to_live", "delay_while_idle"]
      json.keys.each do |key|
        fail.call unless valid_fields.include?(key)
      end

      true
    end

    def handle_req_data(req_data)
      req_json = JSON.parse(req_data)

      success, failure, canonical_ids, results = 0, 0, 0, []

      reg_ids = req_json['registration_ids']
      reg_ids.each do |reg_id|
        results << {}.tap do |result|
          if error = error_for(reg_id)
            result['error'] = error
            failure += 1
            next
          end

          if canonical_id = canonical_id_for(reg_id)
            result['registration_id'] = canonical_id
            canonical_ids += 1
          end

          result['message_id'] = rand(100_000_000)
          success += 1
        end

        add_received(reg_id, req_json['collapse_key'], req_json['time_to_live'],
                             req_json['delay_while_idle'], req_json.fetch('data'))
      end

      return success, failure, canonical_ids, results
    end

    # HttpServer handlers

    def ip_auth_handler(io)
      true
    end

    def request_handler(request, response)
      req_data = request.data.read(request.content_length)

      return unless check_fail_next_request(request, response, req_data)
      return unless check_authorization_header(request, response, req_data)
      return unless check_content_type(request, response, req_data)
      return unless check_data_format(request, response, req_data)

      success, failure, canonical_ids, results = handle_req_data(req_data)

      response.header['Content-Type'] = 'application/json'
      response.body = {
        'multicast_id'  => rand(100_000_000),
        'success'       => success,
        'failure'       => failure,
        'canonical_ids' => canonical_ids,
        'results'       => results
      }.to_json
    end

  end
end
