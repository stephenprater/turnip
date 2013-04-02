require 'pry'

$nesting = 0

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
        @metadata[:silent] ?  reporter.silence! : reporter.speak!
        run_without_silent(example_group_instance, reporter)
      ensure
        reporter.restore!
      end

      def self.included base
        base.send :alias_method, :run_without_silent, :run
        base.send :alias_method, :run, :run_with_silent
      end
    end
  end
end
