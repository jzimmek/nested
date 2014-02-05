module TestHelper
  def singleton(name, model_block=Nested::PROC_NIL)
    Nested::Singleton.new(@sinatra, name, nil, Nested::PROC_TRUE, model_block)
  end

  def many(name, model_block=Nested::PROC_NIL)
    Nested::Many.new(@sinatra, name, nil, Nested::PROC_TRUE, model_block)
  end
end