require 'spec_helper'
require 'json'
require 'httpclient'

describe MockGCM do
  let(:api_key)     { "secrets" }
  let(:mock_gcm_port) { 8282 }
  let(:mock_gcm)    { MockGCM.new(api_key, mock_gcm_port) }
  let(:mock_gcm_url) { "http://localhost:#{mock_gcm_port}" }
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

    optional_keys = ["collapse_key", "time_to_live", "delay_while_idle"]
    ([:all, :no] + optional_keys).each do |included_key|
      it "should accept and report messages including #{included_key} optional key(s)" do
        unless included_key == :all
          optional_keys.each { |key| valid_data.delete(key) unless key == included_key }
        end

        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
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

    describe "#mock_error" do
      it "should fail sends to specified registration_id in subsequent requests" do
        errors = %w{
            MissingRegistration InvalidRegistration MismatchSenderId NotRegistered MessageTooBig
            InvalidDataKey InvalidTtl Unavailable InternalServerError InvalidPackageName
        }
        fails = {
          "42" => errors.sample,
          "16" => errors.sample
        }
        fails.each_pair do |reg_id, error|
          mock_gcm.mock_error(reg_id, error)
        end

        (1+rand(100)).times do
          resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
          resp.should be_ok

          json    = JSON.parse(resp.body)
          json.fetch('success').should == 4
          json.fetch('failure').should == 2
          json.fetch('canonical_ids').should == 0

          result_for = lambda do |reg_id|
            json.fetch('results').at(valid_data['registration_ids'].index(reg_id))
          end

          fails.each_pair do |reg_id, error|
            result = result_for.(reg_id)
            result.should_not include('message_id')
            result.fetch('error').should == error
            result.should_not include('registration_id')
          end

          (valid_data['registration_ids'] - fails.keys).each do |reg_id|
            result = result_for.(reg_id)
            result.should include('message_id')
            result.should_not include('error')
            result.should_not include('registration_id')
          end

        end

      end

      it "should limit error reporting to :times times if specified" do
        cnt = 1 + rand(100)

        errors = %w{
            MissingRegistration InvalidRegistration MismatchSenderId NotRegistered MessageTooBig
            InvalidDataKey InvalidTtl Unavailable InternalServerError InvalidPackageName
        }
        fails = {
          "42" => errors.sample,
          "16" => errors.sample
        }
        fails.each_pair do |reg_id, error|
          mock_gcm.mock_error(reg_id, error, :times => cnt)
        end

        cnt.times do
          resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
          resp.should be_ok

          json    = JSON.parse(resp.body)
          json.fetch('success').should == 4
          json.fetch('failure').should == 2
          json.fetch('canonical_ids').should == 0

          result_for = lambda do |reg_id|
            json.fetch('results').at(valid_data['registration_ids'].index(reg_id))
          end

          fails.each_pair do |reg_id, error|
            result = result_for.(reg_id)
            result.should_not include('message_id')
            result.fetch('error').should == error
            result.should_not include('registration_id')
          end

          (valid_data['registration_ids'] - fails.keys).each do |reg_id|
            result = result_for.(reg_id)
            result.should include('message_id')
            result.should_not include('error')
            result.should_not include('registration_id')
          end
        end

        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
        resp.should be_ok

        json    = JSON.parse(resp.body)
        json.fetch('success').should == 6
        json.fetch('failure').should == 0
      end

      it "should not affect unrelated requests" do
        mock_gcm.mock_error("not in valid data", "Unavailable")

        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
        resp.should be_ok

        json = JSON.parse(resp.body)
        json.fetch('failure').should == 0
        json.fetch('results').each { |hash| hash.should_not include('error') }
      end
    end

    describe "#mock_canonical_id" do

      it "should return canonical registration_id for specified registration_ids in subsequent requests" do
        canonicals = { "8" => "27", "42" => "19" }
        canonicals.each_pair do |reg_id, can_id|
          mock_gcm.mock_canonical_id(reg_id, can_id)
        end

        2.times do
          resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
          resp.should be_ok

          json    = JSON.parse(resp.body)
          json.fetch('success').should == 6
          json.fetch('failure').should == 0
          json.fetch('canonical_ids').should == 2

          result_for = lambda do |reg_id|
            json.fetch('results').at(valid_data['registration_ids'].index(reg_id))
          end

          canonicals.each do |reg_id, can_id|
            result = result_for.(reg_id)
            result.should include('message_id')
            result.should_not include('error')
            result.fetch('registration_id').should == can_id
          end

          (valid_data['registration_ids'] - canonicals.keys).each do |reg_id|
            result = result_for.(reg_id)
            result.should include('message_id')
            result.should_not include('error')
            result.should_not include('registration_id')
          end

        end

      end

      it "should not affect unrelated requests" do
        mock_gcm.mock_canonical_id("not in valid data", "1")

        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
        resp.should be_ok

        json = JSON.parse(resp.body)
        json.fetch('canonical_ids').should == 0
        json.fetch('results').each { |hash| hash.should_not include('registration_id') }
      end

    end

    describe "#mock_next_request_failure" do

      5.times do
        errno = 500 + rand(100)
        it "should fail (#{errno}) if requested" do
          mock_gcm.mock_next_request_failure(errno)
          resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
          resp.status.should == errno
          mock_gcm.received_messages.should be_empty
        end
      end

      it "should clear after one failure" do
        mock_gcm.mock_next_request_failure(500)
        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
        resp.status.should == 500
        mock_gcm.received_messages.should be_empty

        resp = http_client.post(mock_gcm_url, valid_data.to_json, headers)
        resp.should be_ok
      end

    end


  end

  context 'missing api key' do
    it "should fail (401)" do
      resp = http_client.post(mock_gcm_url, valid_data.to_json, headers.reject { |k,v| k == 'Authorization' })
      resp.status.should == 401
      mock_gcm.received_messages.should be_empty
    end
  end

  context "incorrect data" do

    it "should fail (400) given more than 1000 registration_ids" do
      resp = http_client.post(mock_gcm_url, valid_data.tap { |d| d['registration_ids'] = 1.upto(1001).map(&:to_s) }.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

    ['data', 'registration_ids'].each do |key|
      it "should fail (400) when #{key} (required) is missing" do
        resp = http_client.post(mock_gcm_url, valid_data.tap { |d| d.delete(key) }.to_json, headers)
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
      it "should fail (400) when #{key} = #{value.inspect} (incorrect type)" do
        resp = http_client.post(mock_gcm_url, valid_data.tap { |d| d[key] = value }.to_json, headers)
        resp.status.should == 400
        mock_gcm.received_messages.should be_empty
      end
    end

    it "should fail(400) when extra keys are present" do
      resp = http_client.post(mock_gcm_url, valid_data.tap { |d| d['extra'] = 1 }.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

    it "should fail (400) if non-valid-json data is sent" do
      resp = http_client.post(mock_gcm_url, "garbage%s" % valid_data.to_json, headers)
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

  end

  context "incorrect content-type header" do

    it "should fail (400)" do
      resp = http_client.post(mock_gcm_url, valid_data.to_json, headers.tap { |h| h['Content-Type'] = 'text/plain' })
      resp.status.should == 400
      mock_gcm.received_messages.should be_empty
    end

  end

end
