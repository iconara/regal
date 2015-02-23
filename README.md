# Regal ♔

[![Build Status](https://travis-ci.org/iconara/regal.png?branch=master)](https://travis-ci.org/iconara/regal)
[![Coverage Status](https://coveralls.io/repos/iconara/regal/badge.png)](https://coveralls.io/r/iconara/regal)
[![Blog](http://b.repl.ca/v1/blog-regal-ff69b4.png)](http://architecturalatrocities.com/tagged/regal)

_If you're reading this on GitHub, please note that this is the readme for the development version and that some features described here might not yet have been released. You can find the readme for a specific version either through [rubydoc.info](http://rubydoc.info/find/gems?q=regal) or via the release tags ([here is an example](https://github.com/iconara/regal/tree/v0.1.0))._

Regal is a Rack framework where you model your application as a tree of routes.

## Just give me an example already

Stick this in a `config.ru` and `rackup`:

```ruby
require 'regal'
require 'json'

# Regal apps are classes, so you can create multiple
# instances of them with different configuration
ThingsApp = Regal::App.create do
  # you build your app up by defining routes, these
  # map directly to the request path, so this route
  # matches requests that begin with /things
  route 'things' do
    # a route can have a handler for each HTTP method, these
    # are passed request and response objects, but unless you
    # need them you can leave those out, like this one does
    #
    # the response is what is returned from the handler, but
    # below you will see how to make sure it's formatted properly
    get do |request|
      # when you create an instance of an app you can give it a hash,
      # a copy of this hash is available through request.attributes,
      # and is shared between all before, after and rescue blocks, as
      # well as the handler blocks, like here
      request.attributes[:database].values
    end

    # this handler uses both the request and the response
    post do |request, response|
      # request bodies are easily available
      thing = JSON.load(request.body.read)
      request.attributes[:database].store(thing['name'], thing)
      # this is how you set the response code and headers
      response.status = 201
      response.headers['Location'] = '/things'
      # the handler's return value will be set as response body
      thing
    end

    # routes with symbols are wildcards and capture their value, so for the
    # path /things/bees the parameter `:thing` will get the value "bees"
    route :thing do
      # helper methods don't need to be defined in special `helper` blocks,
      # they can be defined like this
      #
      # they are available in all child routes, but not sibling routes
      def find_thing(database, name)
        database.fetch(name)
      end

      # rescue_from works a bit like regular rescue, if any before or after
      # block, or handler in this or any child route raises an error, the
      # first matching `rescue_from` block will be called – and unless it
      # re-raises the error it is assumed to have been handled and the after
      # blocks will be called
      rescue_from KeyError do |error, request, response|
        response.status = 404
        response.body = {'error' => 'Thing not found'}
      end

      # before blocks run before the handler and can inspect the request
      # and stop the request processing by calling #finish on the response
      before do |request, response|
        thing = find_thing(request.attributes[:database], request.parameters[:thing])
        if thing
          # before blocks can communicate with other before blocks, handlers
          # and after blocks by setting request attributes
          #
          # it might look like this is a way to share things between requests,
          # but each request has its own copy, so anything you add is only
          # going to be accessible during the request
          #
          # you're of course allowed to put mutable objects in the attributes,
          # like this app's `:database`, which makes it possible to share
          # things between requests
          request.attributes[:thing] = thing
        else
          response.status = 404
          response.body = {'error' => 'Not Found'}
          # finish will stop all remaining before blocks and the handler
          # from running, but after blocks (see below) will still run
          response.finish
        end
      end

      get do |request|
        # this will not run if a before block stops the request processing
        # and it can access anything that the before blocks have put in
        # the attributes hash
        request.attributes[:thing]
      end
    end
  end

  # this handler is defined at the top level, I just defined it down here
  # because it's not very important in this app, the order doesn't matter
  get do |request, response|
    response.headers['Location'] = '/things'
    response.status = 302
    # when you don't want to send any body you can call #no_body on the
    # response, it doesn't matter where you do it, it doesn't have to be last
    response.no_body
  end

  # after all of the request handling has been done the after blocks are called
  # and they get to do whatever they like with the response, for example
  # turning it into JSON, like this
  after do |request, response|
    response.headers['Content-Type'] = 'application/json'
    response.body = JSON.pretty_generate(response.body) << "\n"
  end
end

# to run your app with Rack you need to create an instance,
# the arguments you pass here are available as request.attributes
run ThingsApp.new(database: {})
```

You can do lots more with Regal, check out the tests to see more.

# How to contribute

[See CONTRIBUTING.md](CONTRIBUTING.md)

# Regal?

Besides being the Rack framework for kings and queens, the name can be roughly translated from German as "rack".

# Copyright

Copyright 2015 Theo Hultberg/Iconara and contributors.

_Licensed under the BSD 3-Clause license see [http://opensource.org/licenses/BSD-3-Clause](http://opensource.org/licenses/BSD-3-Clause)_
