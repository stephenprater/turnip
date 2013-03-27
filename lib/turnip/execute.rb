module Turnip
  module Execute
    def step(description, *extra_args)
      extra_args.concat(description.extra_args) if description.respond_to?(:extra_args)

      matches = methods.map do |method|
        next unless method.to_s.start_with?("match: ")
        send(method.to_s, description.to_s)
      end.compact

      if matches.length == 0
        raise Turnip::Pending, description
      end

      if matches.length > 1
        msg = ['Ambiguous step definitions'].concat(matches.map(&:trace)).join("\r\n")
        raise Turnip::Ambiguous, msg
      end

      send(matches.first.method_name, *(matches.first.params + extra_args))
    end
  end

  class StepExample < ::RSpec::Core::Example
    def run(example_group_instance, reporter)
      @example_group_instance = example_group_instance
      @example_group_instance.example = self
      
      begin
        if pending
          record :status => 'pending', :pending_message => String === pending ? pending : Pending::NO_REASON_GIVEN
          reporter.example_pending self
        else
          begin
            @example_group_instance.instance_eval(&@example_block)
            record :status => 'passed'
            reporter.example_passed(self)
          rescue ::RSpec::Core::Pending::PendingDeclaredInExample => e
            record :status => 'pending', :pending_message => e.message
            reporter.example_pending(self)
          rescue Exception => e
            e.extend(NotPendingExampleFixed) unless e.respond_to?(:pending_fixed?)
            e.backtrace.concat @metadata[:caller]
            record :status => 'failed', :exception => e
            reporter.example_failed(self)
          end
        end
      rescue Exception => e
        e.extend(NotPendingExampleFixed) unless e.respond_to?(:pending_fixed?)
        record :status => 'failed', :exception => e
        reporter.example_failed(self)
      ensure
        begin
          assign_generated_description
        rescue Exception => e
          set_exception(e, "while assigning the example description")
        end
      end
    end
  end
end
