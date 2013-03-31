require "turnip"
require "rspec"
require "pry"

module Turnip
  module RSpec

    ##
    # 
    # This module adds a method to the formatter that it can output 
    # 'step stubs' for steps which are pending
    #
    module FormatterExtension
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
      
      def run_step(feature_file, step)
        StepExample.new(self, feature_file,step).run(self, ::RSpec.configuration.reporter)
      end

      def pending_step feature_file, step, dependent
        StepExample.new(self, feature_file, step) do
          pending("Depends on step `#{dependent.step.keyword} #{dependent.step.description}' which #{dependent.result}")
        end.run(self, ::RSpec.configuration.reporter)
      end
    end


    ##
    #
    # This class provides an RSpec::Example subclass for steps, which differ
    # from regular examples in that they live inside of an RSpec Example and
    # provide error reporting on the step, but without modifing the example
    # count
    #
    class StepExample < ::RSpec::Core::Example

      attr_reader :step
      attr_accessor :result
      
      def report?
        @report
      end
      
      def initialize(example, feature_file, step, &block)
        #rewrite the scenario metadata to reflect this step
        meta = example.class.metadata.clone
        meta[:caller] = ["#{feature_file}:#{step.line} in step `#{step.description}'"]
        meta[:description] = "#{step.keyword} #{step.description}"
        meta[:type] = :step

        @step = step
        
        if block.nil?
          super(example.class, "-> #{meta[:description]}", meta, proc { example.step(step) })
        else
          @report = true
          super(example.class, "-> #{meta[:description]}", meta, block)
        end
      end

      def run(example_group_instance, reporter)
        @example_group_instance = example_group_instance
        @example_group_instance.example = self
       
        if pending
          record :status => 'pending', :pending_message => String === pending ? pending : Pending::NO_REASON_GIVEN
          reporter.example_pending self
        else
          begin
            begin
              time = ::RSpec::Core::Time.now
              @example_group_instance.instance_eval(&@example_block)
            ensure
              time = (::RSpec::Core::Time.now - time).to_f
            end
            record :status => 'passed', :run_time => time
            reporter.example_passed(self)
          rescue ::RSpec::Core::Pending::PendingDeclaredInExample => e
            record :status => 'pending', :pending_message => e.message, :run_time => time
            reporter.example_pending(self) if report?
            raise PendingStepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
          rescue Turnip::Pending => e
            record :status => 'pending', :pending_message => "step does not exist", :run_time => time
            if ::RSpec.configuration.generate_step_stubs
              reporter.notify :example_step_stub, self
            end
            reporter.example_pending(self) if report?
            raise PendingStepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
          rescue Exception => e
            e.extend(NotPendingExampleFixed) unless e.respond_to?(:pending_fixed?)
            record :status => 'failed', :run_time => time
            raise StepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
          end
        end
      end
    end

    class StepException < StandardError
      attr_accessor :backtrace, :step
      def initialize(message, step, backtrace)
        self.backtrace = backtrace
        self.step = step
        super(message)
      end
    end

    class PendingStepException < StepException; end

    class << self
      def run(feature_file)
        ::RSpec.configuration.formatters.each do |f|
           f.extend Turnip::RSpec::FormatterExtension
        end

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
                step_fiber = Fiber.new do |f|
                  scenario.steps.each do |step|
                    Fiber.yield step
                  end
                  nil
                end

                # what is going on here?
                # an "it" block creates an RSpec example for later execution
                # but steps are not equivalent to an example.  The more
                # appropriate mapping is from steps to assertions.  the problem
                # being is that each assert depends on all prior assertions
                # running successfully, so without REALLY abusing state and
                # a lot spooky action at a distance programming it doesn't make
                # sense to map examples to steps.
                #
                # instead, we run each step within an example - and change the
                # name of the example based on the execution step that failed.
                # in that way, it's much like a ExpectationFailed matcher
                # - except it provides good backtraces and of course human
                # readability
                #
                
                after :each do |ex|
                  ::RSpec.configuration.formatters.each do |f|
                    f.instance_eval do
                      #remove the 'temporary step holders'
                      @examples.reject! do |example|
                        example.metadata[:description] ==  "__temp_step"
                      end
                      #and put the scenario outcomes at the top of the list
                      @examples.sort_by! do |example|
                        example.metadata[:feature_example] == true ? 1 : -1
                      end
                    end
                  end
                end
                
                
                it "\0", :feature_example => true do |ex|
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
                    pending(e.message)
                  rescue StepException => e
                    original_example.metadata[:description] = e.step.description
                    scenario.pending_step = e.step
                    e.step.result = "failed"
                    raise e
                  end
                end

                it "__temp_step" do
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