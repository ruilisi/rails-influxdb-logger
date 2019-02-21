require 'influxdb'
require 'active_support/core_ext'
require 'uri'
require 'cgi'


class Time
  def to_precision(precision)
    case precision
    when 'ns'
      self.to_ns
    when 'u'
      (self.to_r * 1000000).to_i
    when 'ms'
      self.to_ms
    when 's'
      self.to_i
    when 'm'
      self.to_i / 60
    when 'h'
      self.to_i / 3600
    else
      self.to_ns
    end
  end

  def to_ns
    (self.to_r * 1000000000).to_i
  end

  def to_ms
    (self.to_r * 1000).to_i
  end
end

def log_to_file(message) # for test
  open("#{Rails.root}/log/my.log", 'a') { |f|
    f.puts message.inspect
  }
end

module InfluxdbLogger
  module Logger
    # Severity label for logging. (max 5 char)
    SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY)

    def self.new(async: true, tags: [], fields: {}, settings: {}, batch_size: 1000, interval: 1000)
      log_tags = fields.values
      Rails.application.config.log_tags = log_tags
      if Rails.application.config.respond_to?(:action_cable)
        Rails.application.config.action_cable.log_tags = log_tags.map do |x|
          case
            when x.respond_to?(:call)
              x
            when x.is_a?(Symbol)
              -> (request) { request.send(x) }
            else
              -> (request) { x }
          end
        end
      end

      if ENV["INFLUXDB_URL"]
        settings = self.parse_url(ENV["INFLUXDB_URL"]).merge(settings)
      end

      settings[:batch_size] ||= batch_size
      settings[:interval] ||= interval
      settings[:async] = async

      level = SEV_LABEL.index(Rails.application.config.log_level.to_s.upcase)
      inner_logger = InfluxdbLogger::InnerLogger.new(settings, level, tags, fields)
      logger = ActiveSupport::TaggedLogging.new(inner_logger)
      logger.extend self
    end

    def self.parse_url(influxdb_url)
      uri = URI.parse influxdb_url
      params = CGI.parse uri.query
      {
        database: uri.path[1..-1],
        host: uri.host,
        port: uri.port,
        messages_type: params['messages_type'].try(:first),
        severity_key: params['severity_key'].try(:first),
        username: params['username'].try(:first),
        password: params['password'].try(:first),
        series: params['series'].try(:first),
        time_precision: params['time_precision'].try(:first),
        retry: params['retry'].try(:first).to_i
      }
    end

    def tagged(*tags)
      @tags = tags.flatten
      yield self
    ensure
      flush
    end
  end

  class InnerLogger < ActiveSupport::Logger
    def initialize(options, level, influxdb_tags, fields)
      self.level = level
      @messages_type = (options[:messages_type] || :array).to_sym
      @tag = options[:tag]
      @severity_key = (options[:severity_key] || :severity).to_sym
      @batch_size = options[:batch_size]
      @interval = options[:interval]
      @series = options[:series]
      @retention = options[:retention]
      @global_tags = {}
      @last_flush_time = Time.now.to_ms
      @value_filter = options[:value_filter] || {}
      @time_precision = options[:time_precision] || 'ns'

      @influxdb_logger = InfluxDB::Client.new(
        **options.slice(:host, :port, :database, :retry, :username, :password, :async),
        time_precision: @time_precision,
        discard_write_errors: true
      )

      @influxdb_tags = influxdb_tags
      @severity = 0
      @messages = []
      @tag_keys = influxdb_tags
      @fields = fields
      after_initialize if respond_to? :after_initialize
    end

    def [](key)
      @global_tags[key]
    end

    def []=(key, value)
      @global_tags[key] = value
    end

    def add(severity, message = nil, progname = nil, &block)
      return true if severity < level
      message = (block_given? ? block.call : progname) if message.blank?
      return true if message.blank?
      add_message(severity, message)
      true
    end

    def utf8_encoded(message)
      if message.encoding == Encoding::UTF_8
        message
      else
        message.dup.force_encoding(Encoding::UTF_8)
      end
    end

    def add_message(severity, message)
      @severity = severity if @severity < severity

      values =
        case message
          when ::String
            {
              message_type: 'String',
              message: utf8_encoded(message)
            }
          when ::Hash
            message.slice!(*@value_filter[:only]) if @value_filter[:only].present?
            message.except!(*@value_filter[:except]) if @value_filter[:except].present?
            message.merge({
              message_type: 'Hash'
            })
          when ::Exception
            {
              message_type: 'Exception',
              message: message.message,
              class: message.class,
              backtrace: message.backtrace
            }
          else
            {
              message_type: 'Others',
              message: message.inspect
            }
        end

      if @tags
        @tag_keys.zip(@tags).each do |k, v|
          values[k] = v
        end
      end
      message = {
        series: @series,
        timestamp: Time.now.to_precision(@time_precision),
        tags: values.slice(*@influxdb_tags).merge(@global_tags),
        values: values.except(*@influxdb_tags).merge({
          severity: format_severity(@severity)
        }).transform_values {|value|
          case value
            when ::Numeric, ::String
              value
            when ::Hash
              value.to_json
            when ::Symbol
              value.to_s
            else
              value.inspect
          end
        }
      }

      @messages << message
      flush if @messages.size >= @batch_size || (Time.now.to_ms - @last_flush_time) > @interval
    end

    def flush
      return if @messages.empty?
      @influxdb_logger.write_points(@messages, @time_precision, @retention)
      @severity = 0
      @messages.clear
      @last_flush_time = Time.now.to_ms
      @tags = nil
    end

    def close
    end

    def level
      @level
    end

    def level=(l)
      @level = l
    end

    def format_severity(severity)
      InfluxdbLogger::Logger::SEV_LABEL[severity] || 'ANY'
    end
  end
end
