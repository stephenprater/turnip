require 'spec_helper'

describe 'The CLI', :type => :integration do
  before do
    @result = %x(rspec -fd examples/*.feature)
  end

  it "shows the correct description" do
    @result.should include('A simple feature')
    @result.should include('is a simple feature')
  end

  it "prints out failures and successes" do
    @result.should include('171 examples, 4 failures, 15 pending')
  end

  it "includes features in backtraces" do
    @result.should include('examples/errors.feature:5 # raises errors Step raises error -> When raise error')
  end

  it "includes pending steps in result" do
    @result.should include(<<-PEND)
  using scenario outlines a simple outline -> Given there is a monster with hitpoints:
    # step does not exist
    # ./examples/scenario_outline_table_substitution.feature:3
    PEND
  end

  it "does not report on invisible examples" do
    @result.should_not include('__temp_step')
    @result.should_not include('__scenario_example')
  end

  it "can generate stub steps if passed the right param" do
    @result = %x(STUBS=1 rspec -fd examples/*.feature)
    @result.should(include(<<-STUB))
step "there is an unimplemented step" do
  pending
end
    STUB
  end

  describe "various formatters do not report invisible steps" do
    it "json formatters does not include invisible steps" do
      @result = %x(rspec -fj examples/simple_feature.feature)
      res = JSON.parse(@result)
      res['summary_line'].should == "14 examples, 1 failure, 6 pending"
      res['examples'].select do |ex|
        ex['description'] =~ /__.*$/
      end.should(be_empty)
    end

    it "html formatter does not include invisible steps" do
      @result = %x(rspec -fh examples/simple_feature.feature)
      @result.should_not include('__temp_step')
      @result.should_not include('__scenario_example')
    end

    it "doc formatter does not include invisible steps" do
      @result = %x(rspec -fd examples/simple_feature.feature)
      @result.should_not include('__temp_step')
      @result.should_not include('__scenario_example')
    end
  end
end
