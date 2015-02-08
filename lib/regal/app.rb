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
      @middlewares = []
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

    def middlewares
      if superclass.respond_to?(:middlewares) && (middlewares = superclass.middlewares)
        middlewares + @middlewares
      else
        @middlewares && @middlewares.dup
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

    def use(middleware, *args, &block)
      @middlewares << [middleware, args, block]
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
    PATH_COMPONENTS_KEY = 'regal.path_components'.freeze
    PATH_INFO_KEY = 'PATH_INFO'.freeze
    REQUEST_METHOD_KEY = 'REQUEST_METHOD'.freeze
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
      if !self.class.middlewares.empty?
        @app = self.class.middlewares.reduce(method(:handle)) do |app, (middleware, args, block)|
          middleware.new(app, *args, &block)
        end
      end
      freeze
    end

    def call(env)
      path_components = env[PATH_COMPONENTS_KEY] ||= env[PATH_INFO_KEY].split(SLASH).drop(1)
      path_component = path_components.shift
      if path_component && (app = @routes[path_component])
        dynamic_route = !@routes.key?(path_component)
        if dynamic_route
          env[PATH_CAPTURES_KEY] ||= {}
          env[PATH_CAPTURES_KEY][app.name] = path_component
        end
        app.call(env)
      elsif path_component.nil?
        if @app
          @app.call(env)
        else
          handle(env)
        end
      else
        NOT_FOUND_RESPONSE
      end
    end

    private

    def handle(env)
      if (handler = @handlers[env[REQUEST_METHOD_KEY]])
        request = Request.new(env)
        response = Response.new
        @befores.each do |before|
          break if response.finished?
          @actual.instance_exec(request, response, &before)
        end
        unless response.finished?
          result = @actual.instance_exec(request, response, &handler)
          if request.head? || response.status < 200 || response.status == 204 || response.status == 205 || response.status == 304
            response.no_body
          elsif !response.finished?
            response.body = result
          end
        end
        @afters.each do |after|
          @actual.instance_exec(request, response, &after)
        end
        response
      else
        METHOD_NOT_ALLOWED_RESPONSE
      end
    end
  end
end
