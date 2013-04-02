steps_for(:before) do
  before :all do
    puts "before all"
  end

  before :each do
    puts "before each"
  end

  after :all do
    puts "after all"
  end

  after :each do
    puts "after each"
  end

  step "a step" do
  end

  step "b step" do
  end
end
