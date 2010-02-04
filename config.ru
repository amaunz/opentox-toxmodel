require 'rubygems'
require 'sinatra'
require 'application.rb'
require 'rack'
require 'rack/contrib'

FileUtils.mkdir_p 'log' unless File.exists?('log')
FileUtils.mkdir_p 'tmp' unless File.exists?('tmp')
log = File.new("log/#{ENV["RACK_ENV"]}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

if ENV['RACK_ENV'] == 'production'
	use Rack::MailExceptions do |mail|
		mail.to 'helma@in-silico.ch'
		mail.subject '[ERROR] %s'
	end 
elsif ENV['RACK_ENV'] == 'development'
  use Rack::Reloader 
  use Rack::ShowExceptions
end

require 'rack/flash'
use Rack::Session::Cookie
use Rack::Flash

run Sinatra::Application
