# frozen_string_literal: true

require_relative 'response'
require_relative 'commands'

# execute commands based on input from client
class ClientHandler
  include Response
  include Commands

  attr_reader :client, :master, :replication_id, :offset, :store, :replicas

  def initialize(client, master, replication_id, offset, store, replicas) # rubocop:disable Metrics/ParameterLists
    @client = client
    @master = master
    @replication_id = replication_id
    @offset = offset
    # TODO: parent class & store state
    @store = store
    @replicas = replicas
  end

  def execute_command(commands) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
    commands.each_with_index do |input, index|
      case input.upcase
      when PING_COMMAND
        respond_to_ping
      when ECHO_COMMAND
        respond_to_echo(commands[index + 1])
      when SET_COMMAND
        exp = expiry?(commands[index + 3]) ? commands[index + 4] : nil

        # update replicas
        update_replicas(commands) if master?

        set_value(commands[index + 1], commands[index + 2], exp)
      when GET_COMMAND
        resp = get_value(commands[index + 1])
        client.write(resp)
      when INFO_COMMAND
        respond_to_info(commands[index + 1])
      when REPLCONF_COMMAND
        client.write(generate_simple_string('OK'))
      when PSYNC_COMMAND
        # add client to replicas: ideally this should be done after RDB has been loaded by replica
        replicas << client if master?

        client.write(generate_simple_string("FULLRESYNC #{replication_id} #{offset}"))
        # send RDS file
        res = "$#{decoded_hex_rdb.length}#{CRLF}#{decoded_hex_rdb}"
        client.write(res)
      end
    end
  end

  private

  def respond_to_ping
    # respond to PING command
    client.write(generate_simple_string('PONG'))
  end

  def respond_to_echo(argument)
    # respond to ECHO command
    response = generate_bulk_string(argument)
    client.write(response)
  end

  def set_value(key, value, exp)
    # respond to SET command
    exp_at = exp.nil? ? nil : (exp.to_i / 1000.0).to_f + Time.now.to_f
    store[key] = { value: value, exp: exp_at }

    client.write(generate_simple_string('OK'))
  end

  def get_value(key)
    # respond to GET command
    val = store.fetch(key, nil)

    return null_bulk_string if val.nil?

    if val[:exp] && (Time.now.to_f > val[:exp])
      store.delete(key)

      return null_bulk_string
    end

    generate_bulk_string(val[:value])
  end

  def expiry?(input)
    input&.upcase == 'PX'
  end

  def respond_to_info(parameter)
    response = replication_info if parameter == 'replication'

    client.write(generate_bulk_string(response))
  end

  def replication_info
    # master?
    role = master? ? 'master' : 'slave'
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

  def master?
    @master[:host].nil? && @master[:port].nil?
  end

  def update_replicas(inputs)
    replicas.each do |client|
      client.write(generate_resp_array([inputs[0], inputs[1], inputs[2]]))
    end
  end
end
