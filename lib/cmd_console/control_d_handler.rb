# frozen_string_literal: true

class CmdConsole
  # @api private
  # @since v0.13.0
  module ControlDHandler
    # Deal with the ^D key being pressed. Different behaviour in different
    # cases:
    #   1. In an expression behave like `!` command.
    #   2. At top-level session behave like `exit` command.
    #   3. In a nested session behave like `cd ..`.
    def self.default(pry_instance)
      throw(:breakout)
    end
  end
end
