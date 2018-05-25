# influxdb-logger (Rails)

Log to Influxdb in Rails

## Supported versions

 * Rails 4 and 5

## Installation

Add this line to your application's Gemfile:

    gem 'influxdb-logger', '5.1.4'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install influxdb-logger

## Usage

in config/environments/production.rb

#### Provide conf for influxdb

```ruby
    InfluxdbLogger::Logger.new(settings: {
      host: 'influxdb',
      database: 'rallets',
      series: series,
      retry: 3,
      username: 'user',
      password: 'password',
      time_precision: 'ms'
    })
```

#### Provide conf for influxdb, and log tags
```ruby
    InfluxdbLogger::Logger.new(log_tags: {
      ip: :ip,
      ua: :user_agent,
      uid: ->(request) { request.session[:uid] }
    }, settings: {
      host: 'influxdb',
      database: 'rallets',
      series: series,
      retry: 3,
      username: 'user',
      password: 'password',
      time_precision: 'ms'
    })
```


#### Provide conf for influxdb, and log tags, batch size, interval

```ruby
    InfluxdbLogger::Logger.new(batch_size: 999, interval: 1000, log_tags: {
      ip: :ip,
      ua: :user_agent,
      uid: ->(request) { request.session[:uid] }
    }, settings: {
      host: 'influxdb',
      database: 'rallets',
      series: series,
      retry: 3,
      username: 'user',
      password: 'password',
      time_precision: 'ms'
    })
```

The two arguments `batch_size` and `interval` mean that the log will push logs into `influxdb` only when count of messages is larger than `999` or 
time has passed for at least `1000ms` since last push.
Don't use config.log_tags.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
