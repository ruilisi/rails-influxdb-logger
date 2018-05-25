require 'influxdb'
require 'active_support/core_ext'
require 'uri'
require 'cgi'


class Time
  def to_ms
    (self.to_f * 1000.0).to_i
  end
end

module InfluxdbLogger

  module Logger

    # Severity label for logging. (max 5 char)
    SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY)

    def self.new(log_tags: {}, settings: {}, batch_size: 1000, interval: 1000)
      Rails.application.config.log_tags = log_tags.values
      if Rails.application.config.respond_to?(:action_cable)
        Rails.application.config.action_cable.log_tags = log_tags.values.map do |x|
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
      if (0 == settings.length)
        fluent_config = if ENV["FLUENTD_URL"]
                          self.parse_url(ENV["FLUENTD_URL"])
                        end
        settings = {
          tag:  fluent_config['tag'],
          host: fluent_config['fluent_host'],
          port: fluent_config['fluent_port'],
          nanosecond_precision: fluent_config['nanosecond_precision'],
          messages_type: fluent_config['messages_type'],
          severity_key: fluent_config['severity_key'],
        }
      end

      settings[:batch_size] ||= batch_size
      settings[:interval] ||= interval

      level = SEV_LABEL.index(Rails.application.config.log_level.to_s.upcase)
      logger = InfluxdbLogger::FluentLogger.new(settings, level, log_tags)
      logger = ActiveSupport::TaggedLogging.new(logger)
      logger.extend self
    end

    def self.parse_url(fluentd_url)
      uri = URI.parse fluentd_url
      params = CGI.parse uri.query

      {
        fluent_host: uri.host,
        fluent_port: uri.port,
        tag: uri.path[1..-1],
        nanosecond_precision: params['nanosecond_precision'].try(:first),
        messages_type: params['messages_type'].try(:first),
        severity_key: params['severity_key'].try(:first),
      }.stringify_keys
    end

    def tagged(*tags)
      @tags = tags.flatten
      yield self
    ensure
      flush
    end
  end

  class FluentLogger < ActiveSupport::Logger
    def initialize(options, level, log_tags)
      self.level = level
      @messages_type = (options[:messages_type] || :array).to_sym
      @tag = options[:tag]
      @severity_key = (options[:severity_key] || :severity).to_sym
      @batch_size = options[:batch_size]
      @interval = options[:interval]
      @series = options[:series]
      @global_tags = {}
      @last_flush_time = Time.now.to_ms

      @influxdb_logger = InfluxDB::Client.new(
        host: options[:host],
        database: options[:database],
        retry: options[:retry],
        username: options[:username],
        password: options[:password],
        time_precision: options[:time_precision]
      )

      @severity = 0
      @messages = []
      @log_tags = log_tags
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

      tags = @global_tags.clone

      if @tags
        @log_tags.keys.zip(@tags).each do |k, v|
          tags[k] = v
        end
      end

      message = {
        series: @series,
        timestamp: Time.now.to_ms,
        tags: tags,
        values: values.merge({
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
      # test switch
      # open("#{Rails.root}/log/my.log", 'w') { |f|
      #   f.puts @messages
      # }
      @influxdb_logger.write_points(@messages)
      @severity = 0
      @messages.clear
      @last_flush_time = Time.now.to_ms
    end

    def close
      # @fluent_logger.close
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

