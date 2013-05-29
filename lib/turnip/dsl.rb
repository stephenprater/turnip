require 'pry'
module Turnip
  module DSL
    def placeholder(name, &block)
      Turnip::Placeholder.add(name, &block)
    end

    def step(description, &block)
      Turnip::Steps.step(description, &block)
    end

    def steps_for(tag, &block)
      if tag.to_s == "global"
        warn "[Turnip] using steps_for(:global) is deprecated, add steps to Turnip::Steps instead"
        Turnip::Steps.module_eval(&block)
      else
        Module.new do
          singleton_class.send(:define_method, :tag) { tag }

          [:before, :after, :around].each do |hook|
            singleton_class.send(:define_method, hook) do |scope, options = {}, &blk|
            #this is so an example executed in silent mode can tell if it died
            #during a before or after hook and report the error accordingly.
             g_block = lambda do |ex|
               self.class.in_hook = hook 
               blk.call
               # notably, this is not in an ensure block because we DO NOT want
               # it unset in the event of an exception
               # see the silentexample extension
               self.class.in_hook = false
             end
             ::RSpec.configure do |config|
                config.send(hook, scope, { tag => true, :hooks => :run}.merge(options), &g_block)
              end
            end
          end

          module_eval(&block)
          ::RSpec.configure { |c| c.include self, tag => true }
        end
      end
    end
  end
end
