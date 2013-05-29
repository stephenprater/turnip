module Turnip
  module RSpec
    module SilentExampleExtension
      ##
      #
      # Run the example, if the metadata includes a :silent tag then
      # the example will not report itself. Used by turnip to optionally
      # pend examples which depend on previous examples
      #
      # creates a new output destination for each step level, then pops it
      # at the end of the method
      #
      # TODO Replace the include of this modules and the alias method chain
      # stuff with prepend
      #
      def run_with_silent(example_group_instance, reporter)
        if reporter.respond_to? :silence!
          begin
            @metadata[:silent] ?  reporter.silence! : reporter.speak!
            run_without_silent(example_group_instance, reporter)
          ensure
            reporter.restore!
          end
        else
          run_without_silent(example_group_instance, reporter)
        end
      end

      ## 
      #
      # called when a before / after hook fails or when the invisible example
      # fails.  clean up the backtrace and report something useful.
      #
      def fail_with_exception_with_silent(reporter, exception)
        if example_group.respond_to?(:in_hook) && hook = example_group.in_hook
          begin
            fail_with_exception_without_silent(reporter, exception)
            self.metadata[:description] = "in `#{hook}' hook for scenario #{self.example_group.description}"
            self.metadata[:full_description] = self.metadata[:description]
            self.metadata[:file_path], self.metadata[:line_number] = exception.backtrace.first.split(':').slice(0..1)
          ensure
          end
        else
          fail_with_exception_without_silent(reporter, exception)
        end
      end

      def self.included base
        base.send :alias_method, :run_without_silent, :run
        base.send :alias_method, :run, :run_with_silent

        base.send :alias_method, :fail_with_exception_without_silent, :fail_with_exception
        base.send :alias_method, :fail_with_exception, :fail_with_exception_with_silent

        base.send :attr_accessor, :in_hook
      end
    end
  end
end
