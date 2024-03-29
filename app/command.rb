# frozen_string_literal: true

# Matches a Redis command
class Command
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def match?(input)
    input.match?(regex)
  end

  private

  def regex
    /\b#{Regexp.escape(name)}\b/i
  end
end
