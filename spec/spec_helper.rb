require 'rack/test'
require 'simplecov'

SimpleCov.start do
  add_group 'Implementation', 'lib'
  add_group 'Unit tests', 'spec/regal'
end

require 'regal'
