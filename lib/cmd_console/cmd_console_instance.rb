# frozen_string_literal: true

require 'method_source'
require 'ostruct'

##
# CmdConsole is a powerful alternative to the standard IRB shell for Ruby. It
# features syntax highlighting, runtime invocation and source and documentation browsing.
#
# CmdConsole can be started similar to other command line utilities by simply running
# the following command:
#
#     pry
#
# Once inside CmdConsole you can invoke the help message:
#
#     help
#
# This will show a list of available commands and their usage. For more
# information about CmdConsole you can refer to the following resources:
#
# * http://pryrepl.org/
# * https://github.com/pry/pry
# * the IRC channel, which is #pry on the Freenode network
#

# rubocop:disable Metrics/ClassLength
class CmdConsole
  extend CmdConsole::Forwardable

  attr_reader :current_binding
  attr_accessor :custom_completions
  attr_accessor :eval_string
  attr_accessor :backtrace
  attr_accessor :suppress_output
  attr_accessor :last_result
  attr_accessor :last_file
  attr_accessor :last_dir

  attr_reader :last_exception
  attr_reader :exit_value

  # @since v0.12.0
  attr_reader :input_ring

  # @since v0.12.0
  attr_reader :output_ring

  attr_reader :config

  def_delegators(
    :@config, :input, :input=, :output, :output=, :commands,
    :commands=, :print, :print=, :exception_handler, :exception_handler=,
    :color, :color=, :pager, :pager=,
    :memory_size, :memory_size=, :extra_sticky_locals, :extra_sticky_locals=,
    :prompt, :prompt=, :history, :history=,
  )

  EMPTY_COMPLETIONS = [].freeze

  # Create a new {CmdConsole} instance.
  # @param [Hash] options
  # @option options [#readline] :input
  #   The object to use for input.
  # @option options [#puts] :output
  #   The object to use for output.
  # @option options [CmdConsole::CommandBase] :commands
  #   The object to use for commands.
  # @option options [Proc] :print
  #   The Proc to use for printing return values.
  # @option options [Boolean] :quiet
  #   Omit the `whereami` banner when starting.
  # @option options [Array<String>] :backtrace
  #   The backtrace of the session's `binding.pry` line, if applicable.
  # @option options [Object] :target
  #   The initial context for this session.
  def initialize(options = {})
    @eval_string   = ''.dup
    @backtrace     = options.delete(:backtrace) || caller
    target = options.delete(:target) || Object.new
    @config = self.class.config.merge(options)
    @input_ring = CmdConsole::Ring.new(config.memory_size)
    @output_ring = CmdConsole::Ring.new(config.memory_size)
    @custom_completions = config.command_completions
    set_last_result nil
    @input_ring << nil
    @current_binding = target
    @stopped = false
  end

  #
  # Generate completions.
  #
  # @param [String] str
  #   What the user has typed so far
  #
  # @return [Array<String>]
  #   Possible completions
  #
  def complete(str)
    return EMPTY_COMPLETIONS
    # TODO: This used to rely on InputCompleter from Pry. That functionality was awkward for
    # CmdConsole's simpler use cases. This method should implement a different style of completion
    # that is better suited for CmdConsole's use cases.
  end

  #
  # Injects a local variable into the provided binding.
  #
  # @param [String] name
  #   The name of the local to inject.
  #
  # @param [Object] value
  #   The value to set the local to.
  #
  # @param [Binding] binding
  #   The binding to set the local on.
  #
  # @return [Object]
  #   The value the local was set to.
  #
  def inject_local(name, value, binding)
    value = value.is_a?(Proc) ? value.call : value
    if binding.respond_to?(:local_variable_set)
      binding.local_variable_set name, value
    else # < 2.1
      begin
        CmdConsole.current[:pry_local] = value
        binding.eval "#{name} = ::CmdConsole.current[:pry_local]"
      ensure
        CmdConsole.current[:pry_local] = nil
      end
    end
  end

  undef :memory_size if method_defined? :memory_size
  # @return [Integer] The maximum amount of objects remembered by the inp and
  #   out arrays. Defaults to 100.
  def memory_size
    @output_ring.max_size
  end

  undef :memory_size= if method_defined? :memory_size=
  def memory_size=(size)
    @input_ring = CmdConsole::Ring.new(size)
    @output_ring = CmdConsole::Ring.new(size)
  end

  # Add a sticky local to this CmdConsole instance.
  # A sticky local is a local that persists between all bindings in a session.
  # @param [Symbol] name The name of the sticky local.
  # @yield The block that defines the content of the local. The local
  #   will be refreshed at each tick of the repl loop.
  def add_sticky_local(name, &block)
    config.extra_sticky_locals[name] = block
  end

  def sticky_locals
    {
      _in_: input_ring,
      _out_: output_ring,
      pry_instance: self,
      _ex_: last_exception && last_exception.wrapped_exception,
      _file_: last_file,
      _dir_: last_dir,
      _: proc { last_result },
      __: proc { output_ring[-2] }
    }.merge(config.extra_sticky_locals)
  end

  # Reset the current eval string. If the user has entered part of a multiline
  # expression, this discards that input.
  def reset_eval_string
    @eval_string = ''.dup
  end

  # Pass a line of input to CmdConsole.
  #
  # This is the equivalent of `Binding#eval` but with extra CmdConsole!
  #
  # In particular:
  # 1. CmdConsole commands will be executed immediately if the line matches.
  # 2. Partial lines of input will be queued up until a complete expression has
  #    been accepted.
  # 3. Output is written to `#output` in pretty colours, not returned.
  #
  # Once this method has raised an exception or returned false, this instance
  # is no longer usable. {#exit_value} will return the session's breakout
  # value if applicable.
  #
  # @param [String?] line The line of input; `nil` if the user types `<Ctrl-D>`
  # @option options [Boolean] :generated Whether this line was generated automatically.
  #   Generated lines are not stored in history.
  # @return [Boolean] Is CmdConsole ready to accept more input?
  # @raise [Exception] If the user uses the `raise-up` command, this method
  #   will raise that exception.
  def eval(line, options = {})
    return false if @stopped

    exit_value = nil
    exception = catch(:raise_up) do
      exit_value = catch(:breakout) do
        handle_line(line, options)
        # We use 'return !@stopped' here instead of 'return true' so that if
        # handle_line has stopped this pry instance (e.g. by opening pry_instance.repl and
        # then popping all the bindings) we still exit immediately.
        return !@stopped
      end
      exception = false
    end

    @stopped = true
    @exit_value = exit_value

    # TODO: make this configurable?
    raise exception if exception

    false
  end

  # Output the result or pass to an exception handler (if result is an exception).
  def show_result(result)
    if last_result_is_exception?
      exception_handler.call(output, result, self)
    elsif should_print?
      print.call(output, result, self)
    end
  rescue RescuableException => e
    # Being uber-paranoid here, given that this exception arose because we couldn't
    # serialize something in the user's program, let's not assume we can serialize
    # the exception either.
    begin
      output.puts "(pry) output error: #{e.inspect}\n#{e.backtrace.join("\n")}"
    rescue RescuableException
      if last_result_is_exception?
        output.puts "(pry) output error: failed to show exception"
      else
        output.puts "(pry) output error: failed to show result"
      end
    end
  ensure
    output.flush if output.respond_to?(:flush)
  end

  # If the given line is a valid command, process it in the context of the
  # current `eval_string` and binding.
  # @param [String] val The line to process.
  # @return [Boolean] `true` if `val` is a command, `false` otherwise
  def process_command(val)
    val = val.lstrip if /^\s\S/ !~ val
    val = val.chomp
    result = commands.process_line(
      val,
      target: current_binding,
      output: output,
      eval_string: @eval_string,
      pry_instance: self,
    )

    # set a temporary (just so we can inject the value we want into eval_string)
    CmdConsole.current[:pry_cmd_result] = result

    # note that `result` wraps the result of command processing; if a
    # command was matched and invoked then `result.command?` returns true,
    # otherwise it returns false.
    if result.command?
      unless result.void_command?
        # the command that was invoked was non-void (had a return value) and so we make
        # the value of the current expression equal to the return value
        # of the command.
        @eval_string = "::CmdConsole.current[:pry_cmd_result].retval\n"
      end
      true
    else
      false
    end
  end

  # Same as process_command, but outputs exceptions to `#output` instead of
  # raising.
  # @param [String] val  The line to process.
  # @return [Boolean] `true` if `val` is a command, `false` otherwise
  def process_command_safely(val)
    process_command(val)
  rescue CommandError,
         CmdConsole::Slop::InvalidOptionError,
         MethodSource::SourceNotFoundError => e
    CmdConsole.last_internal_error = e
    output.puts "Error: #{e.message}"
    true
  end

  # Run the specified command.
  # @param [String] val The command (and its params) to execute.
  # @return [CmdConsole::Command::VOID_VALUE]
  # @example
  #   pry_instance.run_command("ls -m")
  def run_command(val)
    commands.process_line(
      val,
      eval_string: @eval_string,
      target: current_binding,
      pry_instance: self,
      output: output
    )
    CmdConsole::Command::VOID_VALUE
  end

  # Set the last result of an eval.
  # This method should not need to be invoked directly.
  # @param [Object] result The result.
  # @param [String] code The code that was run.
  def set_last_result(result, code = "")
    @last_result_is_exception = false
    @output_ring << result

    self.last_result = result unless code =~ /\A\s*\z/
  end

  # Set the last exception for a session.
  # @param [Exception] exception The last exception.
  def last_exception=(exception)
    @last_result_is_exception = true
    last_exception = CmdConsole::LastException.new(exception)
    @output_ring << last_exception
    @last_exception = last_exception
  end

  # Update CmdConsole's internal state after evalling code.
  # This method should not need to be invoked directly.
  # @param [String] code The code we just eval'd
  def update_input_history(code)
    # Always push to the @input_ring as the @output_ring is always pushed to.
    @input_ring << code
    return unless code

    CmdConsole.line_buffer.push(*code.each_line)
    CmdConsole.current_line += code.lines.count
  end

  # @return [Boolean] True if the last result is an exception that was raised,
  #   as opposed to simply an instance of Exception (like the result of
  #   Exception.new)
  def last_result_is_exception?
    @last_result_is_exception
  end

  # Whether the print proc should be invoked.
  # Currently only invoked if the output is not suppressed.
  # @return [Boolean] Whether the print proc should be invoked.
  def should_print?
    !@suppress_output
  end

  undef :pager if method_defined? :pager
  # Returns the currently configured pager
  # @example
  #   pry_instance.pager.page text
  def pager
    CmdConsole::Pager.new(self)
  end

  undef :output if method_defined? :output
  # Returns an output device
  # @example
  #   pry_instance.output.puts "ohai!"
  def output
    CmdConsole::Output.new(self)
  end

  # Raise an exception out of CmdConsole.
  #
  # See Kernel#raise for documentation of parameters.
  # See rb_make_exception for the inbuilt implementation.
  #
  # This is necessary so that the raise-up command can tell the
  # difference between an exception the user has decided to raise,
  # and a mistake in specifying that exception.
  #
  # (i.e. raise-up RunThymeError.new should not be the same as
  #  raise-up NameError, "unititialized constant RunThymeError")
  #
  def raise_up_common(force, *args)
    exception = if args == []
                  last_exception || RuntimeError.new
                elsif args.length == 1 && args.first.is_a?(String)
                  RuntimeError.new(args.first)
                elsif args.length > 3
                  raise ArgumentError, "wrong number of arguments"
                elsif !args.first.respond_to?(:exception)
                  raise TypeError, "exception class/object expected"
                elsif args.size == 1
                  args.first.exception
                else
                  args.first.exception(args[1])
                end

    raise TypeError, "exception object expected" unless exception.is_a? Exception

    exception.set_backtrace(args.size == 3 ? args[2] : caller(1))

    if force
      throw :raise_up, exception
    else
      raise exception
    end
  end

  def raise_up(*args)
    raise_up_common(false, *args)
  end

  def raise_up!(*args)
    raise_up_common(true, *args)
  end

  # Convenience accessor for the `quiet` config key.
  # @return [Boolean]
  def quiet?
    config.quiet
  end

  private

  def handle_line(line, options)
    if line.nil?
      config.control_d_handler.call(self)
      return
    end

    ensure_correct_encoding!(line)
    history << line unless options[:generated]

    @suppress_output = false
    begin
      unless process_command_safely(line)
        @eval_string += "#{line.chomp}\n" if !line.empty? || !@eval_string.empty?
      end
    rescue RescuableException => e
      self.last_exception = e
      result = e

      CmdConsole.critical_section do
        show_result(result)
      end
      return
    end

    throw(:breakout) if current_binding.nil?
  end

  # Force `eval_string` into the encoding of `val`. [Issue #284]
  def ensure_correct_encoding!(val)
    if @eval_string.empty? &&
       val.respond_to?(:encoding) &&
       val.encoding != @eval_string.encoding
      @eval_string.force_encoding(val.encoding)
    end
  end
end
# rubocop:enable Metrics/ClassLength
