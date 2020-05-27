# frozen_string_literal: true

require 'cmd_console'
require 'readline'

history_file = File.join(File.dirname(__FILE__), 'history.txt')
puts "Should read history from #{history_file}"

history = CmdConsole::History.new(
  history: Readline::HISTORY,
  file_path: history_file,
)
history.load

CmdConsole::REPL.start({
  commands: CmdConsole::Commands,
  history: history,
  history_load: true,
  history_save: true,
})

