# frozen_string_literal: true

class CmdConsole
  module Helpers
    module BaseHelpers
      extend self

      def silence_warnings
        old_verbose = $VERBOSE
        $VERBOSE = nil
        begin
          yield
        ensure
          $VERBOSE = old_verbose
        end
      end

      # Acts like send but ignores any methods defined below Object or Class in the
      # inheritance hierarchy.
      # This is required to introspect methods on objects like Net::HTTP::Get that
      # have overridden the `method` method.
      def safe_send(obj, method, *args, &block)
        (obj.is_a?(Module) ? Module : Object).instance_method(method)
          .bind(obj).call(*args, &block)
      end

      def find_command(name, set = CmdConsole::Commands)
        command_match = set.find do |_, command|
          (listing = command.options[:listing]) == name && !listing.nil?
        end
        command_match.last if command_match
      end

      def not_a_real_file?(file)
        file =~ /^(\(.*\))$|^<.*>$/ || file =~ /__unknown__/ || file == "" || file == "-e"
      end

      def use_ansi_codes?
        CmdConsole::Helpers::Platform.windows_ansi? ||
          ((term = CmdConsole::Env['TERM']) && term != "dumb")
      end

      def colorize_code(code)
        SyntaxHighlighter.highlight(code)
      end

      def highlight(string, regexp, highlight_color = :bright_yellow)
        string.gsub(regexp) do |match|
          "<#{highlight_color}>#{match}</#{highlight_color}>"
        end
      end

      # formatting
      def heading(text)
        text = "#{text}\n--"
        "\e[1m#{text}\e[0m"
      end
    end
  end
end