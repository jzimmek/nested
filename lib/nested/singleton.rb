module Nested
  class Singleton < Resource
    include WithMany

    def default_init_block
      if parent
        Proc.new{ instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name) }
      else
        Proc.new { nil }
      end
    end
  end
end