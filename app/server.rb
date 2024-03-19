# frozen_string_literal: true

require 'socket'
require_relative 'parser'

# Redis server
class YourRedisServer
  PING_COMMAND = 'PING'
  ECHO_COMMAND = 'ECHO'
  SET_COMMAND = 'SET'
  GET_COMMAND = 'GET'
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

  def handle_client(client) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
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
        set_value(client, inputs[index + 1], inputs[index + 2])
      when GET_COMMAND
        get_value(client, inputs[index + 1])
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

  def set_value(client, key, value)
    # respond to SET command
    @store[key] = value

    client.puts("+OK#{CRLF}")
  end

  def get_value(client, key)
    # respond to GET command
    val = @store.fetch(key, nil)

    return "$-1#{CRLF}" if val.nil?

    response = encode_string(val)
    client.puts(response)
  end

  def encode_string(string)
    "$#{string.length}#{CRLF}#{string}#{CRLF}"
  end
end

YourRedisServer.new(6379).start
