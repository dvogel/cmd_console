# frozen_string_literal: true

require 'stringio'
require 'pathname'

class CmdConsole
  LOCAL_RC_FILE = "./.pryrc".freeze

  # @return [Boolean] true if this Ruby supports safe levels and tainting,
  #  to guard against using deprecated or unsupported features
  HAS_SAFE_LEVEL = (
    RUBY_ENGINE == 'ruby' &&
    Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7')
  )

  class << self
    extend CmdConsole::Forwardable
    attr_accessor :custom_completions
    attr_accessor :current_line
    attr_accessor :line_buffer
    attr_accessor :eval_path
    attr_accessor :cli
    attr_accessor :last_internal_error
    attr_accessor :unrescued_exceptions

    #
    # @example
    #  CmdConsole.configure do |config|
    #     config.eager_load! # optional
    #     config.input =     # ..
    #     config.foo = 2
    #  end
    #
    # @yield [config]
    #   Yields a block with {CmdConsole.config} as its argument.
    #
    def configure
      yield config
    end
  end

  #
  # @return [CmdConsole::Config]
  #  Returns a value store for an instance of CmdConsole running on the current thread.
  #
  def self.current
    Thread.current[:__pry__] ||= {}
  end

  # Expand a file to its canonical name (following symlinks as appropriate)
  def self.real_path_to(file)
    Pathname.new(File.expand_path(file)).realpath.to_s
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  # Trap interrupts on jruby, and make them behave like MRI so we can
  # catch them.
  def self.load_traps
    if CmdConsole::Helpers::Platform.jruby?
      trap('INT') { raise Interrupt }
    end
  end

  def self.load_win32console
    require 'win32console'
    # The mswin and mingw versions of pry require win32console, so this should
    # only fail on jruby (where win32console doesn't work).
    # Instead we'll recommend ansicon, which does.
  rescue LoadError
    warn <<-WARNING if CmdConsole.config.windows_console_warning
For a better CmdConsole experience on Windows, please use ansicon:
  https://github.com/adoxa/ansicon
If you use an alternative to ansicon and don't want to see this warning again,
you can add "CmdConsole.config.windows_console_warning = false" to your pryrc.
    WARNING
  end

  # Do basic setup for initial session including: loading pryrc,
  # requires, and history.
  def self.initial_session_setup
    return unless initial_session?

    @initial_session = false
  end

  def self.final_session_setup
    return if @session_finalized

    @session_finalized = true
    load_history if CmdConsole.config.history_load
    load_win32console if Helpers::Platform.windows? && !Helpers::Platform.windows_ansi?
  end

  # Load Readline history if required.
  def self.load_history
    CmdConsole.history.load
  end

  # @return [Boolean] Whether this is the first time a CmdConsole session has
  #   been started since loading the CmdConsole class.
  def self.initial_session?
    @initial_session
  end

  def self.auto_resize!
    CmdConsole.config.input # by default, load Readline

    if !defined?(Readline) || CmdConsole.config.input != Readline
      warn "Sorry, you must be using Readline for CmdConsole.auto_resize! to work."
      return
    end

    if Readline::VERSION =~ /edit/i
      warn(<<-WARN)
Readline version #{Readline::VERSION} detected - will not auto_resize! correctly.
  For the fix, use GNU Readline instead:
  https://github.com/guard/guard/wiki/Add-Readline-support-to-Ruby-on-Mac-OS-X
      WARN
      return
    end

    trap :WINCH do
      begin
        Readline.set_screen_size(*output.size)
      rescue StandardError => e
        warn "\nCmdConsole.auto_resize!'s Readline.set_screen_size failed: #{e}"
      end
      begin
        Readline.refresh_line
      rescue StandardError => e
        warn "\nCmdConsole.auto_resize!'s Readline.refresh_line failed: #{e}"
      end
    end
  end

  # Set all the configurable options back to their default values
  def self.reset_defaults
    @initial_session = true
    @session_finalized = nil

    self.unrescued_exceptions = [::SystemExit, ::SignalException, CmdConsole::TooSafeException]
    self.cli = false
    self.current_line = 1
    self.line_buffer = [""]
    self.eval_path = "(pry)"
  end

  # Basic initialization.
  def self.init
    reset_defaults
  end

  def self.in_critical_section?
    Thread.current[:pry_critical_section] ||= 0
    Thread.current[:pry_critical_section] > 0
  end

  def self.critical_section
    Thread.current[:pry_critical_section] ||= 0
    Thread.current[:pry_critical_section] += 1
    yield
  ensure
    Thread.current[:pry_critical_section] -= 1
  end
end

CmdConsole.init
