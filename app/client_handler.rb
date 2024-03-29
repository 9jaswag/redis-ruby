# frozen_string_literal: true

require_relative 'response'
require_relative 'commands'
require_relative 'command'

# execute commands based on input from client
class ClientHandler # rubocop:disable Metrics/ClassLength
  include Response
  include Commands

  attr_reader :client, :master_server, :client_is_master, :replication_id, :offset, :store, :replicas

  def initialize(client, master_server, client_is_master, replication_id, offset, store, replicas) # rubocop:disable Metrics/ParameterLists
    @client = client
    @master_server = master_server
    @client_is_master = client_is_master
    @replication_id = replication_id
    @offset = offset
    @store = store
    @replicas = replicas
  end

  def execute_command(input)
    command = commands.find { |cmd| cmd.match?(input) }
    response = send(command_handlers[command.name], input) if command

    client.write(response) unless response.nil?
  end

  private

  def command_consts
    Commands.constants.map { |c| Commands.const_get(c) }
  end

  def commands
    command_consts.map { |c| Command.new(c) }
  end

  def command_handlers
    {}.tap do |handlers|
      command_consts.each do |command|
        handlers[command] = "respond_to_#{command.downcase}".to_sym
      end
    end
  end

  def respond_to_ping(_input)
    # respond to PING command
    generate_simple_string('PONG') unless client_is_master
  end

  def respond_to_echo(input)
    # respond to ECHO command
    argument = input.split[1]
    generate_bulk_string(argument)
  end

  def respond_to_set(input)
    # respond to SET command
    commands = input.split
    exp = expiry?(commands[3]) ? commands[4] : nil
    set_value(commands[1..2], exp)
  end

  def respond_to_get(command)
    # respond to GET command
    key = command.split[1]
    val = store.fetch(key, nil)

    return null_bulk_string if val.nil?

    if val[:exp] && (Time.now.to_f > val[:exp])
      store.delete(key)

      return null_bulk_string
    end

    generate_bulk_string(val[:value])
  end

  def respond_to_info(command)
    parameter = command.split[1]
    response = replication_info if parameter == 'replication'

    generate_bulk_string(response)
  end

  def respond_to_psync(_command)
    # executed in master server
    # store client as a replica: ideally this should be done after RDB has been loaded by replica
    replicas << client if master_server

    client.write(generate_simple_string("FULLRESYNC #{replication_id} #{offset}"))

    # send RDB file to replica
    "$#{decoded_hex_rdb.length}#{CRLF}#{decoded_hex_rdb}"
  end

  def respond_to_replconf(command)
    type = command.split[1]
    return generate_resp_array(['REPLCONF', 'ACK', offset.to_s]) if type == REPLCONF_GETACK_COMMAND

    generate_simple_string('OK')
  end

  def respond_to_wait(command)
    _, _numreplicas, _timeout = command.split

    generate_simple_integer(replicas.size)
  end

  def set_value((key, value), exp)
    # respond to SET command
    exp_at = exp.nil? ? nil : update_current_time_by_ms(exp)
    store[key] = { value: value, exp: exp_at }

    # update replicas if running server is master server
    update_replicas(SET_COMMAND, key, value)

    # only send response if client == master...running on master port
    generate_simple_string('OK') unless client_is_master
  end

  def expiry?(input)
    input&.upcase == 'PX'
  end

  def replication_info
    role = master_server ? 'master' : 'slave'
    resp = <<-REPLICATION
      role:#{role}
    REPLICATION

    resp = resp.strip
    resp += "\nmaster_replid:#{replication_id}" if replication_id
    resp += "\nmaster_repl_offset:#{offset}" if offset

    resp
  end

  def empty_hex_rdb
    '524544495330303131fa0972656469732d76657205372e322e30fa0a72656469732d62697473c040fa056374'\
    '696d65c26d08bc65fa08757365642d6d656dc2b0c41000fa08616f662d62617365c000fff06e3bfec0ff5aa2'
  end

  def decoded_hex_rdb
    [empty_hex_rdb].pack('H*')
  end

  def update_replicas(command, key, value)
    return unless master_server

    replicas.each do |client|
      client.write(generate_resp_array([command, key, value]))

      # client_ack = client.gets
      # update acknowledge count
    end
  end

  def update_current_time_by_ms(duration)
    (duration.to_i / 1000.0).to_f + Time.now.to_f
  end
end
