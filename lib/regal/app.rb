require 'rack'

module Regal
  module App
    def self.create(&block)
      Class.new(Route).create(nil, &block)
    end

    def self.new(attributes={}, &block)
      create(&block).new(attributes)
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
      @middlewares = []
      @rescuers = []
      @name = name
      class_exec(&block)
      self
    end

    def befores
      @befores.dup
    end

    def afters
      @afters.dup
    end

    def rescuers
      @rescuers.dup
    end

    def apply_middleware(app)
      @middlewares.reduce(app) do |app, (middleware, args, block)|
        middleware.new(app, *args, &block)
      end
    end

    def create_routes(attributes)
      routes = {}
      @mounted_apps.each do |app|
        mounted_routes = app.create_routes(attributes).each_with_object({}) do |(name, route), r|
          r[name] = app.apply_middleware(MountGraft.new(app, route))
        end
        routes.merge!(mounted_routes)
      end
      @static_routes.each do |path, cls|
        routes[path] = cls.new(attributes)
      end
      if @dynamic_route
        routes.default = @dynamic_route.new(attributes)
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

  REQUEST_KEY = 'regal.request'.freeze
  RESPONSE_KEY = 'regal.response'.freeze
  BEFORES_KEY = 'regal.before'.freeze
  AFTERS_KEY = 'regal.after'.freeze
  RESCUERS_KEY = 'regal.rescue_from'.freeze
  PATH_CAPTURES_KEY = 'regal.path_captures'.freeze
  PATH_COMPONENTS_KEY = 'regal.path_components'.freeze

  module Preparations
    SLASH = '/'.freeze
    PATH_INFO_KEY = 'PATH_INFO'.freeze

    def prepare(env)
      env[REQUEST_KEY] ||= Request.new(env)
      env[RESPONSE_KEY] ||= Response.new
      env[PATH_COMPONENTS_KEY] ||= env[PATH_INFO_KEY].split(SLASH).drop(1)
      befores = (env[BEFORES_KEY] ||= [])
      befores.concat(@befores)
      afters = (env[AFTERS_KEY] ||= [])
      afters.concat(@afters.reverse)
      rescuers = (env[RESCUERS_KEY] ||= [])
      rescuers.concat(@rescuers)
    end
  end

  class AppContext
    attr_reader :attributes

    def initialize(attributes)
      @attributes = attributes.dup.freeze
    end
  end

  class Route
    extend RouterDsl
    include Preparations

    METHOD_NOT_ALLOWED_RESPONSE = [405, {}.freeze, [].freeze].freeze
    NOT_FOUND_RESPONSE = [404, {}.freeze, [].freeze].freeze
    EMPTY_BODY = ''.freeze
    REQUEST_METHOD_KEY = 'REQUEST_METHOD'.freeze

    attr_reader :name

    def self.new(attributes={})
      apply_middleware(allocate.send(:initialize, attributes))
    end

    def initialize(attributes)
      @actual = self.dup
      @app_context = AppContext.new(attributes)
      @befores = self.class.befores
      @afters = self.class.afters.reverse
      @rescuers = self.class.rescuers
      @routes = self.class.create_routes(attributes)
      @handlers = self.class.handlers
      @name = self.class.name
      freeze
    end

    def call(env)
      prepare(env)
      path_component = env[Regal::PATH_COMPONENTS_KEY].shift
      if path_component && (app = @routes[path_component])
        dynamic_route = !@routes.key?(path_component)
        if dynamic_route
          env[Regal::PATH_CAPTURES_KEY] ||= {}
          env[Regal::PATH_CAPTURES_KEY][app.name] = path_component
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
        begin
          request = env[Regal::REQUEST_KEY]
          response = env[Regal::RESPONSE_KEY]
          env[Regal::BEFORES_KEY].each do |before|
            unless response.finished?
              @actual.instance_exec(request, response, @app_context, &before)
            end
          end
          unless response.finished?
            result = @actual.instance_exec(request, response, @app_context, &handler)
            if request.head? || response.status < 200 || response.status == 204 || response.status == 205 || response.status == 304
              response.no_body
            elsif !response.finished?
              response.body = result
            end
          end
        rescue => e
          handle_error(e, request, response, env)
        end
        env[Regal::AFTERS_KEY].reverse_each do |after|
          begin
            @actual.instance_exec(request, response, @app_context, &after)
          rescue => e
            handle_error(e, request, response, env)
          end
        end
        response
      else
        METHOD_NOT_ALLOWED_RESPONSE
      end
    end

    def handle_error(e, request, response, env)
      env[Regal::RESCUERS_KEY].reverse_each do |type, handler|
        if type === e
          @actual.instance_exec(e, request, response, @app_context, &handler)
          return
        end
      end
      raise e
    end
  end

  class MountGraft
    include Preparations

    def initialize(mounted_app, route)
      @befores = mounted_app.befores
      @afters = mounted_app.afters
      @rescuers = mounted_app.rescuers
      @route = route
    end

    def call(env)
      prepare(env)
      @route.call(env)
    end
  end
end
