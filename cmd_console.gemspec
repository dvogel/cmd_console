Gem::Specification.new do |s|
  s.name = "cmd_console"
  s.version = "0.0.1"
  s.date = "2020-05-22"
  s.summary = "A command console for implementing interactive command lines."
  s.files = [
    "Gemfile",
    "VERSION",
    "lib/cmd_console.rb"
    "lib/cmd_console/command.rb",
    "lib/cmd_console/repl.rb",
    "lib/cmd_console/helpers.rb",
    "lib/cmd_console/input_lock.rb",
    "lib/cmd_console/builtins/list_commands.rb",
    "lib/cmd_console/helpers/base_helpers.rb",
    "lib/cmd_console/helpers/table.rb",
    "lib/cmd_console/helpers/options_helpers.rb",
    "lib/cmd_console/helpers/platform.rb",
    "lib/cmd_console/helpers/documentation_helpers.rb",
    "lib/cmd_console/helpers/command_helpers.rb",
    "lib/cmd_console/helpers/text.rb",
  ]
  s.require_paths = ["lib"]
end
