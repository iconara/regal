require 'rack'

module Regal
  module App
    def self.create(*args, &block)
      Class.new(Route).create(nil, &block)
    end

    def self.new(*args, &block)
      create(&block).new(*args)
    end
  end

  module RouterDsl
    attr_reader :name

    def create(name=nil, &block)
      @mounted_apps = []
      @static_routes = {}
      @dynamic_route = nil
      @handlers = {}
      @befores = []
      @afters = []
      @setups = []
      @name = name
      class_exec(&block)
      self
    end

    def setups
      if superclass.respond_to?(:setups) && (setups = superclass.setups)
        setups + @setups
      else
        @setups && @setups.dup
      end
    end

    def befores
      if superclass.respond_to?(:befores) && (befores = superclass.befores)
        befores + @befores
      else
        @befores && @befores.dup
      end
    end

    def afters
      if superclass.respond_to?(:afters) && (afters = superclass.afters)
        afters + @afters
      else
        @afters && @afters.dup
      end
    end

    def create_routes(args)
      routes = {}
      if @dynamic_route
        routes.default = @dynamic_route.new(*args)
      end
      @mounted_apps.each do |app|
        routes.merge!(app.create_routes(args))
      end
      @static_routes.each do |path, cls|
        routes[path] = cls.new(*args)
      end
      routes
    end

    def handlers
      @handlers.dup
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

    def setup(&block)
      @setups << block
    end

    def before(&block)
      @befores << block
    end

    def after(&block)
      @afters << block
    end

    [:get, :head, :options, :delete, :post, :put, :patch].each do |name|
      upcased_name = name.to_s.upcase
      define_method(name) do |&block|
        @handlers[upcased_name] = block
      end
    end

    def any(&block)
      @handlers.default = block
    end
  end

  class Route
    extend RouterDsl

    SLASH = '/'.freeze
    PATH_CAPTURES_KEY = 'regal.path_captures'.freeze
    METHOD_NOT_ALLOWED_RESPONSE = [405, {}.freeze, [].freeze].freeze
    NOT_FOUND_RESPONSE = [404, {}.freeze, [].freeze].freeze
    EMPTY_BODY = ''.freeze

    attr_reader :name

    def initialize(*args)
      @actual = self.dup
      self.class.setups.each do |setup|
        @actual.instance_exec(*args, &setup)
      end
      @befores = self.class.befores
      @afters = self.class.afters.reverse
      @routes = self.class.create_routes(args)
      @handlers = self.class.handlers
      @name = self.class.name
      freeze
    end

    def call(env)
      path_components = env[Rack::PATH_INFO].split(SLASH)
      path_components.shift
      env[PATH_CAPTURES_KEY] = {}
      internal_call(env, path_components)
    end

    def internal_call(env, path_components)
      if path_components.empty?
        if (handler = @handlers[env[Rack::REQUEST_METHOD]])
          request = Request.new(env)
          response = Response.new
          @befores.each do |before|
            @actual.instance_exec(request, response, &before)
          end
          response.body = @actual.instance_exec(request, response, &handler)
          @afters.each do |after|
            @actual.instance_exec(request, response, &after)
          end
          response.body = EMPTY_BODY if request.head?
          response
        else
          METHOD_NOT_ALLOWED_RESPONSE
        end
      elsif (app = @routes[path_components.first])
        unless @routes.key?(path_components.first)
          env[PATH_CAPTURES_KEY][app.name] = path_components.first
        end
        path_components.shift
        app.internal_call(env, path_components)
      else
        NOT_FOUND_RESPONSE
      end
    end
  end
end
