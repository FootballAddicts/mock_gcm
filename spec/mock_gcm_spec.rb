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

  before { mock_gcm.start }
  after { mock_gcm.stop; sleep(0.01) until mock_gcm.stopped? }

  context 'correct data' do

    # TODO: http://developer.android.com/google/gcm/http.html#error_codes
    pending "it should fail individual messages according to fail message specification"
    pending "it should set canonical id for individual messages according to canonical id pecification"
    pending "it should fail (500) if mock server error trigger is set"

    optional_keys = ["collapse_key", "time_to_live", "delay_while_idle"]
    ([:all, :no] + optional_keys).each do |included_key|
      it "should accept and report messages including #{included_key} optional key(s)" do
        unless included_key == :all
          optional_keys.each { |key| valid_data.delete(key) unless key == included_key }
        end

        resp = http_client.post("http://localhost:8282", valid_data.to_json, headers)
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
          { "collapse_key"     => valid_data["collapse_key"],
            "time_to_live"     => valid_data["time_to_live"],
            "delay_while_idle" => valid_data['delay_while_idle'],
            "data"             => valid_data["data"],
            "registration_id" => registration_id }
        end
        mock_gcm.received_messages.should == expected_report
      end
    end

  end

  context 'missing api key' do
    it "should fail (401)" do
      resp = http_client.post("http://localhost:8282", valid_data.to_json, headers.reject { |k,v| k == 'Authorization' })
      resp.status.should == 401
      mock_gcm.received_messages.should be_empty
    end
  end

  context "incorrect data" do

    ['data', 'registration_ids'].each do |key|
      it "should fail (400) when #{key} (required) is missing" do
        resp = http_client.post("http://localhost:8282", valid_data.tap { |d| d.delete(key) }.to_json, headers)
        resp.status.should == 400
        mock_gcm.received_messages.should be_empty
      end
    end

    [ ['data', 1],
      ['registration_ids', 1],
      ['registration_ids', [1]],
      ['time_to_live', "123"],
      ['collapse_key', 1],
      ['delay_while_idle', "1"]
    ].each do |key, value|
      it "should fail (400) when #{key} = #{value} (incorrect type)" do
        resp = http_client.post("http://localhost:8282", valid_data.tap { |d| d[key] = value }.to_json, headers)
        resp.status.should == 400
        mock_gcm.received_messages.should be_empty
      end
    end

    it "should fail(400) when extra keys are present" do
      resp = http_client.post("http://localhost:8282", valid_data.tap { |d| d['extra'] = 1 }.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

    it "should fail (400) if non-valid-json data is sent" do
      resp = http_client.post("http://localhost:8282", "garbage%s" % valid_data.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

  end

  context "incorrect content-type header" do

    it "should fail (400)" do
      resp = http_client.post("http://localhost:8282", valid_data.to_json, headers.tap { |h| h['Content-Type'] = 'text/plain' })
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

  end

end
