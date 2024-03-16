require "socket"

class YourRedisServer
  def initialize(port)
    @port = port
  end

  def start
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    puts("Logs from your program will appear here!")

    # instantiate new TCP server
    server = TCPServer.new(@port)
    # wait for client to connect
    client = server.accept

    # respond to PING command
    client.puts("+PONG\r\n")
    # close server
    client.close
  end
end

YourRedisServer.new(6379).start
