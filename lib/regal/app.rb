require 'rack'

module Regal
  module App
    # Creates a new app described by the given block.
    #
    # @yield []
    # @return [Class<Route>]
    def self.create(&block)
      Class.new(Route).create(&block)
    end

    # Creates a new app and instantiates it.
    #
    # This is the same as `App.create { }.new(attributes)`.
    #
    # @param [Hash] attributes
    # @yield []
    # @return [Route]
    def self.new(attributes={}, &block)
      create(&block).new(attributes)
    end
  end

  module RoutesDsl
    # @private
    attr_reader :name,
                :befores,
                :afters,
                :rescuers,
                :handlers

    # @private
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

    # @private
    def create_routes(attributes)
      routes = {}
      @mounted_apps.each do |app|
        mounted_routes = app.create_routes(attributes)
        mounted_routes.merge!(mounted_routes) do |name, route, _|
          MountGraft.new(app, route)
        end
        routes.merge!(mounted_routes)
        routes.default = mounted_routes.default
      end
      @routes.each do |path, cls|
        routes[path] = cls.new(attributes)
      end
      if @routes.default
        routes.default = @routes.default.new(attributes)
      end
      routes
    end

    # Defines a route.
    #
    # A route is either static or dynamic. Static routes match request path
    # components verbatim, whereas dynamic routes captures their value. A
    # static route is defined by a string and a dynamic route by a symbol.
    #
    # When routes are matched during request handling a static route will match
    # if it is exactly equal to the next path component. A dynamic route will
    # always match. All static routes are tried before any dynamic route.
    #
    # A route can only have a single dynamic child route. If you declare multiple
    # dynamic routes only the last one is kept.
    #
    # @param [String, Symbol] s either a string, which creates a static route
    #   that matches a path component exactly, or a symbol, which captures the
    #   value of the path component.
    # @yield []
    # @return [void]
    def route(s, &block)
      r = Class.new(self).create(s, &block)
      if s.is_a?(Symbol)
        @routes.default = r
      else
        @routes[s] = r
      end
      nil
    end

    # Mount a child app.
    #
    # Mounting a child app makes that app's routes available as if they were
    # defined in this route.
    #
    # @param [Class<Route>] app
    # @return [void]
    def mount(app)
      @mounted_apps << app
      nil
    end

    # Wrap the child routes and handlers in a scope.
    #
    # Scopes can have before, after and rescue blocks that are not shared with
    # sibling scopes. They work more or less like mounting apps, but inline.
    #
    # @yield []
    # @return [void]
    def scope(&block)
      mount(Class.new(self).create(&block))
    end

    # Register a before block for this route.
    #
    # Before blocks run before the request handler and have access to the
    # request and response.
    #
    # A route can have any number of before blocks and they will be called
    # in the order that they are declared with the outermost route's before
    # blocks being called first, followed by child routes.
    #
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @return [void]
    def before(&block)
      @befores << block
      nil
    end

    # Register an after block for this route.
    #
    # After blocks run after the request handler and have access to the
    # request and response.
    #
    # A route can have any number of after blocks and they will be called
    # in the order that they are declared with the innermost route's after
    # blocks being called first, followed by the parent route.
    #
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @return [void]
    def after(&block)
      @afters << block
      nil
    end

    # Register a rescue block for this route.
    #
    # Rescue blocks run when a before or after block, or a handler raises
    # an error that matches the block's error type (compared using `#===`).
    #
    # A route can have any number of rescue blocks, but the order they are
    # declared in is important. When an error is raised the blocks are searched
    # in reverse order for a match, so the last declared rescue block with a
    # matching type will be the one to handle the error.
    #
    # Once an error handler has been called the error is assumed to have been
    # handled. If the error handler raises an error, the next matching handler
    # will be found, or the error will bubble up outside the app.
    #
    # @param [Class<Error>] type
    # @yield [error, request, response]
    # @yieldparam error [Error]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @return [void]
    def rescue_from(type, &block)
      @rescuers << [type, block]
      nil
    end

    [:get, :head, :options, :delete, :post, :put, :patch].each do |name|
      upcased_name = name.to_s.upcase
      define_method(name) do |&block|
        @handlers[upcased_name] = block
      end
    end

    # @!group Handlers

    # Register a handler for `GET` requests to this route
    #
    # @!method get
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `HEAD` requests to this route
    #
    # @!method head
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `OPTIONS` requests to this route
    #
    # @!method options
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `DELETE` requests to this route
    #
    # @!method delete
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `POST` requests to this route
    #
    # @!method post
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `PUT` requests to this route
    #
    # @!method put
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for `PATCH` requests to this route
    #
    # @!method patch
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]

    # Register a handler for any request method
    #
    # `any` handlers are called when there is no specific handler in this route
    # for the request method.
    #
    # @yield [request, response]
    # @yieldparam request [Request]
    # @yieldparam response [Response]
    # @yieldreturn [Object] the response body
    # @return [void]
    def any(&block)
      @handlers.default = block
    end

    # @!endgroup
  end

  # @private
  module Arounds
    def before(request, response)
      @befores.each do |before|
        unless response.finished?
          @route.instance_exec(request, response, &before)
        end
      end
    end

    def after(request, response)
      @afters.each do |after|
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

  # A route is an application, or a part of an application
  class Route
    extend RoutesDsl
    include Arounds

    # @private
    attr_reader :name,
                :routes

    # Create a new application with this route as its root
    #
    # @param [Hash] attributes a copy of this hash will be available
    #   from {Request#attributes} during request processing
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

    # Route and handle a request
    #
    # @param [Hash] env
    # @return [Array<(Integer, Hash, Enumerable)>]
    def call(env)
      path_components = path_components = env[PATH_INFO_KEY].split(SLASH).drop(1)
      parent_routes, path_captures = match_route(path_components)
      matching_route = parent_routes.last
      request_method = env[REQUEST_METHOD_KEY]
      if matching_route && matching_route.can_handle?(request_method)
        request = Request.new(env, path_captures, @attributes)
        response = Response.new
        finishing_route = run_befores(parent_routes, request, response)
        if finishing_route.nil? && !response.finished?
          begin
            result = matching_route.handle(request_method, request, response)
            unless response.finished?
              response.body = result
            end
          rescue => e
            finishing_route = handle_error(parent_routes, finishing_route, e, request, response)
          end
        end
        run_afters(parent_routes, finishing_route, request, response)
        if no_body_response?(request_method, response)
          response.no_body
        end
        response
      elsif matching_route
        [405, {}, []]
      else
        [404, {}, []]
      end
    end

    # @private
    def can_handle?(request_method)
      !!@handlers[request_method]
    end

    # @private
    def handle(request_method, request, response)
      handler = @handlers[request_method]
      instance_exec(request, response, &handler)
    end

    private

    SLASH = '/'.freeze
    PATH_INFO_KEY = 'PATH_INFO'.freeze
    REQUEST_METHOD_KEY = 'REQUEST_METHOD'.freeze
    HEAD_METHOD = 'HEAD'.freeze

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
            skip_routes = true
            finishing_route = handle_error(parent_routes, parent_route, e, request, response)
          end
        end
      end
    end

    def handle_error(parent_routes, finishing_route, e, request, response)
      skip_routes = !finishing_route.nil?
      parent_routes.reverse_each do |parent_route|
        if !skip_routes || finishing_route == parent_route
          skip_routes = false
          begin
            if parent_route.rescue_error(e, request, response)
              return parent_route
            end
          rescue => e
            if parent_routes.first == parent_route
              raise e
            else
              next_level = parent_routes[parent_routes.index(parent_route) - 1]
              return handle_error(parent_routes, next_level, e, request, response)
            end
          end
        end
      end
      raise e
    end
  end

  # @private
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
