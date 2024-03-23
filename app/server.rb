# frozen_string_literal: true

require 'socket'
require 'date'
require_relative 'parser'
require_relative 'response'
require_relative 'commands'
require_relative 'client_handler'

# Redis server
class YourRedisServer
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
    @replicas = []
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
    line = client.readpartial(1024).chomp
    # parse input
    inputs = Parser.parse(line)

    ClientHandler.new(client, @master, @replication_id, @offset, @store, @replicas).execute_command(inputs)
  rescue EOFError
    # delete client
    @clients.delete(client)
    # close connection
    client.close
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

  # run by replica server
  def perform_handshake
    return if master?

    # connect to master
    master = TCPSocket.open(@master[:host], @master[:port])
    resp = generate_resp_array(['ping'])

    # send PING response
    master.write(resp)

    # send REPLCONF response
    listening_port = "REPLCONF listening-port #{@port}".split(' ')
    master.write(generate_resp_array(listening_port))

    # send REPLCONF response
    capabilities = 'REPLCONF capa psync2'.split(' ')
    master.write(generate_resp_array(capabilities))

    # send PSYNC response
    psync = 'PSYNC ? -1'.split(' ')
    master.write(generate_resp_array(psync))
  end
end

index = ARGV.index('--port')
port = index.nil? ? 6379 : ARGV[index + 1].to_i
master_index = ARGV.index('--replicaof')
master_host = master_index.nil? ? nil : ARGV[master_index + 1].to_i
master_port = master_index.nil? ? nil : ARGV[master_index + 2].to_i

YourRedisServer.new(port, master_host, master_port).start
