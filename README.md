# influxdb-logger (Rails)

**Logger** for **Influxdb** in **Rails**

## Supported versions

 * Rails 4 and 5

## Installation

Add this line to your application's Gemfile:

    gem 'influxdb-logger', '2.0.0'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install influxdb-logger

## Basic Usage

In `config/environments/production.rb`(`test.rb`, `development.rb`)

```ruby
config.logger = InfluxdbLogger::Logger.new(influxdb_tags: ... tags: ... settings: ... batch_size: ..., interval: ...,  async: ...)

```

By default, influxdb-logger will log
`duration, db, format, location, message, message_type, method, params, path, severity, status, view` as [fields](https://docs.influxdata.com/influxdb/v1.7/concepts/key_concepts/#field-key) into specified
[series](https://docs.influxdata.com/influxdb/v1.7/concepts/key_concepts/#series).

Which means, your `influxdb-logger` is good to go with configuration only about how to talk to influxdb: 
```ruby
config.logger = InfluxdbLogger::Logger.new(settings: {
  database: ENV['INFLUXDB_DB_NAME'],
  series: ENV['INFLUXDB_SERIES'],
  username: ENV['INFLUXDB_USER'],
  password: ENV['INFLUXDB_USER_PASSWORD']
})
```

## Advanced Usage

* `influxdb_tags`[Array]: This argument specifies [tag-set](https://docs.influxdata.com/influxdb/v1.7/concepts/key_concepts/#tag-set) of series.
If we need to constantly checkout influxdb logs about specific `controller` or `action`, the best way is to tag both fields to speed up any query on them utilizing `influxdb_tags`:
  ```ruby
  config.logger = InfluxdbLogger::Logger.new(infludb_tags: [:controller, :action], settings: ...)
  ```

* `tags`[Hash]: If extra fields are required to be sent to influxdb, `tags` could be utilized, e.g., ip info of agents:
  ```ruby
  config.logger = InfluxdbLogger::Logger.new(tags: {
    remote_ip: -> request { request.remote_ip }
  },  settings: ...)
  ```
  Passed `tags` can be a `Hash` consisting values of any basic ruby type or a `lambda`. 

* `settings`: Which defines how our `influxdb-logger` connects to influxdb database. Detailed doc about it is here: [influxdb-ruby](https://github.com/influxdata/influxdb-ruby).
  ```ruby
  InfluxdbLogger::Logger.new(settings: {
    host: 'influxdb',
    retry: 3,
    time_precision: 'ms',
    database: ENV['INFLUXDB_DB_NAME'],
    series: ENV['INFLUXDB_SERIES'],
    username: ENV['INFLUXDB_USER'],
    password: ENV['INFLUXDB_USER_PASSWORD']
  })
  ```

* `batch_size`, `interval`: Since logging is a high frequncy job for any application with large user base in production environment. These two parameters
   give a chance for the logger to batch logging actions.

   For example, you can tell the logger to log when size of logging actions hits `1000` or that the last logging action is `1000`ms later than the first one in the queue by:

  ```ruby
  InfluxdbLogger::Logger.new(batch_size: 1000, interval: 1000, settings: ...)
  ```

* `async`: Determines whether the logger write asynchronously to influxdb, default to `false`. Read code [here](https://github.com/influxdata/influxdb-ruby/blob/master/lib/influxdb/writer/async.rb#L48) to know how it works.
  ```ruby
  InfluxdbLogger::Logger.new(async: false, settings: ...)
  ```

## License

MIT

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
