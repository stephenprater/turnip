require "turnip"
require "rspec"

require "turnip/rspec/formatter_extension"
require "turnip/rspec/step_example"
require "turnip/rspec/example_extension"
require "pry"

module Turnip
  module RSpec

    ##
    #
    # This module hooks Turnip into RSpec by duck punching the load Kernel
    # method. If the file is a feature file, we run Turnip instead!
    #
    module Loader
      def load(*a, &b)
        if a.first.end_with?('.feature')
          require_if_exists 'turnip_helper'
          require_if_exists 'spec_helper'

          Turnip::RSpec.run(a.first)
        else
          super
        end
      end

      private

      def require_if_exists(filename)
        require filename
      rescue LoadError => e
        # Don't hide LoadErrors raised in the spec helper.
        raise unless e.message.include?(filename)
      end
    end

    ##
    #
    # This module provides an improved method to run steps inside RSpec, adding
    # proper support for pending steps, as well as nicer backtraces.
    #
    # These steps DO participate in RSpec reporting - so it's possible to have things
    # like more failures (or pendings) than examples
    #
    module Execute
      include Turnip::Execute

      # Run a step example
      def run_step(feature_file, step)
        StepExample.new(self, feature_file,step).run(self, ::RSpec.configuration.reporter)
      end

      # Run a step in "pending" state.  The step still participates in error reporting
      # but always returns pending because an earlier step failed.
      def pending_step feature_file, step, dependent
        StepExample.new(self, feature_file, step) do
          pending("Depends on step `#{dependent.step.keyword} #{dependent.step.description}' which #{dependent.result}")
        end.run(self, ::RSpec.configuration.reporter)
      end
    end

    class << self
      
      def run(feature_file)
        ::RSpec.configuration.formatters.each do |f|
           f.extend Turnip::RSpec::FormatterExtension
        end

        ::RSpec.configuration.reporter.extend Turnip::RSpec::ReporterExtension

        Turnip::Builder.build(feature_file).features.each do |feature|
          describe feature.name, feature.metadata_hash do
            before do
              # This is kind of a hack, but it will make RSpec throw way nicer exceptions
              example.metadata[:file_path] = feature_file

              feature.backgrounds.map(&:steps).flatten.each do |step|
                run_step(feature_file, step)
              end
            end

            feature.scenarios.each do |scenario|
              describe scenario.name, scenario.metadata_hash do
                # an enumerator type thing which will return nil when the steps
                # are exhausted rather than raising StopIteration
                step_fiber = Fiber.new do |f|
                  scenario.steps.each do |step|
                    Fiber.yield step
                  end
                  nil
                end

                # what is going on here?
                # an "it" block creates an RSpec example for later execution
                # but steps are not equivalent to an example, since they should
                # run in the same context. The more appropriate mapping is from steps to assertions.
                # The problem being that assertions do not participate in RSpec reporting
                # the same way an example does.  So without REALLY abusing global state and
                # a lot spooky action at a distance it doesn't make
                # sense to map examples to steps. (you'd basically need to
                # rewrite the entire CONCEPT of an example)
                #
                # instead, we run each step within an example - and change the
                # name of the example based on the execution step that failed.
                # in that way, it's much like a ExpectationFailed matcher
                # - except it provides good backtraces and of course human
                # readability
                #
                it "__scenario_example", :silent => true do |ex|
                  original_example = example
                  example.metadata[:line_number] = scenario.line
                  begin
                    while step = step_fiber.resume do
                      run_step(feature_file, step)
                    end
                  rescue PendingStepException => e
                    original_example.metadata[:description] = e.step.description
                    scenario.pending_step = e.step
                    e.step.result = "is pending"
                    #if a step is pending, rewrite the metadata and declare the example pending
                  rescue StepException => e
                    original_example.metadata[:description] = e.step.description
                    scenario.pending_step = e.step
                    e.step.result = "failed"
                    #if a step failed, rewrite the metadata and declare the example failed
                  end
                end

                # this is an internal step which will not participate in reporting,
                # although steps executed WITHIN it will
                #
                # if the step enumerator is not exhausted when this step is run then
                # it will report all additional steps as pending with the 'parent' step
                # in the reason
               
                it "__temp_step", :silent => true do
                  if scenario.pending_step?
                    while step = step_fiber.resume do
                      begin
                        pending_step(feature_file, step, scenario.pending_step)
                      rescue PendingStepException
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end


::RSpec::Core::Configuration.send(:include, Turnip::RSpec::Loader)
::RSpec::Core::Example.send(:include, Turnip::RSpec::SilentExampleExtension)
::Turnip::RSpec::StepExample.send(:include, Turnip::RSpec::SilentExampleExtension)

::RSpec.configure do |config|
  config.add_setting :generate_step_stubs,
    :default => false
  config.include Turnip::RSpec::Execute, turnip: true
  config.include Turnip::Steps, turnip: true
  config.pattern << ",**/*.feature"
  config.backtrace_clean_patterns << /lib\/turnip/
  if ENV['STUBS']
    config.generate_step_stubs = true
  end
end