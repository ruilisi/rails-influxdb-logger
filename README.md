# influxdb-logger (Rails)

**Logger** for **Influxdb** in **Rails**

## Supported versions

 * Rails 4 and 5

## Installation

Add this line to your application's Gemfile:

    gem 'influxdb-logger', '1.0.1'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install influxdb-logger

## Usage

In `config/environments/production.rb`(`test.rb`, `development.rb`)

```ruby
config.logger = InfluxdbLogger::Logger.new(log_tags: {}, ...)

```

Supported parameters for `InfluxdbLogger::Logger.new`:

* `log_tags`: tags which you want the created logger to pass into influxdb, for example, 
  you could log **ip**, **user agent**, **device_type**(through requested parameters) and **version** with the following setup:

  ```ruby
    config.logger = InfluxdbLogger::Logger.new(log_tags: {
      ip: :ip,
      ua: :user_agent,
      device_type: -> request { request.params[:DEVICE_TYPE] },
      version: -> request { request.params[:VERSION] },
      session_id: -> request { request.params[:session_id] }
    }, settings: ...})

  ```

* `settings`: which defines how the logger would connect to influxdb database. More detail about it could found in [influxdb-ruby](https://github.com/influxdata/influxdb-ruby).
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

* `batch_size`, `interval`: Since logging is a high frequncy job for any application with large user base in production environment. These two parameters
   give a chance for the logger to batch logging actions.

   For example, you can tell the logger to log when size of logging actions hits `1000` or that the last logging action is `1000`ms later than the first one in the queue by:

  ```ruby
      InfluxdbLogger::Logger.new(batch_size: 1000, interval: 1000, log_tags: {
        ip: :ip,
        ua: :user_agent,
        device_type: -> request { request.params[:DEVICE_TYPE] },
        version: -> request { request.params[:VERSION] },
        session_id: -> request { request.params[:session_id] }
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

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
