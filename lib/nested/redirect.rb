module Nested
  class Redirect
    attr_reader :url
    def initialize(url)
      @url = url
    end
  end
end