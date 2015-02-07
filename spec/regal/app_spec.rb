require 'spec_helper'

module Regal
  describe App do
    include Rack::Test::Methods

    context 'with a basic app' do
      let :app do
        a = App.create do
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
        a.new
      end

      it 'routes a request' do
        get '/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'routes a request with more than one path component' do
        get '/hello/world'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello world')
      end

      it 'responds with 404 when the route does not exist' do
        get '/hello/fnord'
        expect(last_response.status).to eq(404)
      end

      it 'responds with 405 when the route exists but there is no handler for the HTTP method' do
        delete '/hello/world'
        expect(last_response.status).to eq(405)
      end
    end

    context 'with an app that has wildcard routes' do
      let :app do
        a = App.create do
          route 'foo' do
            route :bar do
              get do
                'whatever'
              end
            end

            route 'bar' do
              get do
                'bar'
              end
            end
          end
        end
        a.new
      end

      it 'routes anything to wildcard routes' do
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
    end

    context 'with an app that mounts another app' do
      HelloApp = App.create do
        route 'hello' do
          get do
            'hello'
          end
        end
      end

      let :app do
        a = App.create do
          route 'i' do
            route 'say' do
              mount HelloApp
            end
          end

          route 'oh' do
            mount HelloApp
          end
        end
        a.new
      end

      it 'routes a request' do
        get '/i/say/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end

      it 'routes a request through all mounts' do
        get '/oh/hello'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('hello')
      end
    end
  end
end
