require 'rubygems'
require 'opentox-ruby-api-wrapper'
require 'tasks/config'
set :app_file, __FILE__ # to get the view path right
run Sinatra::Application
