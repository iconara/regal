require 'rack'

module Regal
  module App
    def self.create(&block)
      Class.new(Route).create(&block)
    end
  end

  class Route
    class << self
      def create(parameter_name=nil, &block)
        @mounted_apps = []
        @static_routes = {}
        @dynamic_route = nil
        @handlers = {}
        @parameter_name = parameter_name
        instance_exec(&block)
        self
      end

      def route(s, &block)
        r = Class.new(self)
        if s.is_a?(Symbol)
          @dynamic_route = r.create(s, &block)
        else
          @static_routes[s] = r.create(&block)
        end
      end

      def mount(app)
        @mounted_apps << app
      end

      def get(&block)
        @handlers['GET'] = block
      end

      attr_reader :static_routes, :dynamic_route, :mounted_apps, :handlers, :parameter_name
    end

    SLASH = '/'.freeze
    PATH_CAPTURES_KEY = 'regal.path_captures'.freeze

    attr_reader :parameter_name

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
      @parameter_name = self.class.parameter_name
      @dynamic_route = self.class.dynamic_route && self.class.dynamic_route.new
    end

    def call(env)
      path_components = env[Rack::PATH_INFO].split(SLASH)
      path_components.shift
      env[PATH_CAPTURES_KEY] = {}
      internal_call(env, path_components)
    end

    def internal_call(env, path_components)
      if path_components.empty?
        if (handler = self.class.handlers[env[Rack::REQUEST_METHOD]])
          request = Request.new(env)
          body = instance_exec(request, &handler)
          [200, {}, [body]]
        else
          [405, {}, []]
        end
      elsif (app = @static_routes[path_components.first])
        path_components.shift
        app.internal_call(env, path_components)
      elsif @dynamic_route
        env[PATH_CAPTURES_KEY][@dynamic_route.parameter_name] = path_components.shift
        @dynamic_route.internal_call(env, path_components)
      else
        [404, {}, []]
      end
    end
  end
end
