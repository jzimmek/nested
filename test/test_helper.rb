module TestHelper
  def singleton(name)
    Nested::Resource.new(@sinatra, name, true, false, nil, Nested::Resource::PROC_TRUE, nil)
  end

  def many(name)
    Nested::Resource.new(@sinatra, name, false, true, nil, Nested::Resource::PROC_TRUE, nil)
  end
end