require 'spec_helper'
require 'json'

module Regal
  describe App do
    include Rack::Test::Methods

    context 'a basic app' do
      let :app do
        App.new do
          get do
            'root'
          end

          route 'hello' do
            get do
              'hello'
            end

            route 'world' do
              get do
                'hello world'
              end
            end
          end
        end
      end

      it 'routes a request' do
        get '/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'routes a request to the root' do
        get '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('root')
      end

      it 'routes a request with more than one path component' do
        get '/hello/world'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello world')
      end

      it 'responds with 404 when the path does not match any route' do
        get '/hello/fnord'
        expect(last_response.status).to eq(404)
      end

      it 'responds with 405 when the path matches a route but there is no handler for the HTTP method' do
        delete '/hello/world'
        expect(last_response.status).to eq(405)
      end
    end

    context 'a simple interactive app' do
      let :app do
        App.new do
          route 'echo' do
            get do |request|
              request.parameters['s']
            end

            post do |request|
              request.body.read
            end
          end

          route 'international-hello' do
            get do |request|
              case request.headers['Accept-Language']
              when 'sv_SE'
                'hej'
              when 'fr_FR'
                'bonjour'
              else
                '?'
              end
            end
          end
        end
      end

      it 'can access the query parameters' do
        get '/echo?s=hallo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hallo')
      end

      it 'can access the request headers' do
        get '/international-hello', nil, {'HTTP_ACCEPT_LANGUAGE' => 'sv_SE'}
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hej')
        get '/international-hello', nil, {'HTTP_ACCEPT_LANGUAGE' => 'fr_FR'}
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('bonjour')
      end

      it 'can access the request body' do
        post '/echo', 'blobblobblob'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('blobblobblob')
      end
    end

    context 'an app that does more than just respond with a body' do
      let :app do
        App.new do
          route 'redirect' do
            get do |_, response|
              response.status = 307
              response.headers['Location'] = 'somewhere/else'
            end
          end
        end
      end

      it 'can change the response code' do
        get '/redirect'
        expect(last_response.status).to eq(307)
      end

      it 'can set response headers' do
        get '/redirect'
        expect(last_response.headers).to include('Location' => 'somewhere/else')
      end
    end

    context 'an app doing work before route handlers' do
      MountedBeforeApp = App.create do
        before do |request|
          request.attributes[:some_key] << 2
        end

        route 'in-mounted-app' do
          before do |request|
            request.attributes[:some_key] << 3
          end

          get do |request|
            request.attributes.values.join(',')
          end
        end
      end

      let :state do
        {}
      end

      let :app do
        App.new(state: state) do
          before do |request, _, app|
            request.attributes[:some_key] = [1]
            app.attributes[:state][:before] = :called
          end

          get do |request|
            request.attributes[:some_key].join(',')
          end

          route 'one-before' do
            before do |request|
              request.attributes[:some_key] << 2
            end

            get do |request|
              request.attributes[:some_key].join(',')
            end
          end

          route 'two-before' do
            before do |request|
              request.attributes[:some_key] << 2
            end

            before do |request|
              request.attributes[:some_key] << 3
            end

            get do |request|
              request.attributes[:some_key].join(',')
            end

            route 'another-before' do
              before do |request|
                request.attributes[:some_key] << 4
              end

              get do |request|
                request.attributes[:some_key].join(',')
              end
            end
          end

          route 'redirect-before' do
            before do |_, response|
              response.headers['Location'] = 'somewhere/else'
              response.status = 307
              response.body = 'Go somewhere else'
              response.finish
            end

            before do |_, response|
              response.body = 'whoopiedoo'
            end

            get do
              "I'm not called!"
            end

            after do |_, response|
              response.headers['WasAfterCalled'] = 'yes'
            end
          end

          mount MountedBeforeApp
        end
      end

      it 'calls the before block before the request handler' do
        get '/'
        expect(last_response.body).to eq('1')
      end

      it 'calls the before blocks of all routes before the request handler' do
        get '/one-before'
        expect(last_response.body).to eq('1,2')
      end

      it 'calls the before blocks of a route in order' do
        get '/two-before'
        expect(last_response.body).to eq('1,2,3')
      end

      it 'calls all before blocks of a route before the request handler' do
        get '/two-before/another-before'
        expect(last_response.body).to eq('1,2,3,4')
      end

      it 'gives the before blocks access to the response' do
        get '/redirect-before'
        expect(last_response.status).to eq(307)
      end

      context 'when the path does not match any route' do
        it 'does not run any before blocks' do
          get '/does-not-exist'
          expect(last_response.status).to eq(404)
          expect(state).to be_empty
        end
      end

      context 'when the response is marked as finished' do
        before do
          get '/redirect-before'
        end

        it 'does not call further handlers or before blocks when the response is marked as finished' do
          expect(last_response.body).to eq('Go somewhere else')
        end

        it 'calls after blocks' do
          expect(last_response.headers).to include('WasAfterCalled' => 'yes')
        end
      end

      context 'with a mounted app' do
        it 'runs the before blocks from both the mounting and the mounted app' do
          get '/in-mounted-app'
          expect(last_response.body).to eq('1,2,3')
        end
      end
    end

    context 'an app doing work after route handlers' do
      MountedAfterApp = App.create do
        after do |_, response|
          response.body['list'] << 1
        end

        route 'in-mounted-app' do
          after do |_, response|
            response.body['list'] << 2
          end

          get do
            {'list' => []}
          end
        end
      end

      let :state do
        {}
      end

      let :app do
        App.new(state: state) do
          after do |_, response, app|
            response.headers['Content-Type'] = 'application/json'
            response.body = JSON.dump(response.body)
            app.attributes[:state][:after] = :called
          end

          get do |request|
            {'root' => true}
          end

          route 'one-after' do
            after do |_, response|
              response.body['list'] << 1
            end

            get do |request|
              {'list' => []}
            end
          end

          route 'two-after' do
            after do |request, response|
              response.body['list'] << 1
            end

            after do |request, response|
              response.body['list'] << 2
            end

            get do |request|
              {'list' => []}
            end

            route 'another-after' do
              after do |request, response|
                response.body['list'] << 3
              end

              get do |request|
                {'list' => []}
              end
            end
          end

          route 'stops-early' do
            before do |_, response|
              response.body = 'before1'
              response.finish
            end

            after do |_, response|
              response.body << '|after1'
            end

            route 'not-called' do
              before do |_, response|
                response.body << '|before2'
              end

              after do |_, response|
                response.body << '|after2'
              end

              get do |_, response|
                response.body << '|handler'
              end
            end
          end

          mount MountedAfterApp
        end
      end

      it 'calls the after block after the request handler' do
        get '/'
        expect(last_response.body).to eq('{"root":true}')
      end

      it 'calls the after blocks of all routes after the request handler' do
        get '/one-after'
        expect(last_response.body).to eq('{"list":[1]}')
      end

      it 'calls all after blocks of a route in order' do
        get '/two-after'
        expect(last_response.body).to eq('{"list":[2,1]}')
      end

      it 'calls all after blocks of a route after the request handler' do
        get '/two-after/another-after'
        expect(last_response.body).to eq('{"list":[3,2,1]}')
      end

      context 'when the path does not match any route' do
        it 'does not run any before blocks' do
          get '/does-not-exist'
          expect(last_response.status).to eq(404)
          expect(state).to be_empty
        end
      end

      context 'with a mounted app' do
        it 'runs the after blocks from both the mounting and the mounted app' do
          get '/in-mounted-app'
          expect(last_response.body).to eq('{"list":[2,1]}')
        end
      end

      context 'when the request is finished by a before block' do
        it 'runs only the after blocks from the same level and up', pending: true do
          get '/stops-early/not-called'
          expect(last_response.body).to eq('"before1|after1"')
        end
      end
    end

    context 'an app that has capturing routes' do
      let :app do
        App.new do
          route 'foo' do
            route :bar do
              get do
                'whatever'
              end

              route 'echo' do
                get do |request|
                  request.parameters[:bar]
                end
              end
            end

            route 'bar' do
              get do
                'bar'
              end
            end
          end
        end
      end

      it 'matches anything for the capture route' do
        get '/foo/something'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('whatever')
        get '/foo/something-else'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('whatever')
      end

      it 'picks static routes first' do
        get '/foo/bar'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('bar')
      end

      it 'captures the path component as a parameter using a symbol as key' do
        get '/foo/zzz/echo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('zzz')
        get '/foo/q/echo'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('q')
      end
    end

    context 'an app that mounts another app' do
      GoodbyeApp = App.create do
        route 'goodbye' do
          get do
            'goodbye'
          end
        end
      end

      HelloApp = App.create do
        route 'hello' do
          get do
            'hello'
          end

          route 'you' do
            route 'say' do
              mount GoodbyeApp
            end
          end
        end
      end

      let :app do
        App.new do
          route 'i' do
            route 'say' do
              mount HelloApp
              mount GoodbyeApp
            end
          end

          route 'oh' do
            mount HelloApp
          end
        end
      end

      it 'routes a request into the other app' do
        get '/i/say/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'can mount multiple apps' do
        get '/i/say/goodbye'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('goodbye')
      end

      it 'routes a request into apps that mount yet more apps' do
        get '/i/say/hello/you/say/goodbye'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('goodbye')
      end

      it 'can mount the same app multiple times' do
        get '/oh/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end
    end

    context 'an app that supports all HTTP methods' do
      let :app do
        App.new do
          get do |request|
            request.request_method
          end

          head do |request|
            request.request_method
          end

          options do |request|
            request.request_method
          end

          delete do |request|
            request.request_method
          end

          post do |request|
            request.request_method
          end

          put do |request|
            request.request_method
          end

          patch do |request|
            request.request_method
          end

          route 'anything' do
            any do |request|
              request.request_method
            end
          end
        end
      end

      it 'routes GET requests' do
        get '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('GET')
      end

      it 'routes HEAD requests, but does not respond with any body' do
        head '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to be_empty
      end

      it 'routes OPTIONS requests' do
        options '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('OPTIONS')
      end

      it 'routes DELETE requests' do
        delete '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('DELETE')
      end

      it 'routes POST requests' do
        post '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('POST')
      end

      it 'routes PUT requests' do
        put '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('PUT')
      end

      it 'routes PATCH requests' do
        patch '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('PATCH')
      end

      it 'routes all HTTP requests when there is an any handler' do
        get '/anything'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('GET')
        delete '/anything'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('DELETE')
        head '/anything'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to be_empty
        put '/anything'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('PUT')
      end
    end

    context 'an app with helper methods' do
      let :app do
        App.new do
          def top_level_helper
            'top_level_helper'
          end

          rescue_from StandardError do |_, _, response|
            response.body = top_level_helper
          end

          route 'one' do
            def first_level_helper
              'first_level_helper'
            end

            get do
              first_level_helper
            end

            route 'two' do
              def second_level_helper
                'second_level_helper'
              end

              before do |_, response|
                response.body = 'before:' << [top_level_helper, first_level_helper, second_level_helper].join(',')
              end

              after do |_, response|
                response.body += '|after:' << [top_level_helper, first_level_helper, second_level_helper].join(',')
              end

              get do |_, response|
                response.body + '|handler:' << [top_level_helper, first_level_helper, second_level_helper].join(',')
              end
            end
          end

          route 'boom' do
            get do
              raise 'Bork'
            end
          end
        end
      end

      it 'can use the helper methods defined on the same route as the handler' do
        get '/one'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('first_level_helper')
      end

      it 'can use the helper methods defined on all routes above a handler' do
        get '/one/two'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('handler:top_level_helper,first_level_helper,second_level_helper')
      end

      it 'can use the helper methods in before blocks' do
        get '/one/two'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('before:top_level_helper,first_level_helper,second_level_helper')
      end

      it 'can use the helper methods in after blocks' do
        get '/one/two'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('after:top_level_helper,first_level_helper,second_level_helper')
      end

      it 'can use the helper methods in rescue blocks' do
        get '/boom'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('top_level_helper')
      end
    end

    context 'an app that receives configuration when created' do
      let :app do
        App.new(fuzzinator: fuzzinator, blip_count: 3) do
          route 'blip' do
            get do |request, _, app|
              "blip\n" * app.attributes[:blip_count]
            end
          end

          route 'fuzz' do
            get do |request, _, app|
              app.attributes[:fuzzinator].fuzz(request.parameters['s'])
            end
          end
        end
      end

      let :fuzzinator do
        double(:fuzzinator)
      end

      before do
        allow(fuzzinator).to receive(:fuzz) { |s| s.split('').join('z') }
      end

      it 'can access the arguments given to .new through the attributes hash' do
        get '/blip'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("blip\nblip\nblip\n")
        get '/fuzz?s=badaboom'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('bzazdzazbzozozm')
      end
    end

    context 'an app that uses Rack middleware' do
      class Reverser
        def initialize(app)
          @app = app
        end

        def call(env)
          response = @app.call(env)
          body = response[2][0]
          body && body.reverse!
          response
        end
      end

      class Uppercaser
        def initialize(app)
          @app = app
        end

        def call(env)
          response = @app.call(env)
          body = response[2][0]
          body && body.upcase!
          response
        end
      end

      class Mutator
        def initialize(app, &block)
          @app = app
          @block = block
        end

        def call(env)
          @app.call(@block.call(env))
        end
      end

      MountedMiddlewareApp = App.create do
        use Rack::Runtime, 'MountedMiddlewareApp'

        route 'in-mounted-app' do
          use Mutator do |env|
            env['app.greeting'] = 'Marhaban'
            env
          end

          get do |request|
            request.env['app.greeting']
          end
        end
      end

      let :app do
        App.new do
          use Reverser

          get do
            'lorem ipsum'
          end

          route 'more' do
            use Uppercaser

            get do
              'dolor sit'
            end
          end

          route 'hello' do
            use Rack::Runtime, 'Regal'
            use Mutator do |env|
              env['app.greeting'] = 'Bonjour'
              env
            end

            get do |request|
              request.env['app.greeting'] + ', ' + request.parameters['name']
            end
          end

          mount MountedMiddlewareApp
        end
      end

      it 'calls the middleware when processing the request' do
        get '/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('muspi merol')
      end

      it 'calls the middleware of all routes' do
        get '/more'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('TIS ROLOD')
      end

      it 'passes arguments when instantiating the middleware' do
        get '/hello?name=Eve'
        expect(last_response.status).to eq(200)
        expect(last_response.headers).to have_key('X-Runtime-Regal')
      end

      it 'passes blocks when instantiating the middleware' do
        get '/hello?name=Eve'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('Bonjour, Eve'.reverse)
      end

      context 'with a mounted app' do
        it 'calls the middleware from both the mounting and the mounted app' do
          get '/in-mounted-app'
          expect(last_response.status).to eq(200)
          expect(last_response.body).to eq('nabahraM')
          expect(last_response.headers).to have_key('X-Runtime-MountedMiddlewareApp')
        end
      end
    end

    context 'an app which needs more control over the response body' do
      let :app do
        App.new do
          route 'no-overwrite' do
            get do |_, response|
              response.body = 'foobar'
              response.finish
            end
          end

          route 'raw-body' do
            get do |_, response|
              response.raw_body = 'a'..'z'
            end
          end

          route 'no-body' do
            before do |_, response|
              response.no_body
            end

            get do
              'I will not be used'
            end
          end
        end
      end

      it 'can finish the response so that the result of the handler will not be used as body' do
        get '/no-overwrite'
        expect(last_response.body).to eq('foobar')
      end

      it 'can set the raw body of the response' do
        get '/raw-body'
        expect(last_response.body).to eq('abcdefghijklmnopqrstuvwxyz')
      end

      it 'can disable the response body completely' do
        get '/no-body'
        expect(last_response.body).to be_empty
      end
    end

    context 'an app that responds with no-body response codes' do
      let :app do
        App.new do
          [111, 204, 205, 304].each do |status|
            route status.to_s do
              get do |_, response|
                response.status = status
                'this will not be returned'
              end
            end
          end

          route 'with-after' do
            get do |_, response|
              response.status = 204
              'this will not be returned'
            end

            after do |_, response|
              response.body = 'this will not be returned either'
            end
          end
        end
      end

      it 'ignore the response body' do
        [111, 204, 205, 304].each do |status|
          get "/#{status}"
          expect(last_response.status).to eq(status)
          expect(last_response.body).to be_empty
        end
      end

      it 'ignores response bodies set by after blocks' do
        get '/with-after'
        expect(last_response.status).to eq(204)
        expect(last_response.body).to be_empty
      end
    end

    context 'an app that raises exceptions' do
      class SomeNastyError < StandardError; end
      class AppError < StandardError; end
      class SpecificError < AppError; end

      MountedRescuingApp = App.create do
        rescue_from SpecificError do |_, _, response|
          response.body = 'handled SpecificError in the mounted app'
        end

        route 'raise-specific-error' do
          get do
            raise SpecificError, 'Blam!'
          end
        end

        route 'raise-app-error' do
          get do
            raise AppError, 'Kaboom!'
          end
        end

        route 'raise-and-and-handle-app-error' do
          rescue_from AppError do |_, _, response|
            response.body = 'handled AppError in the mounted app'
          end

          get do
            raise AppError, 'Kaboom!'
          end
        end
      end

      MountedNonRescuingApp = App.create do
        after do
          raise AppError, 'Kaboom!'
        end

        route 'raise-from-after' do
          get do
          end
        end
      end

      let :app do
        App.new do
          route 'unhandled' do
            get do
              raise 'Bork!'
            end
          end

          route 'handled' do
            rescue_from AppError do |error, request, response|
              response.body = error.message
            end

            after do |_, response|
              response.headers['WasAfterCalled'] = 'yes'
            end

            get do
              raise SpecificError, 'Boom!'
            end

            route 'handled' do
              get do
                raise AppError, 'Crash!'
              end
            end

            route 'unhandled' do
              get do
                raise SomeNastyError
              end
            end

            route 'from-before' do
              before do
                raise SpecificError, 'Bang!'
              end

              get do
              end
            end

            route 'from-after' do
              after do
                raise SpecificError, 'Kazam!'
              end

              after do |_, response|
                response.headers['NextAfterWasCalled'] = 'yes'
              end

              get do
              end
            end

            route 'handled-locally' do
              rescue_from SpecificError do |error, request, response|
              end

              get do
                raise SpecificError, 'Bam!'
              end
            end
          end

          route 'with-mounted-app' do
            rescue_from AppError do |_, _, response|
              response.body = 'handled AppError in the mounting app'
            end

            mount MountedRescuingApp
            mount MountedNonRescuingApp
          end
        end
      end

      context 'from handlers' do
        it 'does not catch them' do
          expect { get '/unhandled' }.to raise_error('Bork!')
        end

        it 'delegates them to matching error handlers' do
          get '/handled'
          expect(last_response.body).to eq('Boom!')
        end

        it 'calls after blocks when errors are handled' do
          get '/handled'
          expect(last_response.headers['WasAfterCalled']).to eq('yes')
        end

        it 'lets them bubble all the way up when there are no matching error handlers' do
          expect { get '/handled/unhandled' }.to raise_error(SomeNastyError)
        end
      end

      context 'from before blocks' do
        it 'delegates them to matching error handlers' do
          get '/handled/from-before'
          expect(last_response.body).to eq('Bang!')
        end

        it 'calls after blocks when errors are handled' do
          get '/handled/from-before'
          expect(last_response.headers['WasAfterCalled']).to eq('yes')
        end
      end

      context 'from after blocks' do
        it 'delegates them to matching error handlers' do
          get '/handled/from-after'
          expect(last_response.body).to eq('Kazam!')
        end

        it 'calls the rest of the after blocks when errors are handled' do
          get '/handled/from-after'
          expect(last_response.headers['NextAfterWasCalled']).to eq('yes')
          expect(last_response.headers['WasAfterCalled']).to eq('yes')
        end
      end

      context 'from mounted apps' do
        it 'delegates them to matching error handlers in the mounting app' do
          get '/with-mounted-app/raise-app-error'
          expect(last_response.body).to eq('handled AppError in the mounting app')
        end

        it 'delegates them to matching error handlers declared at the top of the mounted app' do
          get '/with-mounted-app/raise-specific-error'
          expect(last_response.body).to eq('handled SpecificError in the mounted app')
        end

        it 'delegates them to matching error handlers declared in routes of the mounted app' do
          get '/with-mounted-app/raise-and-and-handle-app-error'
          expect(last_response.body).to eq('handled AppError in the mounted app')
        end

        context 'in after blocks' do
          it 'delegates them to a matching error handler' do
            get '/with-mounted-app/raise-from-after'
            expect(last_response.body).to eq('handled AppError in the mounting app')
          end
        end
      end
    end
  end
end
