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
        r = Class.new(self).create(&block)
        if s.is_a?(Symbol)
          @dynamic_route = r
        else
          @static_routes[s] = r
        end
      end

      def mount(app)
        @mounted_apps << app
      end

      def get(&block)
        @handlers['GET'] = block
      end

      attr_reader :static_routes, :dynamic_route, :mounted_apps, :handlers
    end

    SLASH = '/'.freeze

    def initialize
      @static_routes = {}
      self.class.mounted_apps.each do |app|
        app.static_routes.each do |path, cls|
          @static_routes[path] = cls.new
        end
      end
      self.class.static_routes.each do |path, cls|
        @static_routes[path] = cls.new
      end
      @dynamic_route = self.class.dynamic_route && self.class.dynamic_route.new
    end

    def call(env)
      path_components = env[Rack::PATH_INFO].split(SLASH)
      path_components.shift
      internal_call(env, path_components)
    end

    def internal_call(env, path_components)
      if path_components.empty?
        if (handler = self.class.handlers[env[Rack::REQUEST_METHOD]])
          body = instance_exec(&handler)
          [200, {}, [body]]
        else
          [405, {}, []]
        end
      elsif (app = @static_routes[path_components.first])
        path_components.shift
        app.internal_call(env, path_components)
      elsif @dynamic_route
        path_components.shift
        @dynamic_route.internal_call(env, path_components)
      else
        [404, {}, []]
      end
    end
  end
end
