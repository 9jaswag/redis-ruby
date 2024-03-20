# frozen_string_literal: true

require 'socket'
require 'date'
require_relative 'parser'

# Redis server
class YourRedisServer
  PING_COMMAND = 'PING'
  ECHO_COMMAND = 'ECHO'
  SET_COMMAND = 'SET'
  GET_COMMAND = 'GET'
  INFO_COMMAND = 'INFO'
  CRLF = "\r\n"

  def initialize(port)
    @port = port
    # instantiate new TCP Server
    @server = TCPServer.new(@port)
    # list of clients
    @clients = []
    @store = {}
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
    client.puts("+PONG#{CRLF}")
  end

  def respond_to_echo(client, argument)
    # respond to ECHO command
    response = encode_string(argument)
    client.puts(response)
  end

  def set_value(client, key, value, exp)
    # respond to SET command
    exp_at = exp.nil? ? nil : (exp.to_i / 1000.0).to_f + Time.now.to_f
    @store[key] = { value: value, exp: exp_at }

    client.puts("+OK#{CRLF}")
  end

  def get_value(key)
    # respond to GET command
    val = @store.fetch(key, nil)

    return null_bulk_string if val.nil?

    if val[:exp] && (Time.now.to_f > val[:exp])
      @store.delete(key)

      return null_bulk_string
    end

    encode_string(val[:value])
  end

  def encode_string(string)
    "$#{string.length}#{CRLF}#{string}#{CRLF}"
  end

  def null_bulk_string
    "$-1#{CRLF}"
  end

  def expiry?(input)
    input&.upcase == 'PX'
  end

  def respond_to_info(client, parameter)
    response = replication_info.strip if parameter == 'replication'

    client.puts(encode_string(response))
  end

  def replication_info
    <<-REPLICATION
    role:master
    REPLICATION
  end
end

index = ARGV.index('--port')
port = index.nil? ? 6379 : ARGV[index + 1].to_i

YourRedisServer.new(port).start
