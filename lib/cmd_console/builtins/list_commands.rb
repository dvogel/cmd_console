# frozen_string_literal: true

class CmdConsole
  class Command
    class ListCommands < CmdConsole::ClassCommand
      match 'list-commands'
      group 'Built-ins'
      description 'List all of the other commands'

      # def options(opt)
      #   opt
      # end

      def process
        CmdConsole::Commands.each do |cmd_name, cmd_klass|
          output.puts cmd_name
        end
      end
    end

    CmdConsole::Commands.add_command(CmdConsole::Command::ListCommands)
  end
end

