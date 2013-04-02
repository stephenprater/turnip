require 'rspec/core/formatters/html_formatter'
require 'rspec/core/formatters/json_formatter'

module Turnip
  module RSpec
    module ReporterExtension
      def silence!
        output_stack.push :silence
      end

      def speak!
        output_stack.push :speak
      end

      def restore!
        output_stack.pop
      end

      def output_stack
        @output_stack ||= [:speak]
      end

      def output
        output_stack.last
      end

      def notify method, *args, &block
        @formatters.each do |formatter|
          if output == :silence
            formatter.output = StringIO.new
          elsif output == :speak
            formatter.output = formatter.loud_output
          end
        end
        super(method, *args, &block)
      end
    end

    ##
    # 
    # This module adds a method to the formatter that it can output 
    # 'step stubs' for steps which are pending
    #
    module FormatterExtension
      def self.extended base

        base.class.send :attr_accessor, :loud_output
        base.class.send :attr_accessor, :output
        base.loud_output = base.output.clone

        case base
        when ::RSpec::Core::Formatters::HtmlFormatter
          base.extend Turnip::RSpec::HtmlFormatterExtension
        when ::RSpec::Core::Formatters::JsonFormatter
          base.extend Turnip::RSpec::JsonFormatterExtension
        end
      end

      def example_step_stub example
        @stubs ||= Set.new 
        stub = <<-STUB
        step "#{example.step.description}" do
          pending
        end
        STUB
        indent = stub.scan(/^\s*/).min_by{ |l|l.length }
        @stubs << stub.gsub(/#{indent}/,"")
      end

      def dump_stubs
        output.puts "\nMissing Steps:\n\n"
        output.puts @stubs.to_a.join("\n")
      end

      def dump_summary(*args)
        if @stubs && !@stubs.empty?
          dump_stubs
        end
        super(*args)
      end
    end

    ##
    #
    # Addresses an implmentation problem in the HTML formatter in that the
    # `printer` object directly addresses the output object by it's own
    # reference rather than through an accessor, or even more prefereably, the
    # accessor of the formatter object
    #
    module HtmlFormatterExtension
      def output= arg
        @output = arg
        @printer.instance_eval do
          @output = arg 
        end
      end
    end

    ##
    # 
    # The JsonFormatter doesn't actually output data in a stream, but rather
    # waits until the 'stop' method is called and then builds a hash from all of
    # the data - address this by removing "silent" examples before the formatter
    # flushes it's output
    #
    module JsonFormatterExtension
      def example_started ex
        unless ex.metadata[:silent] == true
          super(ex)
        end
      end

      def stop
        super
        @output_hash[:examples] = examples.map do |example|
          {
            :description => example.description,
            :full_description => example.full_description,
            :status => example.execution_result[:status],
            # :example_group,
            # :execution_result,
            :file_path => example.metadata[:file_path],
            :line_number  => example.metadata[:line_number],
          }.tap do |hash|
            if e=example.exception
              hash[:exception] =  {
                :class => e.class.name,
                :message => e.message,
                :backtrace => e.backtrace,
              }
            end
          end
        end
      end
    end
  end
end
