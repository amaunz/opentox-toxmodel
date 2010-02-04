require 'rubygems'
require 'opentox-ruby-api-wrapper'
require 'config/config_ru'
set :app_file, __FILE__ # to get the view path right
run Sinatra::Application
