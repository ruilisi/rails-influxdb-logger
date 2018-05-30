require 'spec_helper'
require 'tempfile'

class Time
  def to_ms # for convenience of comparing  timestamps
    (self.to_f * 1000.0).to_i
  end
end

module InfluxdbLogger
  module Logger
    attr_accessor :settings
  end
end

describe InfluxdbLogger::Logger do
  before do
    stub_const('Rails', Class.new) unless defined?(Rails)
    allow(Rails).to receive(:env).and_return('test')
    allow(Rails).to receive_message_chain(:application, :config, :log_level).and_return(:debug)
    allow(Rails).to receive_message_chain(:application, :config, :log_tags=)

    class MyLogger
      attr_accessor :log
      def initialize()
        @log = []
      end

      def post(tag, map)
      end

      def clear
        @log.clear
      end

      def close
      end

      def write_point(point)
        @log << point
      end

      def write_points(points, time_precision, rentention = nil)
        @log ||= []
        @log.concat(points)
      end
    end
    @my_logger = MyLogger.new
    allow(InfluxDB::Client).to receive(:new).and_return(@my_logger)
  end

  let(:series) { 'Request' }

  let(:log_tags) {
    {
      uuid: :uuid,
      foo: ->(request) { 'foo_value' }
    }
  }

  let(:settings) {
    {
      host: 'influxdb',
      database: 'paiyou',
      series: series,
      retry: 3,
      username: 'user',
      password: 'password',
      time_precision: 'ms'
    }
  }

  let(:logger) {
    InfluxdbLogger::Logger.new(log_tags: log_tags, settings: settings)
  }

  let(:request) {
    double('request', uuid: 'uuid_value')
  }

  describe 'logging' do

    describe 'basic' do
      it 'info' do
        # see Rails::Rack::compute_tags
        tags = log_tags.values.collect do |tag|
          case tag
          when Proc
            tag.call(request)
          when Symbol
            request.send(tag)
          else
            tag
          end
        end
        logger[:abc] = 'xyz'
        logger.tagged(tags) { logger.info('hello') }
        expect(@my_logger.log).to eq(
                                    [{
                                      series: series,
                                      timestamp: Time.now.to_ms,
                                      tags: {
                                        abc: 'xyz',
                                        uuid: 'uuid_value',
                                        foo: 'foo_value'
                                      },
                                      values: {
                                        message_type: 'String',
                                        message: 'hello',
                                        severity: 'INFO'
                                      }
                                    }])
        @my_logger.clear
        logger.tagged(tags) { logger.info('world'); logger.info('bye') }
        expect(@my_logger.log).to eq(
          [{
            series: series,
            timestamp: Time.now.to_ms,
            tags: {
              abc: 'xyz',
              uuid: 'uuid_value',
              foo: 'foo_value'
            },
            values: {
              message_type: 'String',
              message: 'world',
              severity: 'INFO'
            }
          }, {
            series: series,
            timestamp: Time.now.to_ms,
            tags: {
              abc: 'xyz',
              uuid: 'uuid_value',
              foo: 'foo_value'
            },
            values: {
              message_type: 'String',
              message: 'bye',
              severity: 'INFO'
            }
          }])
      end
    end

    describe 'frozen ascii-8bit string' do
      before do
        logger.instance_variable_set(:@messages_type, :string)
      end

      after do
        logger.instance_variable_set(:@messages_type, :array)
      end

      it 'join messages' do
        ascii = "\xe8\x8a\xb1".force_encoding('ascii-8bit').freeze
        logger.tagged([request]) {
          logger.info(ascii)
          logger.info('咲く')
        }
        expect(@my_logger.log[0][:values][:message]).to eq("花")
        expect(@my_logger.log[1][:values][:message]).to eq("咲く")
        expect(ascii.encoding).to eq(Encoding::ASCII_8BIT)
      end
    end

    describe 'Exception' do
      it 'output message, class, backtrace' do
        begin
          3 / 0
        rescue => e
          logger.tagged([request]) {
            logger.error(e)
          }
          expect(@my_logger.log[0][:values][:message]).to eq("divided by 0")
        end
      end
    end

    describe 'Object' do
      it 'output inspect' do
        x = Object.new
        logger.tagged([request]) {
          logger.info(x)
        }
        expect(@my_logger.log[0][:values][:message]).to eq(x.inspect)
      end
    end
  end

  describe "settings with ENV['INDUX_DB_URL']" do
    let(:influxdb_url) { 'http://influxdb:8086/paiyou?messages_type=string&severity_key=level&username=user&password=pass&time_precision=ms&series=Log&retry=3' }

      it "settings are properly set" do
        stub_const("ENV", {'INFLUXDB_URL' => influxdb_url })
        allow(InfluxdbLogger::InnerLogger).to receive(:new) do |settings|
          expect(settings).to eq({
            database: "paiyou",
            host: "influxdb",
            port: 8086,
            messages_type: "string",
            severity_key: "level",
            username: "user",
            password: "pass",
            series: "Log",
            time_precision: "ms",
            retry: 3,
            batch_size: 1000,
            interval: 1000
          })
          ActiveSupport::Logger.new(STDOUT)
        end
        InfluxdbLogger::Logger.new(settings: {})
    end
  end

  describe 'batch size', now: true do
    it 'inner logger write_points after every two messages if batch_size is set to 2' do
      logger = InfluxdbLogger::Logger.new(settings: settings, batch_size: 2)
      logger.info('message 1')
      expect(@my_logger.log.size).to eq 0
      logger.info('message 2')
      expect(@my_logger.log.size).to eq 2
      logger.info('message 3')
      expect(@my_logger.log.size).to eq 2
      logger.info('message 4')
      expect(@my_logger.log.size).to eq 4
    end
  end
end
