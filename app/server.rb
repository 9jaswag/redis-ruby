require "socket"

class YourRedisServer
  def initialize(port)
    @port = port
  end

  def start
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    puts("Logs from your program will appear here!")

    # instantiate new TCP Server
    server = TCPServer.new(@port)

    loop {
      # accept multiple connections
      Thread.new(server.accept) { |client| handle_client(client) }
    }
  end

  private

  def handle_client(client)
    # read input
    while line = client.gets
      input = line.upcase.chomp

      if input == "PING"
        # respond to PING command
        client.puts("+PONG\r\n")
      end
    end

    # close server
    client.close
  end
end

YourRedisServer.new(6379).start
