# frozen_string_literal: true

require 'socket'

# Redis server
class YourRedisServer
  PING_COMMAND = 'PING'

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

  def handle_client(client)
    # read input: []
    line = client.readpartial(1024).upcase.chomp
    inputs = line.split(/[\r\n]+/)

    inputs.each do |input|
      # respond to PING command
      client.puts("+PONG\r\n") if input == PING_COMMAND
    end
  rescue EOFError => e
    # delete client
    @clients.delete(client)
    # close connection
    client.close
  end
end

YourRedisServer.new(6379).start
