['rubygems', 'sinatra', 'rest_client', 'sinatra/url_for', 'haml', 'sass', 'crack/xml'].each do |lib|
	require lib
end

LAZAR_URI = 'http://webservices.in-silico.ch/lazar/models/'
#LAZAR_URI = 'http://localhost:3000/models/'
COMPOUNDS_URI = 'http://webservices.in-silico.ch/compounds/'
#COMPOUNDS_URI = 'http://localhost:9393'

get '/?' do 
	@models = []
	(RestClient.get LAZAR_URI).chomp.each_line do |uri|
		puts uri
		xml = RestClient.get uri
		@models << Crack::XML.parse(xml)['model']
		name = Crack::XML.parse(xml)['model']['name']
	end
	haml :index
end

get '/create' do
	haml :create
end

get '/:id' do # input form for predictions
	begin
		xml = RestClient.get "#{LAZAR_URI}#{params[:id]}"
		@model = Crack::XML.parse(xml)['model']
	 	YAML.load(RestClient.get "#{@model['validation']['details_uri']}") # check if model creation is finished
		haml :show
 	rescue
		redirect "/tmp/#{params[:id]}"
 	end
end

get '/validation/:id' do 
	begin
	 xml = RestClient.get "#{LAZAR_URI}#{params[:id]}"
	 @model = Crack::XML.parse(xml)['model']
	 @summary = YAML.load(RestClient.get "#{@model['validation']['summary_uri']}")
	 haml :validation
 	rescue
		redirect "/tmp/#{params[:id]}"
 	end
end

get '/delete/:id' do
	xml = RestClient.get "#{LAZAR_URI}#{params[:id]}"
	@model = Crack::XML.parse(xml)['model']
	haml :delete
end

get '/tmp/:id' do
	haml :tmp
end

post '/' do # create a new model
	# create dataset
	# validate lazar on the dataset
	sanitized_name = params[:name].gsub(/\s+/,'_').gsub(/\W/, '')
	uri = `curl -F name=#{sanitized_name} -F file=@#{params[:file][:tempfile].path} -F username=#{params[:username]} -F password=#{params[:password]} #{LAZAR_URI}`
	id = uri.chomp.gsub(/^.*\/(\d+)$/,'\1')
	# TODO check for not authorized
	redirect "/#{id}"
end

post '/:id' do # post chemical name to model
	begin
		smiles = RestClient.get "#{COMPOUNDS_URI}#{URI.encode(params[:name])}.smiles"
	rescue
		@message = "Can not retrieve Smiles from #{params[:name]}. Please try again."
		redirect "/#{params[:id]}"
	end
	begin
		xml = RestClient.get "#{LAZAR_URI}#{params[:id]}?smiles=#{URI.encode(smiles)}"
		@lazar = Crack::XML.parse(xml)['lazar']
		haml :prediction
	rescue
		"Prediction for #{params[:name]} (SMILES #{smiles}) failed." 
	end
end

delete '/:id' do
	begin
		`curl  -X DELETE -d username=#{params[:username]} -d password=#{params[:password]} #{LAZAR_URI}#{params[:id]}`
		redirect '/'
	rescue
		"Deletion of model with ID #{params[:id]} failed. Please check your username and password."
	end
end

# SASS stylesheet
get '/stylesheets/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end
