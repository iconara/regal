require 'spec_helper'

module Regal
  describe App do
    include Rack::Test::Methods

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
end
