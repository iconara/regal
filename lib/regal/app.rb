require 'rack'

module Regal
  module App
    def self.create(&block)
      Class.new(Route).create(&block)
    end

    def self.new(attributes={}, &block)
      create(&block).new(attributes)
    end
  end

  module RouterDsl
    attr_reader :name

    def create(name=nil, &block)
      @name = name
      @mounted_apps = []
      @routes = {}
      @handlers = {}
      @befores = []
      @afters = []
      @middlewares = []
      @rescuers = []
      class_exec(&block)
      @mounted_apps.freeze
      @routes.freeze
      @handlers.freeze
      @befores.freeze
      @afters.freeze
      @middlewares.freeze
      @rescuers.freeze
      self
    end

    def befores
      Array(@befores)
    end

    def afters
      Array(@afters)
    end

    def rescuers
      Array(@rescuers)
    end

    def middlewares
      Array(@middlewares)
    end

    def create_routes(attributes, middlewares)
      routes = {}
      middlewares = Array(middlewares)
      @mounted_apps.each do |app|
        mounted_middlewares = middlewares + app.middlewares
        mounted_routes = app.create_routes(attributes, mounted_middlewares)
        mounted_routes.merge!(mounted_routes) do |name, route, _|
          MountGraft.new(app, route)
        end
        routes.merge!(mounted_routes)
      end
      @routes.each do |path, cls|
        routes[path] = cls.new(attributes, middlewares)
      end
      if @routes.default
        routes.default = @routes.default.new(attributes, middlewares)
      end
      routes
    end

    def handlers
      @handlers.dup
    end

    def route(s, &block)
      r = Class.new(self).create(s, &block)
      if s.is_a?(Symbol)
        @routes.default = r
      else
        @routes[s] = r
      end
    end

    def mount(app)
      @mounted_apps << app
    end

    def use(middleware, *args, &block)
      @middlewares << [middleware, args, block]
    end

    def before(&block)
      @befores << block
    end

    def after(&block)
      @afters << block
    end

    def rescue_from(type, &block)
      @rescuers << [type, block]
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

  PATH_CAPTURES_KEY = 'regal.path_captures'.freeze

  class AppContext
    attr_reader :attributes

    def initialize(attributes)
      @attributes = attributes.dup.freeze
    end
  end

  class Route
    extend RouterDsl

    METHOD_NOT_ALLOWED_RESPONSE = [405, {}.freeze, [].freeze].freeze
    NOT_FOUND_RESPONSE = [404, {}.freeze, [].freeze].freeze
    SLASH = '/'.freeze
    PATH_INFO_KEY = 'PATH_INFO'.freeze
    REQUEST_METHOD_KEY = 'REQUEST_METHOD'.freeze

    attr_reader :name,
                :routes,
                :handlers

    def initialize(attributes, middlewares=nil)
      middlewares = Array(middlewares) + self.class.middlewares
      @attributes = attributes.dup.freeze
      @name = self.class.name
      @befores = self.class.befores
      @afters = self.class.afters
      @rescuers = self.class.rescuers
      @routes = self.class.create_routes(attributes, middlewares)
      setup_handlers(middlewares)
      freeze
    end

    def call(env)
      path_components = env[PATH_INFO_KEY].split(SLASH).drop(1)
      path_captures = {}
      matching_route = self
      parent_routes = []
      path_components.each do |path_component|
        if matching_route
          parent_route = matching_route
          parent_routes << parent_route
          matching_route = matching_route.routes[path_component]
          if matching_route && !parent_route.routes.include?(path_component)
            path_captures[matching_route.name] = path_component
          end
        end
      end
      request_method = env[REQUEST_METHOD_KEY]
      if matching_route && matching_route.can_handle?(request_method)
        env[PATH_CAPTURES_KEY] = path_captures
        parent_routes << matching_route
        request = Request.new(env, @attributes)
        response = Response.new
        begin
          parent_routes.each do |parent_route|
            parent_route.before(request, response)
          end
          env['regal.request'] = request
          env['regal.response'] = response
          matching_route.handle(request_method, env)
        rescue => e
          handle_error(parent_routes, e, request, response)
        end
        parent_routes.reverse_each do |parent_route|
          begin
            parent_route.after(request, response)
          rescue => e
            handle_error(parent_routes, e, request, response)
          end
        end
        if request.head? || response.status < 200 || response.status == 204 || response.status == 205 || response.status == 304
          response.no_body
        end
        response
      elsif matching_route
        METHOD_NOT_ALLOWED_RESPONSE
      else
        NOT_FOUND_RESPONSE
      end
    end

    def can_handle?(request_method)
      !!@handlers[request_method]
    end

    def handle(request_method, env)
      @handlers[request_method].call(env)
    end

    def before(request, response)
      @befores.each do |before|
        unless response.finished?
          instance_exec(request, response, &before)
        end
      end
    end

    def after(request, response)
      @afters.reverse_each do |after|
        begin
          instance_exec(request, response, &after)
        rescue => e
          raise unless rescue_error(e, request, response)
        end
      end
    end

    def rescue_error(e, request, response)
      @rescuers.reverse_each do |type, handler|
        if type === e
          instance_exec(e, request, response, &handler)
          return true
        end
      end
      false
    end

    private

    def handle_error(parent_routes, e, request, response)
      parent_routes.reverse_each do |parent_route|
        return if parent_route.rescue_error(e, request, response)
      end
      raise e
    end

    def setup_handlers(middlewares)
      if middlewares.nil? || middlewares.empty?
        @handlers = self.class.handlers
        @handlers.merge!(@handlers) do |_, handler, _|
          Handler.new(self, handler)
        end
        if @handlers.default
          @handlers.default = Handler.new(self, @handlers.default)
        end
      else
        @handlers = self.class.handlers
        @handlers.merge!(@handlers) do |_, handler, _|
          wrap_in_middleware(middlewares, Handler.new(self, handler))
        end
        if @handlers.default
          @handlers.default = wrap_in_middleware(middlewares, Handler.new(self, @handlers.default))
        end
      end
    end

    def wrap_in_middleware(middlewares, app)
      middlewares.reduce(app) do |app, (middleware, args, block)|
        middleware.new(app, *args, &block)
      end
    end
  end

  class Handler
    def initialize(route, handler)
      @route = route
      @handler = handler
    end

    def call(env)
      request = env['regal.request']
      response = env['regal.response']
      result = @route.instance_exec(request, response, &@handler)
      unless response.finished?
        response.body = result
      end
      response
    end
  end

  module Graft
    attr_reader :name,
                :routes

    def can_handle?(request_method)
      @route.can_handle?(request_method)
    end

    def handle(*args)
      @route.handle(*args)
    end

    def before(*args)
      @route.before(*args)
    end

    def after(*args)
      @route.after(*args)
    end

    def rescue_error(*args)
      @route.rescue_error(*args)
    end
  end

  class MountGraft
    include Graft

    def initialize(mounted_app, route)
      @route = route
      @name = route.name
      @routes = route.routes
      @befores = mounted_app.befores
      @afters = mounted_app.afters
      @rescuers = mounted_app.rescuers
    end

    def before(*args)
      @befores.each do |before|
        @route.instance_exec(*args, &before)
      end
      super
    end

    def after(*args)
      super
      @afters.reverse_each do |after|
        begin
          @route.instance_exec(*args, &after)
        rescue => e
          raise unless rescue_error(e, *args)
        end
      end
    end

    def rescue_error(e, *args)
      if super
        true
      else
        @rescuers.reverse_each do |type, handler|
          if type === e
            instance_exec(e, *args, &handler)
            return true
          end
        end
        false
      end
    end
  end
end
