# frozen_string_literal: true

require 'socket'
require 'date'
require_relative 'parser'
require_relative 'response'
require_relative 'commands'

# Redis server
class YourRedisServer # rubocop:disable Metrics/ClassLength
  include Response
  include Commands

  def initialize(port, master_host, master_port)
    @port = port
    # instantiate new TCP Server
    @server = TCPServer.new(@port)
    # list of clients
    @clients = []
    # store
    @store = {}

    # host & port the master replica is running on
    @master = { host: master_host, port: master_port }
    @replication_id = replication_id
    @offset = offset

    # handshake
    perform_handshake
  end

  def start # rubocop:disable Metrics/MethodLength
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    puts('Logs from your program will appear here!')

    loop do
      # accept multiple connections using event loop pattern
      # have file descriptors, use IO.select to select items available to be worked on
      # this way the code is non-blockiing
      fds_to_watch = [@server, *@clients]
      item_ready_to_read, = IO.select(fds_to_watch)

      item_ready_to_read.each do |item|
        # if new client is ready to connect
        if item == @server
          @clients << @server.accept

          next
        end

        # if it's not the server, its a client that wants to send new info
        handle_client(item)
      end
    end
  end

  private

  def handle_client(client) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
    # read input: []
    line = client.readpartial(1024).chomp
    # parse input
    inputs = Parser.parse(line)

    inputs.each_with_index do |input, index|
      case input.upcase
      when PING_COMMAND
        respond_to_ping(client)
      when ECHO_COMMAND
        respond_to_echo(client, inputs[index + 1])
      when SET_COMMAND
        exp = expiry?(inputs[index + 3]) ? inputs[index + 4] : nil
        set_value(client, inputs[index + 1], inputs[index + 2], exp)
      when GET_COMMAND
        resp = get_value(inputs[index + 1])
        client.puts(resp)
      when INFO_COMMAND
        respond_to_info(client, inputs[index + 1])
      when REPLCONF_COMMAND
        client.puts(generate_simple_string('OK'))
      when PSYNC_COMMAND
        client.puts(generate_simple_string('FULLRESYNC * 0'))
      end
    end
  rescue EOFError
    # delete client
    @clients.delete(client)
    # close connection
    client.close
  end

  def respond_to_ping(client)
    # respond to PING command
    client.puts(generate_simple_string('PONG'))
  end

  def respond_to_echo(client, argument)
    # respond to ECHO command
    response = generate_bulk_string(argument)
    client.puts(response)
  end

  def set_value(client, key, value, exp)
    # respond to SET command
    exp_at = exp.nil? ? nil : (exp.to_i / 1000.0).to_f + Time.now.to_f
    @store[key] = { value: value, exp: exp_at }

    client.puts(generate_simple_string('OK'))
  end

  def get_value(key)
    # respond to GET command
    val = @store.fetch(key, nil)

    return null_bulk_string if val.nil?

    if val[:exp] && (Time.now.to_f > val[:exp])
      @store.delete(key)

      return null_bulk_string
    end

    generate_bulk_string(val[:value])
  end

  def expiry?(input)
    input&.upcase == 'PX'
  end

  def respond_to_info(client, parameter)
    response = replication_info if parameter == 'replication'

    client.puts(generate_bulk_string(response))
  end

  def replication_info
    role = @master[:port].nil? ? 'master' : 'slave'
    resp = <<-REPLICATION
    role:#{role}
    REPLICATION

    resp = resp.strip
    resp += "\nmaster_replid:#{@replication_id}" if @replication_id
    resp += "\nmaster_repl_offset:#{@offset}" if @offset

    resp
  end

  def replication_id
    '8371b4fb1155b71f4a04d3e1bc3e18c4a990aeeb'
  end

  def offset
    0
  end

  def master?
    @master[:host].nil? && @master[:port].nil?
  end

  def perform_handshake
    return if master?

    # connect to master
    master = TCPSocket.open(@master[:host], @master[:port])
    resp = generate_resp_array(['ping'])

    # send PING response
    master.puts(resp)

    # send REPLCONF response
    listening_port = "REPLCONF listening-port #{@port}".split(' ')
    master.puts(generate_resp_array(listening_port))

    # send REPLCONF response
    capabilities = 'REPLCONF capa psync2'.split(' ')
    master.puts(generate_resp_array(capabilities))

    # send PSYNC response
    psync = 'PSYNC ? -1'.split(' ')
    master.puts(generate_resp_array(psync))
  end
end

index = ARGV.index('--port')
port = index.nil? ? 6379 : ARGV[index + 1].to_i
master_index = ARGV.index('--replicaof')
master_host = master_index.nil? ? nil : ARGV[master_index + 1].to_i
master_port = master_index.nil? ? nil : ARGV[master_index + 2].to_i

YourRedisServer.new(port, master_host, master_port).start
