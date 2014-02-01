module TestHelper
  def singleton(name)
    Nested::Singleton.new(@sinatra, name, nil, Nested::PROC_TRUE, nil)
  end

  def many(name)
    Nested::Many.new(@sinatra, name, nil, Nested::PROC_TRUE, nil)
  end
end