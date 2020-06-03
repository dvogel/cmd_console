# frozen_string_literal: true

require 'ostruct'
require 'pp'

class CmdConsole
  # @api private
  class Config
    extend Attributable

    # @return [IO, #readline] he object from which CmdConsole retrieves its lines of
    #   input
    attribute :input

    # @return [IO, #puts] where CmdConsole should output results provided by {input}
    attribute :output

    # @return [CmdConsole::CommandSet]
    attribute :commands

    # @return [Proc] the printer for Ruby expressions (not commands)
    attribute :print

    # @return [Proc] the printer for exceptions
    attribute :exception_handler

    # @return [Integer] The number of lines of context to show before and after
    #   exceptions
    attribute :default_window_size

    # @return [String]
    attribute :prompt

    # @return [Array<Object>] the list of objects that are known to have a
    #   1-line #inspect output suitable for prompt
    attribute :prompt_safe_contexts

    # @return [Boolean]
    attribute :color

    # @return [Boolean]
    attribute :pager

    # @return [CmdConsole::History]
    attribute :history

    # @return [Boolean]
    attribute :history_save

    # @return [Boolean]
    attribute :history_load

    # @return [Array<String,Regexp>]
    attribute :history_ignorelist

    # @return [Array<String>] Ruby files to be required
    attribute :requires

    # @return [Integer] how many input/output lines to keep in memory
    attribute :memory_size

    # @return [Boolean] displays a warning about experience improvement on
    #   Windows
    attribute :windows_console_warning

    # @return [Proc]
    attribute :command_completions

    # @return [Hash]
    attribute :ls

    # @return [String] a line of code to execute in context before the session
    #   starts
    attribute :exec_string

    def initialize
      merge!(
        input: MemoizedValue.new { lazy_readline },
        output: $stdout.tap { |out| out.sync = true },
        commands: CmdConsole::Commands,
        prompt: "> ",
        prompt_safe_contexts: [String, Numeric, Symbol, nil, true, false],
        print: proc{ |_output, value, pry_instance| pp(value) },
        exception_handler: CmdConsole::ExceptionHandler.method(:handle_exception),
        pager: true,
        color: CmdConsole::Helpers::BaseHelpers.use_ansi_codes?,
        default_window_size: 5,
        requires: [],
        windows_console_warning: true,
        control_d_handler: CmdConsole::ControlDHandler.method(:default),
        memory_size: 100,
        command_completions: proc { commands.keys },
        history_save: true,
        history_load: true,
        history_ignorelist: [],
        history: MemoizedValue.new do
          if defined?(input::HISTORY)
            CmdConsole::History.new(history: input::HISTORY)
          else
            CmdConsole::History.new
          end
        end,
        exec_string: ''
      )

      @custom_attrs = {}
    end

    def merge!(config_hash)
      config_hash.each_pair { |attr, value| __send__("#{attr}=", value) }
      self
    end

    def merge(config_hash)
      dup.merge!(config_hash)
    end

    def []=(attr, value)
      @custom_attrs[attr.to_s] = Config::Value.new(value)
    end

    def [](attr)
      @custom_attrs[attr.to_s].call
    end

    # rubocop:disable Style/MethodMissingSuper
    def method_missing(method_name, *args, &_block)
      name = method_name.to_s

      if name.end_with?('=')
        self[name[0..-2]] = args.first
      elsif @custom_attrs.key?(name)
        self[name]
      end
    end
    # rubocop:enable Style/MethodMissingSuper

    def respond_to_missing?(method_name, include_all = false)
      @custom_attrs.key?(method_name.to_s.tr('=', '')) || super
    end

    def initialize_dup(other)
      super
      @custom_attrs = @custom_attrs.dup
    end

    attr_reader :control_d_handler
    def control_d_handler=(value)
      proxy_proc =
        if value.arity == 2
          CmdConsole::Warning.warn(
            "control_d_handler's arity of 2 parameters was deprecated " \
            '(eval_string, pry_instance). Now it gets passed just 1 ' \
            'parameter (pry_instance)'
          )
          proc do |*args|
            if args.size == 2
              value.call(args.first, args[1])
            else
              value.call(args.first.eval_string, args.first)
            end
          end
        else
          proc do |*args|
            if args.size == 2
              value.call(args[1])
            else
              value.call(args.first)
            end
          end
        end
      @control_d_handler = proxy_proc
    end

    private

    def lazy_readline
      require 'readline'
      ::Readline
    rescue LoadError
      output.puts(
        "Sorry, you can't use CmdConsole without Readline or a compatible library. \n" \
        "Possible solutions: \n" \
        " * Rebuild Ruby with Readline support using `--with-readline` \n" \
        " * Use the rb-readline gem, which is a pure-Ruby port of Readline \n" \
        " * Use the pry-coolline gem, a pure-ruby alternative to Readline"
      )
      raise
    end
  end
end
