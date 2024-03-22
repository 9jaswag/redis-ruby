# frozen_string_literal: true

# Encodes strings and arrays into RESP objects
module Response
  CRLF = "\r\n"

  def generate_bulk_string(string)
    "$#{string.length}#{CRLF}#{string}#{CRLF}"
  end

  def generate_resp_array(value)
    # TODO: handle nested arrs
    res = "*#{value.size}#{CRLF}"
    value.each do |val|
      if val.instance_of?(Integer)
        res += ":#{val}#{CRLF}"
        next
      end

      res += generate_bulk_string(val)
    end

    res
  end

  def null_bulk_string
    "$-1#{CRLF}"
  end

  def null_resp_array
    "*-1#{CRLF}"
  end

  def pong_string
    "+PONG#{CRLF}"
  end

  def ok_string
    "+OK#{CRLF}"
  end
end
