#! /usr/bin/env ruby
#
#   check-mongodb-query-count.rb
#
# DESCRIPTION:
#   Check how many documents are returned by a MongoDB query.
#
# OUTPUT:
#   Plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: mongo
#   gem: bson
#   gem: bson_ext
#   gem: json
#
# USAGE:
#   # Check MongoDB collection "logs" for critical events
#   ./check-mongodb-query-count.rb --user sensu --pass sensu --database test --collection logs
#     --query '{"level":"CRITICAL"}'
#     --minutes-previous 5
#     -w 0 -c 10 --include-results
#
# NOTES:
#   Ruby is shit.
#
# LICENSE:
#   Copyright 2019 github.com/boutetnico
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'mongo'
require 'json'
include Mongo

#
# Mongodb
#

class MongoDBQueryCount < Sensu::Plugin::Check::CLI
  option :host,
         description: 'MongoDB host',
         long: '--host HOST',
         default: 'localhost'

  option :port,
         description: 'MongoDB port',
         long: '--port PORT',
         default: 27_017

  option :user,
         description: 'MongoDB user',
         long: '--user USER',
         default: nil

  option :password,
         description: 'MongoDB password',
         long: '--password PASSWORD',
         default: nil

  option :ssl,
         description: 'Connect using SSL',
         long: '--ssl',
         default: false

  option :ssl_cert,
         description: 'The certificate file used to identify the local connection against mongod',
         long: '--ssl-cert SSL_CERT',
         default: ''

  option :ssl_key,
         description: 'The private key used to identify the local connection against mongod',
         long: '--ssl-key SSL_KEY',
         default: ''

  option :ssl_ca_cert,
         description: 'The set of concatenated CA certificates, which are used to validate certificates passed from the other end of the connection',
         long: '--ssl-ca-cert SSL_CA_CERT',
         default: ''

  option :ssl_verify,
         description: 'Whether or not to do peer certification validation',
         long: '--ssl-verify',
         default: false

  option :debug,
         description: 'Enable debug',
         long: '--debug',
         default: false

  option :database,
         description: 'Database to perform query on',
         short: '-d DATABASE',
         long: '--database DATABASE',
         required: true

  option :collection,
         description: 'Collection to perform query on',
         short: '-C COLLECTION',
         long: '--collection COLLECTION',
         required: true

  option :query,
         description: 'Query to perform',
         short: '-q QUERY',
         long: '--query QUERY',
         required: true

  option :warn,
         short: '-w N',
         long: '--warn N',
         description: 'Result count WARNING threshold',
         proc: proc(&:to_i),
         default: 0

  option :crit,
         short: '-c N',
         long: '--crit N',
         description: 'Result count CRITICAL threshold',
         proc: proc(&:to_i),
         default: 0

  option :invert,
         long: '--invert',
         description: 'Invert thresholds',
         boolean: true

  option :date_field,
         description: 'Field to use instead of "date" for query.',
         long: '--date-field FIELD_NAME',
         default: 'date'

  option :minutes_previous,
         description: 'Minutes before offset to check date field against query.',
         long: '--minutes-previous MINUTES_PREVIOUS',
         proc: proc(&:to_i),
         default: 0

  option :hours_previous,
         description: 'Hours before offset to check date field against query.',
         long: '--hours-previous HOURS_PREVIOUS',
         proc: proc(&:to_i),
         default: 0

  option :days_previous,
         description: 'Days before offset to check date field against query.',
         long: '--days-previous DAYS_PREVIOUS',
         proc: proc(&:to_i),
         default: 0

  option :weeks_previous,
         description: 'Weeks before offset to check date field against query.',
         long: '--weeks-previous WEEKS_PREVIOUS',
         proc: proc(&:to_i),
         default: 0

  option :months_previous,
         description: 'Months before offset to check date field against query.',
         long: '--months-previous MONTHS_PREVIOUS',
         proc: proc(&:to_i),
         default: 0

  option :include_results,
         long: '--include-results',
         description: 'Include results in response',
         boolean: false

  def connect_mongo_db
    address_str = "#{config[:host]}:#{config[:port]}"
    client_opts = {}
    client_opts[:database] = config[:database]
    unless config[:user].nil?
      client_opts[:user] = config[:user]
      client_opts[:password] = config[:password]
    end
    if config[:ssl]
      client_opts[:ssl] = true
      client_opts[:ssl_cert] = config[:ssl_cert]
      client_opts[:ssl_key] = config[:ssl_key]
      client_opts[:ssl_ca_cert] = config[:ssl_ca_cert]
      client_opts[:ssl_verify] = config[:ssl_verify]
    end
    mongo_client = Mongo::Client.new([address_str], client_opts)
    @db = mongo_client.database
  end

  def query_mongo
    collection = @db[config[:collection]]
    begin
      query = JSON.parse(config[:query])
    rescue JSON::ParserError
      unknown 'Failed to parse query. Provide a valid JSON array.'
    end

    start_time = Time.now.utc.to_i
    if config[:minutes_previous] != 0
      start_time -= (config[:minutes_previous] * 60)
    end
    if config[:hours_previous] != 0
      start_time -= (config[:hours_previous] * 60 * 60)
    end
    if config[:days_previous] != 0
      start_time -= (config[:days_previous] * 60 * 60 * 24)
    end
    if config[:weeks_previous] != 0
      start_time -= (config[:weeks_previous] * 60 * 60 * 24 * 7)
    end
    if config[:months_previous] != 0
      start_time -= (config[:months_previous] * 60 * 60 * 24 * 31)
    end

    query[config[:date_field]] = { '$gte' => Time.at(start_time).to_datetime }

    if config[:debug]
      puts 'Query: ' + query.inspect
    end

    collection.find(query)
  end

  def print_results(results)
    count = results.count

    if config[:include_results]
      results.each { |document| puts document.inspect }
    end

    if config[:invert]
      if count < config[:crit]
        critical "Query count (#{count}) was below critical threshold."
      elsif count < config[:warn]
        warning "Query count (#{count}) was below warning threshold."
      else
        ok "Query count (#{count}) was ok"
      end
    elsif count > config[:crit]
      critical "Query count (#{count}) was above critical threshold."
    elsif count > config[:warn]
      warning "Query count (#{count}) was above warning threshold."
    else
      ok "Query count (#{count}) was ok"
    end
  end

  def run
    Mongo::Logger.logger.level = Logger::FATAL
    @debug = config[:debug]
    if @debug
      Mongo::Logger.logger.level = Logger::DEBUG
      config_debug = config.clone
      config_debug[:password] = '***'
      puts 'Arguments: ' + config_debug.inspect
    end

    connect_mongo_db

    results = query_mongo

    print_results(results)
  end
end
