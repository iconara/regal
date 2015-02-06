require 'spec_helper'

module Regal
  describe App do
    include Rack::Test::Methods

    context 'with a basic app' do
      let :app do
        HelloWorldApp.new
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
    end

    context 'with an app that mounts another app' do
      let :app do
        MountingApp.new
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

  HelloWorldApp = App.create do
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

  MountingApp = App.create do
    route 'i' do
      route 'say' do
        mount HelloWorldApp
      end
    end

    route 'oh' do
      mount HelloWorldApp
    end
  end
end
