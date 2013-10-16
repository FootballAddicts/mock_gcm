# MockGcm

Fake GCM server for your integration testing needs.


Please be aware that this does not test everything as specific tests for errors like InvalidTtl, DataTooBig, InvalidRegistration are not made - but their results can be mocked.

## Installation

Add this line to your application's Gemfile:

    gem 'mock_gcm'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install mock_gcm

## Usage
    require 'mock_gcm'

    mock_gcm = MockGCM.new("my key", 8282)
    mock_gcm.start

    require 'gcm_client' # some gcm client library
    client = GcmClient.new(:url => "http://localhost:8282/", :api_key => "my key")
    client.send("registration_id1", {:some => :data})
    client.send("registration_id2", {:some => :data})

    mock_gcm.received_messages =>
    # => [
    #        {
    #          "collapse_key"     => nil,
    #          "time_to_live"     => nil,
    #          "delay_while_idle" => nil,
    #          "data"             => {"some" => "data"},
    #          "registration_id" =>  "registration_id1"
    #        }, {
    #          "collapse_key"     => nil,
    #          "time_to_live"     => nil,
    #          "delay_while_idle" => nil,
    #          "data"             => {"some" => "data"},
    #          "registration_id" =>  "registration_id2"
    #        }
    #    ]

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
