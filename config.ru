require 'rubygems'
require 'opentox-ruby-api-wrapper'
require 'config/config_ru'
require 'rack/flash'
use Rack::Session::Cookie
use Rack::Flash
set :app_file, __FILE__ # to get the view path right

run Sinatra::Application
