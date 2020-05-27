# frozen_string_literal: true

class CmdConsole
  class REPL
    extend CmdConsole::Forwardable
    def_delegators :@pry, :input, :output

    # @return [CmdConsole] The instance of {CmdConsole} that the user is controlling.
    attr_accessor :pry

    # Instantiate a new {CmdConsole} instance with the given options, then start a
    # {REPL} instance wrapping it.
    # @option options See {CmdConsole#initialize}
    def self.start(options)
      new(CmdConsole.new(options)).start
    end

    # Create an instance of {REPL} wrapping the given {CmdConsole}.
    # @param [CmdConsole] pry The instance of {CmdConsole} that this {REPL} will control.
    # @param [Hash] options Options for this {REPL} instance.
    # @option options [Object] :target The initial target of the session.
    def initialize(pry, options = {})
      @pry    = pry

      @readline_output = nil

      @pry.push_binding options[:target] if options[:target]
    end

    # Start the read-eval-print loop.
    # @return [Object?] If the session throws `:breakout`, return the value
    #   thrown with it.
    # @raise [Exception] If the session throws `:raise_up`, raise the exception
    #   thrown with it.
    def start
      prologue
      CmdConsole::InputLock.for(:all).with_ownership { repl }
    end

    private

    # Set up the repl session.
    # @return [void]
    def prologue
      return unless pry.config.correct_indent

      # Clear the line before starting CmdConsole. This fixes issue #566.
      output.print(Helpers::Platform.windows_ansi? ? "\e[0F" : "\e[0G")
    end

    # The actual read-eval-print loop.
    #
    # The {REPL} instance is responsible for reading and looping, whereas the
    # {CmdConsole} instance is responsible for evaluating user input and printing
    # return values and command output.
    #
    # @return [Object?] If the session throws `:breakout`, return the value
    #   thrown with it.
    # @raise [Exception] If the session throws `:raise_up`, raise the exception
    #   thrown with it.
    def repl
      loop do
        case val = read
        when :control_c
          output.puts ""
          pry.reset_eval_string
        when :no_more_input
          output.puts "" if output.tty?
          break
        when ''
          next
        else
          output.puts "" if val.nil? && output.tty?
          return pry.exit_value unless pry.eval(val)
        end
      end
    end

    # Read a line of input from the user.
    # @return [String] The line entered by the user.
    # @return [nil] On `<Ctrl-D>`.
    # @return [:control_c] On `<Ctrl+C>`.
    # @return [:no_more_input] On EOF.
    def read
      current_prompt = pry.prompt

      # Will be nil for EOF, :no_more_input for error, or :control_c for <Ctrl-C>
      read_line(current_prompt)
    end

    # Manage switching of input objects on encountering `EOFError`s.
    # @return [Object] Whatever the given block returns.
    # @return [:no_more_input] Indicates that no more input can be read.
    def handle_read_errors
      should_retry = true
      exception_count = 0

      begin
        yield
      rescue EOFError
        pry.config.input = CmdConsole.config.input
        unless should_retry
          output.puts "Error: CmdConsole ran out of things to read from! " \
            "Attempting to break out of REPL."
          return :no_more_input
        end
        should_retry = false
        retry

      # Handle <Ctrl+C> like Bash: empty the current input buffer, but don't
      # quit.  This is only for MRI 1.9; other versions of Ruby don't let you
      # send Interrupt from within Readline.
      rescue Interrupt
        return :control_c

      # If we get a random error when trying to read a line we don't want to
      # automatically retry, as the user will see a lot of error messages
      # scroll past and be unable to do anything about it.
      rescue RescuableException => e
        puts "Error: #{e.message}"
        output.puts e.backtrace
        exception_count += 1
        retry if exception_count < 5
        puts "FATAL: CmdConsole failed to get user input using `#{input}`."
        puts "To fix this you may be able to pass input and output file " \
          "descriptors to pry directly. e.g."
        puts "  CmdConsole.config.input = STDIN"
        puts "  CmdConsole.config.output = STDOUT"
        puts "  binding.pry"
        return :no_more_input
      end
    end

    # Returns the next line of input to be sent to the {CmdConsole} instance.
    # @param [String] current_prompt The prompt to use for input.
    # @return [String?] The next line of input, or `nil` on <Ctrl-D>.
    def read_line(current_prompt)
      handle_read_errors do
        if coolline_available?
          input.completion_proc = proc do |cool|
            completions = @pry.complete cool.completed_word
            completions.compact
          end
        elsif input.respond_to? :completion_proc=
          input.completion_proc = proc do |inp|
            @pry.complete inp
          end
        end

        if readline_available?
          set_readline_output
          input_readline(current_prompt, false) # false since we'll add it manually
        elsif coolline_available?
          input_readline(current_prompt)
        elsif input.method(:readline).arity == 1
          input_readline(current_prompt)
        else
          input_readline
        end
      end
    end

    def input_readline(*args)
      CmdConsole::InputLock.for(:all).interruptible_region do
        input.readline(*args)
      end
    end

    def readline_available?
      defined?(Readline) && input == Readline
    end

    def coolline_available?
      defined?(Coolline) && input.is_a?(Coolline)
    end

    # If `$stdout` is not a tty, it's probably a pipe.
    # @example
    #   # `piping?` returns `false`
    #   % pry
    #   [1] pry(main)
    #
    #   # `piping?` returns `true`
    #   % pry | tee log
    def piping?
      return false unless $stdout.respond_to?(:tty?)

      !$stdout.tty? && $stdin.tty? && !Helpers::Platform.windows?
    end

    # @return [void]
    def set_readline_output
      return if @readline_output

      @readline_output = (Readline.output = CmdConsole.config.output) if piping?
    end

    # Calculates correct overhang for current line. Supports vi Readline
    # mode and its indicators such as "(ins)" or "(cmd)".
    #
    # @return [Integer]
    # @note This doesn't calculate overhang for Readline's emacs mode with an
    #   indicator because emacs is the default mode and it doesn't use
    #   indicators in 99% of cases.
    def calculate_overhang(current_prompt, original_val, indented_val)
      overhang = original_val.length - indented_val.length

      if readline_available? && Readline.respond_to?(:vi_editing_mode?)
        begin
          # rb-readline doesn't support this method:
          # https://github.com/ConnorAtherton/rb-readline/issues/152
          if Readline.vi_editing_mode?
            overhang = output.width - current_prompt.size - indented_val.size
          end
        rescue NotImplementedError
          # VI editing mode is unsupported on JRuby.
          # https://github.com/pry/pry/issues/1840
          nil
        end
      end
      [0, overhang].max
    end
  end
end

