require 'rack'

module Regal
  module App
    def self.create(&block)
      Class.new(Route).create(&block)
    end
  end

  class Route
    class << self
      def create(&block)
        @mounted_apps = []
        @static_routes = {}
        @dynamic_route = nil
        @handlers = {}
        instance_exec(&block)
        self
      end

      def route(s, &block)
        @static_routes[s] = Class.new(self).create(&block)
      end

      def mount(app)
        @mounted_apps << app
      end

      def get(&block)
        @handlers['GET'] = block
      end

      def resolve(path_components, request_method)
        app = path_components.reduce(self) do |app, path_component|
          app && app.find_route(path_component)
        end
        app && app.find_handler(request_method)
      end

      def find_route(path_component)
        if (app = @static_routes[path_component])
          app
        else
          @mounted_apps.each do |a|
            if (r = a.find_route(path_component))
              return r
            end
          end
          nil
        end
      end

      def find_handler(request_method)
        @handlers[request_method]
      end
    end

    SLASH = '/'.freeze

    def call(env)
      request_method = env[Rack::REQUEST_METHOD]
      path_components = env[Rack::PATH_INFO].split(SLASH)
      path_components.shift
      handler = self.class.resolve(path_components, request_method)
      if handler
        body = instance_exec(&handler)
        [200, {}, [body]]
      else
        [404, {}, []]
      end
    end
  end
end
