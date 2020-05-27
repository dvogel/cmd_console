# frozen_string_literal: true

require_relative './cmd_console/forwardable'
require_relative './cmd_console/last_exception'

require_relative './cmd_console/helpers/base_helpers'
require_relative './cmd_console/helpers'

require_relative './cmd_console/exceptions'
require_relative './cmd_console/command'
require_relative './cmd_console/class_command'
require_relative './cmd_console/block_command'
require_relative './cmd_console/command_set'
require_relative './cmd_console/history'
require_relative './cmd_console/repl'
require_relative './cmd_console/exception_handler'
require_relative './cmd_console/control_d_handler'
require_relative './cmd_console/env'

require 'cmd_console/output'
require 'cmd_console/input_lock'
require 'cmd_console/repl'
require 'cmd_console/ring'
require 'cmd_console/slop'

CmdConsole::Commands = CmdConsole::CommandSet.new unless defined?(CmdConsole::Commands)

require_relative './cmd_console/config/attributable'
require_relative './cmd_console/config/lazy_value'
require_relative './cmd_console/config/memoized_value'
require_relative './cmd_console/config/value'
require_relative './cmd_console/config'

require 'cmd_console/cmd_console_class'
require 'cmd_console/cmd_console_instance'
require 'cmd_console/pager'

require_relative './cmd_console/builtins/help'
