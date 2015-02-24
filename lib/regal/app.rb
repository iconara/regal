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
    attr_reader :name,
                :befores,
                :afters,
                :rescuers,
                :handlers

    def create(name=nil, &block)
      @name = name
      @mounted_apps = []
      @routes = {}
      @handlers = {}
      @befores = []
      @afters = []
      @rescuers = []
      class_exec(&block)
      @mounted_apps.freeze
      @routes.freeze
      @handlers.freeze
      @befores.freeze
      @afters.freeze
      @rescuers.freeze
      self
    end

    def create_routes(attributes)
      routes = {}
      @mounted_apps.each do |app|
        mounted_routes = app.create_routes(attributes)
        mounted_routes.merge!(mounted_routes) do |name, route, _|
          MountGraft.new(app, route)
        end
        routes.merge!(mounted_routes)
      end
      @routes.each do |path, cls|
        routes[path] = cls.new(attributes)
      end
      if @routes.default
        routes.default = @routes.default.new(attributes)
      end
      routes
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

    def scope(&block)
      mount(Class.new(self).create(&block))
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

  module Arounds
    def before(request, response)
      @befores.each do |before|
        unless response.finished?
          @route.instance_exec(request, response, &before)
        end
      end
    end

    def after(request, response)
      @afters.reverse_each do |after|
        begin
          @route.instance_exec(request, response, &after)
        rescue => e
          raise unless rescue_error(e, request, response)
        end
      end
    end

    def rescue_error(e, request, response)
      @rescuers.reverse_each do |type, handler|
        if type === e
          @route.instance_exec(e, request, response, &handler)
          return true
        end
      end
      false
    end
  end

  class Route
    extend RouterDsl
    include Arounds

    METHOD_NOT_ALLOWED_RESPONSE = [405, {}.freeze, [].freeze].freeze
    NOT_FOUND_RESPONSE = [404, {}.freeze, [].freeze].freeze
    SLASH = '/'.freeze
    PATH_INFO_KEY = 'PATH_INFO'.freeze
    REQUEST_METHOD_KEY = 'REQUEST_METHOD'.freeze
    HEAD_METHOD = 'HEAD'.freeze

    attr_reader :name,
                :routes

    def initialize(attributes)
      @attributes = attributes.dup.freeze
      @name = self.class.name
      @befores = self.class.befores
      @afters = self.class.afters
      @rescuers = self.class.rescuers
      @handlers = self.class.handlers
      @routes = self.class.create_routes(attributes)
      @route = self
      freeze
    end

    def call(env)
      path_components = path_components = env[PATH_INFO_KEY].split(SLASH).drop(1)
      parent_routes, path_captures = match_route(path_components)
      matching_route = parent_routes.last
      request_method = env[REQUEST_METHOD_KEY]
      if matching_route && matching_route.can_handle?(request_method)
        request = Request.new(env, path_captures, @attributes)
        response = Response.new
        finishing_route = nil
        begin
          finishing_route = run_befores(parent_routes, request, response)
          unless response.finished?
            result = matching_route.handle(request_method, request, response)
            unless response.finished?
              response.body = result
            end
          end
        rescue => e
          handle_error(parent_routes, finishing_route, e, request, response)
        end
        run_afters(parent_routes, finishing_route, request, response)
        if no_body_response?(request_method, response)
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

    def handle(request_method, request, response)
      handler = @handlers[request_method]
      instance_exec(request, response, &handler)
    end

    private

    def no_body_response?(request_method, response)
      request_method == HEAD_METHOD || response.status < 200 || response.status == 204 || response.status == 205 || response.status == 304
    end

    def match_route(path_components)
      path_captures = {}
      matching_route = self
      parent_routes = [self]
      path_components.each do |path_component|
        if matching_route
          wildcard_route = !matching_route.routes.include?(path_component)
          matching_route = matching_route.routes[path_component]
          if matching_route && wildcard_route
            path_captures[matching_route.name] = path_component
          end
        end
        parent_routes << matching_route
      end
      [parent_routes, path_captures]
    end

    def run_befores(parent_routes, request, response)
      parent_routes.each do |parent_route|
        begin
          parent_route.before(request, response)
          if response.finished?
            return parent_route
          end
        rescue => e
          response.finish
          return handle_error(parent_routes, parent_route, e, request, response)
        end
      end
      nil
    end

    def run_afters(parent_routes, finishing_route, request, response)
      skip_routes = !finishing_route.nil?
      parent_routes.reverse_each do |parent_route|
        if !skip_routes || finishing_route == parent_route
          skip_routes = false
          begin
            parent_route.after(request, response)
          rescue => e
            handle_error(parent_routes, parent_route, e, request, response)
          end
        end
      end
    end

    def handle_error(parent_routes, finishing_route, e, request, response)
      skip_routes = !finishing_route.nil?
      parent_routes.reverse_each do |parent_route|
        if !skip_routes || finishing_route == parent_route
          skip_routes = false
          if parent_route.rescue_error(e, request, response)
            return parent_route
          end
        end
      end
      raise e
    end
  end

  class MountGraft
    include Arounds

    attr_reader :name,
                :routes

    def initialize(mounted_app, route)
      @route = route
      @name = route.name
      @routes = route.routes
      @befores = mounted_app.befores
      @afters = mounted_app.afters
      @rescuers = mounted_app.rescuers
    end

    def can_handle?(request_method)
      @route.can_handle?(request_method)
    end

    def handle(*args)
      @route.handle(*args)
    end

    def before(*args)
      super
      @route.before(*args)
    end

    def after(*args)
      @route.after(*args)
      super
    end

    def rescue_error(e, *args)
      @route.rescue_error(e, *args) or super
    end
  end
end
