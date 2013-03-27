require "turnip"
require "rspec"
require 'pry'

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
    module Execute
      include Turnip::Execute
      
      def fake_example feature_file, step
        meta = self.class.metadata.clone
        meta[:caller] = ["#{feature_file}:#{step.line} in `#{step.description}'"]
        meta[:description] = step.description
        meta[:type] = :step
        Turnip::StepExample.new(self.class, "Step: #{step.description}", meta, proc { step(step) })
      end

      def run_step(feature_file, step)
        step = fake_example(feature_file,step)
        begin
          step.run(self, ::RSpec.configuration.reporter)
          step.execution_result[:status] == "passed"
        rescue Turnip::Pending
          pending("No such step: '#{step}'")
        end
      end
    end

    class StepException < StandardError
      attr_accessor :backtrace
      def initialize(message, backtrace)
        self.backtrace = backtrace
        super(message)
      end
    end

    class << self
      def run(feature_file)
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
                it scenario.name do |ex|
                  steps = scenario.steps.collect do |step|
                    run_step(feature_file, step)
                  end
                  if steps.include? false
                    scen_location = ["#{feature_file}:#{feature.line} in Scenario: #{feature.name}"] 
                    e = StepException.new("Scenario failed because a step failed", scen_location)
                    example.metadata[:caller] = scen_location
                    raise e
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

::RSpec.configure do |config|
  config.include Turnip::RSpec::Execute, turnip: true
  config.include Turnip::Steps, turnip: true
  config.pattern << ",**/*.feature"
  config.backtrace_clean_patterns << /lib\/turnip/
end