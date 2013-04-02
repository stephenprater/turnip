require "turnip/version"
require "turnip/dsl"
require "turnip/execute"
require "turnip/define"
require "turnip/builder"
require "turnip/step_definition"
require "turnip/placeholder"
require "turnip/table"

module Turnip
  class Pending < StandardError; end
  class Ambiguous < StandardError; end

  ##
  #
  # The global step module, adding steps here will make them available in all
  # your tests.
  #
  module Steps
  end

  class << self
    attr_accessor :type
  end
end

Turnip.type = :feature

Module.send(:include, Turnip::Define)

self.extend Turnip::DSL

#flat out stole from rails
class Module
  def alias_method_chain(target, feature)
    # Strip out punctuation on predicates or bang methods since
    # e.g. target?_without_feature is not a valid method name.
    aliased_target, punctuation = target.to_s.sub(/([?!=])$/, ''), $1
    yield(aliased_target, punctuation) if block_given?

    with_method, without_method = "#{aliased_target}_with_#{feature}#{punctuation}", "#{aliased_target}_without_#{feature}#{punctuation}"

    alias_method without_method, target
    alias_method target, with_method

    case
      when public_method_defined?(without_method)
        public target
      when protected_method_defined?(without_method)
        protected target
      when private_method_defined?(without_method)
        private target
    end
  end
end

require "turnip/rspec"
