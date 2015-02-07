module Regal
  class Response
    attr_accessor :status
    attr_reader :headers

    def initialize
      @status = 200
      @headers = {}
      @body = nil
    end

    def body=(body)
      if body.is_a?(String)
        @body = [body]
      elsif body.respond_to?(:each)
        @body = body
      else
        raise ArgumentError, %(Body must be a String or Enumerable)
      end
    end

    def [](n)
      case n
      when 0 then @status
      when 1 then @headers
      when 2 then @body
      end
    end

    def to_ary
      [@status, @headers, @body]
    end
  end
end
