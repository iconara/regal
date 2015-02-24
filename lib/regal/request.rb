module Regal
  class Request
    attr_reader :env, :attributes

    def initialize(env, path_captures, attributes_prototype={})
      @env = env
      @path_captures = path_captures
      @attributes = attributes_prototype.dup
    end

    def parameters
      @parameters ||= begin
        query = Rack::Utils.parse_query(@env[QUERY_STRING_KEY])
        query.merge!(@path_captures)
        query.freeze
      end
    end

    def headers
      @headers ||= begin
        headers = @env.each_with_object({}) do |(key, value), headers|
          if key.start_with?(HEADER_PREFIX)
            normalized_key = key[HEADER_PREFIX.length, key.length - HEADER_PREFIX.length]
            normalized_key.gsub!(/(?<=^.|_.)[^_]+/) { |str| str.downcase }
            normalized_key.gsub!('_', '-')
          elsif key == CONTENT_LENGTH_KEY
            normalized_key = CONTENT_LENGTH_HEADER
          elsif key == CONTENT_TYPE_KEY
            normalized_key = CONTENT_TYPE_HEADER
          end
          if normalized_key
            headers[normalized_key] = value
          end
        end
        headers.freeze
      end
    end

    def body
      @env[RACK_INPUT_KEY]
    end

    HEADER_PREFIX = 'HTTP_'.freeze
    QUERY_STRING_KEY = 'QUERY_STRING'.freeze
    CONTENT_LENGTH_KEY = 'CONTENT_LENGTH'.freeze
    CONTENT_LENGTH_HEADER = 'Content-Length'.freeze
    CONTENT_TYPE_KEY = 'CONTENT_TYPE'.freeze
    CONTENT_TYPE_HEADER = 'Content-Type'.freeze
    RACK_INPUT_KEY = 'rack.input'.freeze
  end
end
