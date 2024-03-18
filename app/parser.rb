# frozen_string_literal: true

# Class to parse Redis RESP string
class Parser
  def self.parse(string)
    case string
    when /^\*/
      parse_array(string)
    when /^\$/
      parse_bulk_string(string)
    end
  end

  # Arrays https://redis.io/docs/reference/protocol-spec/#arrays
  def self.parse_array(string)
    matches = string.scan(/\$\d+\r\n([^\r\n]+)|:(\d+)/).flatten.compact
    matches.map! { |match| match.start_with?(':') ? match[1..] : match }
  end

  # Bulk String https://redis.io/docs/reference/protocol-spec/#bulk-strings
  def self.parse_bulk_string(string)
    string.scan(/\$\d+\r\n([^\r\n]+)|:(\d+)/).flatten.compact
  end
end
