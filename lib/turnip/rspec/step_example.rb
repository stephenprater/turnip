module Turnip
  module RSpec

    ##
    #
    # Exception raised when a step fails
    #
    class StepException < StandardError
      attr_accessor :backtrace, :step
      def initialize(message, step, backtrace)
        self.backtrace = backtrace
        self.step = step
        super(message)
      end
    end

    ##
    # Exception raised when a step is pending but implemented
    #
    # @see Turnip::Pending for unimplemented step exception
    #
    class PendingStepException < StepException; end

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
     
      # @returns [Boolean] if step participates in error reporting
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
          super(example.class, "-> #{meta[:description]}", meta, block)
        end
      end

      # @private
      # custom run method which raises step specific exceptions and modifies
      # error reporting
      def run(example_group_instance, reporter)
        @example_group_instance = example_group_instance
        @example_group_instance.example = self
       
        begin
          begin
            time = ::RSpec::Core::Time.now
            reporter.example_started(self)
            @example_group_instance.instance_eval(&@example_block)
          ensure
            time = (::RSpec::Core::Time.now - time).to_f
          end
          record :status => 'passed', :run_time => time
          reporter.example_passed(self)
        rescue ::RSpec::Core::Pending::PendingDeclaredInExample => e
          record :status => 'pending', :pending_message => e.message, :run_time => time
          reporter.example_pending(self)
          raise PendingStepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
        rescue Turnip::Pending => e
          record :status => 'pending', :pending_message => "step does not exist", :run_time => time
          if ::RSpec.configuration.generate_step_stubs
            reporter.notify :example_step_stub, self
          end
          reporter.example_pending(self)
          raise PendingStepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
        rescue Exception => e
          e.extend(NotPendingExampleFixed) unless e.respond_to?(:pending_fixed?)
          record :status => 'failed', :run_time => time, :exception => e
          reporter.example_failed(self)
          raise StepException.new e.message, self, e.backtrace.concat(@metadata[:caller])
        end
      end
    end
  end
end
