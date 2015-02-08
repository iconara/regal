# encoding: utf-8

require 'rspec/core/rake_task'
require 'bundler/gem_helper'

task :default => :spec

RSpec::Core::RakeTask.new(:spec) do |r|
  r.rspec_opts = '--tty'
end

namespace :bundler do
  Bundler::GemHelper.install_tasks
end

desc 'Tag & release the gem'
task :release => [:spec, 'bundler:release']
