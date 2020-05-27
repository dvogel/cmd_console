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
    attr_accessor :quiet
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
  # @return [main]
  #   returns the special instance of Object, "main".
  #
  def self.main
    @main ||= TOPLEVEL_BINDING.eval "self"
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

  # Load any Ruby files specified with the -r flag on the command line.
  def self.load_requires
    CmdConsole.config.requires.each do |file|
      require file
    end
  end

  # Trap interrupts on jruby, and make them behave like MRI so we can
  # catch them.
  def self.load_traps
    trap('INT') { raise Interrupt }
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
    load_requires if CmdConsole.config.should_load_requires
    load_history if CmdConsole.config.history_load
    load_traps if CmdConsole.config.should_trap_interrupts
    load_win32console if Helpers::Platform.windows? && !Helpers::Platform.windows_ansi?
  end

  # Start a CmdConsole REPL.
  # This method also loads `pryrc` as necessary the first time it is invoked.
  # @param [Object, Binding] target The receiver of the CmdConsole session
  # @param [Hash] options
  # @option options (see CmdConsole#initialize)
  # @example
  #   CmdConsole.start(Object.new, :input => MyInput.new)
  def self.start(target = nil, options = {})
    return if CmdConsole::Env['DISABLE_PRY']
    if CmdConsole::Env['FAIL_PRY']
      raise 'You have FAIL_PRY set to true, which results in CmdConsole calls failing'
    end

    options = options.to_hash

    if in_critical_section?
      output.puts "ERROR: CmdConsole started inside CmdConsole."
      output.puts "This can happen if you have a binding.pry inside a #to_s " \
                  "or #inspect function."
      return
    end

    options[:target] = CmdConsole.binding_for(target || toplevel_binding)
    initial_session_setup
    final_session_setup

    # Unless we were given a backtrace, save the current one
    if options[:backtrace].nil?
      options[:backtrace] = caller

      # If CmdConsole was started via `binding.pry`, elide that from the backtrace
      if options[:backtrace].first =~ /pry.*core_extensions.*pry/
        options[:backtrace].shift
      end
    end

    driver = options[:driver] || CmdConsole::REPL

    # Enter the matrix
    driver.start(options)
  rescue CmdConsole::TooSafeException
    puts "ERROR: CmdConsole cannot work with $SAFE > 0"
    raise
  end

  # Execute the file through the REPL loop, non-interactively.
  # @param [String] file_name File name to load through the REPL.
  def self.load_file_through_repl(file_name)
    REPLFileLoader.new(file_name).load
  end

  #
  # An inspector that clips the output to `max_length` chars.
  # In case of > `max_length` chars the `#<Object...> notation is used.
  #
  # @param [Object] obj
  #   The object to view.
  #
  # @param [Hash] options
  # @option options [Integer] :max_length (60)
  #   The maximum number of chars before clipping occurs.
  #
  # @option options [Boolean] :id (false)
  #   Boolean to indicate whether or not a hex reprsentation of the object ID
  #   is attached to the return value when the length of inspect is greater than
  #   value of `:max_length`.
  #
  # @return [String]
  #   The string representation of `obj`.
  #
  def self.view_clip(obj, options = {})
    max = options.fetch :max_length, 60
    id = options.fetch :id, false
    if obj.is_a?(Module) && obj.name.to_s != "" && obj.name.to_s.length <= max
      obj.name.to_s
    elsif CmdConsole.main == obj
      # Special-case to support jruby. Fixed as of:
      # https://github.com/jruby/jruby/commit/d365ebd309cf9df3dde28f5eb36ea97056e0c039
      # we can drop in the future.
      obj.to_s
      # rubocop:disable Style/CaseEquality
    elsif CmdConsole.config.prompt_safe_contexts.any? { |v| v === obj } &&
          obj.inspect.length <= max
      # rubocop:enable Style/CaseEquality

      obj.inspect
    elsif id
      format("#<#{obj.class}:0x%<id>x>", id: obj.object_id << 1)
    else
      "#<#{obj.class}>"
    end
  rescue RescuableException
    "unknown"
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

  # Run a CmdConsole command from outside a session. The commands available are
  # those referenced by `CmdConsole.config.commands` (the default command set).
  # @param [String] command_string The CmdConsole command (including arguments,
  #   if any).
  # @param [Hash] options Optional named parameters.
  # @return [nil]
  # @option options [Object, Binding] :target The object to run the
  #   command under. Defaults to `TOPLEVEL_BINDING` (main).
  # @option options [Boolean] :show_output Whether to show command
  #   output. Defaults to true.
  # @example Run at top-level with no output.
  #   CmdConsole.run_command "ls"
  # @example Run under CmdConsole class, returning only public methods.
  #   CmdConsole.run_command "ls -m", :target => CmdConsole
  # @example Display command output.
  #   CmdConsole.run_command "ls -av", :show_output => true
  def self.run_command(command_string, options = {})
    options = {
      target: TOPLEVEL_BINDING,
      show_output: true,
      output: CmdConsole.config.output,
      commands: CmdConsole.config.commands
    }.merge!(options)

    # :context for compatibility with <= 0.9.11.4
    target = options[:context] || options[:target]
    output = options[:show_output] ? options[:output] : StringIO.new

    pry = CmdConsole.new(output: output, target: target, commands: options[:commands])
    pry.eval command_string
    nil
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

  # Return a `Binding` object for `target` or return `target` if it is
  # already a `Binding`.
  # In the case where `target` is top-level then return `TOPLEVEL_BINDING`
  # @param [Object] target The object to get a `Binding` object for.
  # @return [Binding] The `Binding` object.
  def self.binding_for(target)
    return target if Binding === target # rubocop:disable Style/CaseEquality
    return TOPLEVEL_BINDING if CmdConsole.main == target

    target.__binding__
  end

  def self.toplevel_binding
    unless defined?(@toplevel_binding) && @toplevel_binding
      # Grab a copy of the TOPLEVEL_BINDING without any local variables.
      # This binding has a default definee of Object, and new methods are
      # private (just as in TOPLEVEL_BINDING).
      TOPLEVEL_BINDING.eval <<-RUBY
        def self.__pry__
          binding
        end
        CmdConsole.toplevel_binding = __pry__
        class << self; undef __pry__; end
      RUBY
    end
    @toplevel_binding.eval('private')
    @toplevel_binding
  end

  class << self
    attr_writer :toplevel_binding
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
