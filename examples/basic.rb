# frozen_string_literal: true

require 'cmd_console'

CmdConsole::REPL.start({
  commands: CmdConsole::Commands,
})
