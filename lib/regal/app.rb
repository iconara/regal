require 'rack'

module Regal
  module App
    def self.create(&block)
      Class.new(Route).create(&block)
    end
  end

  module RouterDsl
    attr_reader :static_routes,
                :dynamic_route,
                :mounted_apps,
                :handlers,
                :name

    def create(name=nil, &block)
      @mounted_apps = []
      @static_routes = {}
      @dynamic_route = nil
      @handlers = {}
      @name = name
      instance_exec(&block)
      self
    end

    def route(s, &block)
      r = Class.new(self).create(s, &block)
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

    def post(&block)
      @handlers['POST'] = block
    end
  end

  class Route
    extend RouterDsl

    SLASH = '/'.freeze
    PATH_CAPTURES_KEY = 'regal.path_captures'.freeze

    attr_reader :name

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
      @name = self.class.name
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
          response = Response.new
          response.body = instance_exec(request, response, &handler)
          response
        else
          [405, {}, []]
        end
      elsif (app = @static_routes[path_components.first])
        path_components.shift
        app.internal_call(env, path_components)
      elsif @dynamic_route
        env[PATH_CAPTURES_KEY][@dynamic_route.name] = path_components.shift
        @dynamic_route.internal_call(env, path_components)
      else
        [404, {}, []]
      end
    end
  end
end
