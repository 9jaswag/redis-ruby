# frozen_string_literal: true

require 'socket'
require_relative 'parser'

# Redis server
class YourRedisServer
  PING_COMMAND = 'PING'
  ECHO_COMMAND = 'ECHO'
  CRLF = "\r\n"

  def initialize(port)
    @port = port
    # instantiate new TCP Server
    @server = TCPServer.new(@port)
    # list of clients
    @clients = []
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

  def handle_client(client) # rubocop:disable Metrics/MethodLength
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
    client.puts("+PONG\r\n")
  end

  def respond_to_echo(client, argument)
    # respond to ECHO command
    response = "$#{encode_string(argument.length)}#{encode_string(argument)}"
    client.puts(response)
  end

  def encode_string(string)
    "#{string}#{CRLF}"
  end
end

YourRedisServer.new(6379).start
