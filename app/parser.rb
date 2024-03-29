# frozen_string_literal: true

# Class to parse Redis RESP string
class Parser
  def self.parse(string)
    sanitised_string = extract_after_first_special_character(string)

    # pp '--sani', sanitised_string

    case sanitised_string[0]
    when '*'
      parse_array(string)
    when '$'
      parse_bulk_string(string)
    end
  end

  # Arrays: https://redis.io/docs/reference/protocol-spec/#arrays
  def self.parse_array(input) # rubocop:disable Metrics/MethodLength
    [].tap do |result|
      # Split input string by "\r\n" to get individual elements
      elements = split_string_safe(input)

      # Loop through each element
      until elements.empty?
        element = elements.shift

        # Check the type of the element
        case element[0]
        when '*' # Array
          count = element[1..].to_i
          result << parse_array_elements(count, elements)
        end
      end
    end
  end

  # Bulk String: https://redis.io/docs/reference/protocol-spec/#bulk-strings
  def self.parse_bulk_string(input) # rubocop:disable Metrics/MethodLength
    elements = split_string_safe(input)
    result = []

    until elements.empty?
      element = elements.shift
      res = []

      case element[0]
      when '$'
        count = element[1..].to_i
        command = elements.shift&.strip
        next if command&.start_with?('REDIS')

        res << command

        while res.length < count
          comm = elements.shift&.strip
          break if comm.nil?

          next if comm.start_with?('$')

          res << comm
        end
      end

      result << res.join(' ') unless res.empty?
    end

    result
  end

  def self.parse_array_elements(count, elements)
    command = ''
    count.times do
      item = elements.shift
      command += "#{parse_element(elements, item)} " if item
    end
    command.strip
  end

  def self.parse_element(elements, element)
    case element[0]
    when '$' # Word
      length = element[1..].to_i
      elements.shift[0...length] # Extract the word and skip it
    when ':' # Number
      element[1..].to_i # Extract the number
    else
      element # Return the element as is
    end
  end

  def self.extract_after_first_special_character(string)
    index = find_index_safe(string)
    return string unless index

    string[index..]
  end
end

def find_index_safe(string, max_retries = 3) # rubocop:disable Metrics/MethodLength
  retries = 0
  begin
    index = string.index(/[$*]/)
  rescue ArgumentError
    # Handle invalid byte sequence error
    return nil unless retries < max_retries

    # Remove invalid bytes and retry the operation
    cleaned_string = string.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    string = cleaned_string
    retries += 1
    retry

    # Reached maximum retries, return nil
  end

  index
end

def split_string_safe(string, max_retries = 3) # rubocop:disable Metrics/MethodLength
  retries = 0
  begin
    parts = string.split("\r\n")
  rescue ArgumentError
    # Handle invalid byte sequence error
    return [] unless retries < max_retries

    # Remove invalid bytes and retry the operation
    cleaned_string = string.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    string = cleaned_string
    retries += 1
    retry

    # Reached maximum retries, return nil
  end

  parts
end

# def self.parse_array(string)
#   matches = string.scan(/\$\d+\r\n([^\r\n]+)|:(\d+)/).flatten.compact
#   matches.map! { |match| match.start_with?(':') ? match[1..] : match }
# end

# def self.parse_bulk_string(string)
#   string.scan(/\$\d+\r\n([^\r\n]+)|:(\d+)/).flatten.compact
# end
