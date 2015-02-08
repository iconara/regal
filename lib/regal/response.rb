module Regal
  class Response
    attr_accessor :status, :body
    attr_reader :headers

    def initialize
      @status = 200
      @headers = {}
      @body = nil
    end

    def [](n)
      case n
      when 0 then @status
      when 1 then @headers
      when 2 then rack_body
      end
    end

    def to_ary
      [@status, @headers, rack_body]
    end

    private

    def rack_body
      if @body.is_a?(String)
        [@body]
      else
        @body
      end
    end
  end
end
