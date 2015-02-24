module Regal
  class Response
    # @!attribute [rw] status
    # @return [Hash]

    # @!attribute [rw] body
    # @return [Object]

    # @!attribute [rw] raw_body
    # @return [Enumerable]

    # @!attribute [r] headers
    # @return [Hash]

    attr_accessor :status, :body, :raw_body
    attr_reader :headers

    EMPTY_BODY = [].freeze

    # @private
    def initialize
      @status = 200
      @headers = {}
      @body = nil
      @raw_body = nil
      @finished = false
    end

    # @return [void]
    def finish
      @finished = true
    end

    # @return [true, false]
    def finished?
      @finished
    end

    # @return [Array<()>]
    def no_body
      @raw_body = EMPTY_BODY
    end

    # @param [Integer] n
    # @return [Integer, Hash, Enumerable]
    def [](n)
      case n
      when 0 then @status
      when 1 then @headers
      when 2 then rack_body
      end
    end

    # @param [Integer] n
    # @param [Integer, Hash, Enumerable] v
    # @return [Integer, Hash, Enumerable]
    def []=(n, v)
      case n
      when 0 then @status = v
      when 1 then @headers = v
      when 2 then @raw_body = v
      end
    end

    # @return [Array<(Integer, Hash, Enumerable)>]
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
