module TestHelper
  def singleton(name)
    Nested::Resource.new(@sinatra, name, true, false, nil, nil)
  end

  def many(name)
    Nested::Resource.new(@sinatra, name, false, true, nil, nil)
  end
end