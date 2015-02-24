module Regal
  class Response
    attr_accessor :status, :body, :raw_body
    attr_reader :headers

    EMPTY_BODY = [].freeze

    def initialize
      @status = 200
      @headers = {}
      @body = nil
      @raw_body = nil
      @finished = false
    end

    def finish
      @finished = true
    end

    def finished?
      @finished
    end

    def no_body
      @raw_body = EMPTY_BODY
    end

    def [](n)
      case n
      when 0 then @status
      when 1 then @headers
      when 2 then rack_body
      end
    end

    def []=(n, v)
      case n
      when 0 then @status = v
      when 1 then @headers = v
      when 2 then @raw_body = v
      end
    end

    def to_ary
      [@status, @headers, rack_body]
    end
    alias_method :to_a, :to_ary

    private

    def rack_body
      if @raw_body
        @raw_body
      elsif @body.is_a?(String)
        [@body]
      elsif @body.nil?
        EMPTY_BODY
      else
        @body
      end
    end
  end
end
