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
            formatter.instance_variable_set('@output', StringIO.new)
          elsif output == :speak
            output = formatter.instance_variable_get('@loud_output')
            formatter.instance_variable_set('@output', output)
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
        base.instance_eval do
          @loud_output = @output.clone
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
  end
end
