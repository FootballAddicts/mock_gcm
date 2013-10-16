require 'spec_helper'
require 'json'
require 'httpclient'

describe MockGCM do
  let(:api_key)     { "secrets" }
  let(:mock_gcm)    { MockGCM.new(api_key, 8282) }
  let(:http_client) { HTTPClient.new }
  let(:headers) {
    { "Content-Type"  => "application/json",
      "Authorization" => "key=#{api_key}" }
  }
  let(:optional_keys) { ['collapse_key', 'time_to_live', 'delay_while_idle'] }
  let(:valid_data) {
    {
      "collapse_key"     => "score_update",
      "time_to_live"     => 108,
      "delay_while_idle" => true,
      "data"             => {
        "score" => "4x8",
        "time" => "15:16.2342"
      },
      "registration_ids" => ["4", "8", "15", "16", "23", "42"]
    }
  }

  before do
    mock_gcm.start
  end
  after do
    mock_gcm.stop
    sleep(0.1) until mock_gcm.stopped?
  end

  it "should recieve and report on correct sends" do
    ([:all] + optional_keys).each do |included_key|
      if included_key == :all
        data = valid_data
      else
        data = valid_data.reject { |k,v| included_key != k && optional_keys.include?(k) }
      end

      resp = http_client.post("http://localhost:8282", data.to_json, headers)
      resp.should be_ok
      resp.headers.fetch('Content-type').should == 'application/json'

      json = JSON.parse(resp.body)

      json.should include('multicast_id')
      json.fetch('success').should == 6
      json.fetch('failure').should == 0
      json.fetch('canonical_ids').should == 0


      results = json.fetch('results')
      results.size.should == 6
      results.each do |res|
        res.should include('message_id')
        res.should_not include('registration_id')
        res.should_not include('error')
      end

      expected_report = valid_data['registration_ids'].map do |registration_id|
        { "collapse_key"     => data["collapse_key"],
          "time_to_live"     => data["time_to_live"],
          "delay_while_idle" => data['delay_while_idle'],
          "data"             => data["data"],
          "registration_id" => registration_id }
      end
      mock_gcm.received_messages.should == expected_report
      mock_gcm.clear
    end
  end

  it "should fail (401) given missing api key" do
    resp = http_client.post("http://localhost:8282", valid_data.to_json, headers.reject { |k,v| k == 'Authorization' })
    resp.status.should == 401
    mock_gcm.received_messages.should be_empty
  end

  it "should fail (400) if incorrect data format is sent" do
    # Removing data
    (valid_data.keys - optional_keys).each do |key|
      resp = http_client.post("http://localhost:8282", valid_data.reject { |k,v| k == key }.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

    # Incorrect format
    [
      ['data', 1],
      ['registration_ids', 1],
      ['registration_ids', [1]],
      ['time_to_live', "123"],
      ['collapse_key', 1],
      ['delay_while_idle', "1"],
    ].each do |key, value|
      resp = http_client.post("http://localhost:8282", valid_data.dup.tap { |d| d[key] = value }.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

    # Adding data
    data = valid_data.dup
    data['extra_key'] = 'something'
    resp = http_client.post("http://localhost:8282", data.to_json, headers)
    resp.status.should == 400
    mock_gcm.received_messages.should be_empty

    # Not JSON
    resp = http_client.post("http://localhost:8282", "", headers)
    resp.status.should == 400
    mock_gcm.received_messages.should be_empty
  end

  it "should fail (400) incorrect content-type" do
    resp = http_client.post("http://localhost:8282", valid_data.to_json, headers.dup.tap { |h| h['Content-Type'] = 'text/plain' })
    resp.status.should == 400
    mock_gcm.received_messages.should be_empty
  end

  # TODO: http://developer.android.com/google/gcm/http.html#error_codes
  pending "it should fail individual messages according to fail message specification"
  pending "it should set canonical id for individual messages according to canonical id pecification"
  pending "it should fail (500) if mock server error trigger is set"

end
