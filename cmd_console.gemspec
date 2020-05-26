Gem::Specification.new do |s|
  s.name = "cmd_console"
  s.version = "0.0.1"
  s.date = "2020-05-22"
  s.authors = "drewpvogel@gmail.com"
  s.summary = "A command console for implementing interactive command lines."
  s.files = [
    "Gemfile",
    "LICENSE",
    "lib/cmd_console.rb",
    "lib/cmd_console/control_d_handler.rb",
    "lib/cmd_console/block_command.rb",
    "lib/cmd_console/env.rb",
    "lib/cmd_console/command.rb",
    "lib/cmd_console/cmd_console_instance.rb",
    "lib/cmd_console/exceptions.rb",
    "lib/cmd_console/slop/option.rb",
    "lib/cmd_console/slop/commands.rb",
    "lib/cmd_console/repl.rb",
    "lib/cmd_console/forwardable.rb",
    "lib/cmd_console/exception_handler.rb",
    "lib/cmd_console/helpers.rb",
    "lib/cmd_console/slop.rb",
    "lib/cmd_console/cmd_console_class.rb",
    "lib/cmd_console/class_command.rb",
    "lib/cmd_console/history.rb",
    "lib/cmd_console/pager.rb",
    "lib/cmd_console/output.rb",
    "lib/cmd_console/input_lock.rb",
    "lib/cmd_console/builtins/help.rb",
    "lib/cmd_console/ring.rb",
    "lib/cmd_console/command_set.rb",
    "lib/cmd_console/helpers/base_helpers.rb",
    "lib/cmd_console/helpers/table.rb",
    "lib/cmd_console/helpers/options_helpers.rb",
    "lib/cmd_console/helpers/platform.rb",
    "lib/cmd_console/helpers/documentation_helpers.rb",
    "lib/cmd_console/helpers/command_helpers.rb",
    "lib/cmd_console/helpers/text.rb",
    "lib/cmd_console/config/memoized_value.rb",
    "lib/cmd_console/config/value.rb",
    "lib/cmd_console/config/lazy_value.rb",
    "lib/cmd_console/config/attributable.rb",
    "lib/cmd_console/config.rb",
  ]
  s.require_paths = ["lib"]
end
