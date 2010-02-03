require 'rubygems'
require 'opentox-ruby-api-wrapper'
require 'tasks/config'
require 'rack/flash'
use Rack::Session::Cookie
use Rack::Flash

set :app_file, __FILE__ # to get the view path right
run Sinatra::Application
