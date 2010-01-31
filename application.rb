['rubygems', 'opentox-ruby-api-wrapper', "haml", "sass"].each do |lib|
	require lib
end
require 'rack-flash'
#require 'benchmark'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'

use Rack::Flash
set :sessions, true

get '/?' do
	redirect url_for('/create')
end

get '/predict/?' do 
	@models = OpenTox::Model::Lazar.find_all
	haml :predict
end

get '/create' do
	haml :create
end

get '/about' do
	haml :about
end

get '/csv_format' do
	haml :csv_format
end

get '/tasks' do
	@tasks = OpenTox::Task.all
	haml :tasks
end

get '/task' do
	@task = OpenTox::Task.find(session[:task_uri])
	haml :task
end

post '/upload' do # create a new model
	dataset = OpenTox::Dataset.new
	title = params[:endpoint].sub(/\s+/,'_')
	dataset.title = title
	feature_uri = url_for("/feature#"+title, :full)
	feature = dataset.find_or_create_feature(feature_uri)
	params[:file][:tempfile].each_line do |line|
		items = line.chomp.split(/\s*,\s*/)
		smiles = items[0]
		compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
		compound = dataset.find_or_create_compound(compound_uri)
		case items[1].to_s
		when '1'
			dataset.add(compound,feature,true)
		when '0'
			dataset.add(compound,feature,false)
		else
			flash[:notice] = "Irregular activity '#{items[1]}' for SMILES #{smiles}. Please use 1 for active and 0 for inactive compounds"
		end
	end
	dataset_uri = dataset.save
	task_uri = OpenTox::Algorithm::Lazar.create_model(:dataset_uri => dataset_uri, :feature_uri => feature_uri)
	flash[:notice] = "Model creation started - this may take some time. You can view and manage the status of current tasks at the #{link_to("Tasks page", "/tasks")}. #{link_to("Reload this page", "/predict")} to use the new model."
	session[:task_uri] = task_uri
	redirect url_for('/predict')
end

post '/predict/?' do # post chemical name to model
	@identifier = params[:identifier]
	begin
		@compound = OpenTox::Compound.new(:name => params[:identifier])
	rescue
		flash[:notice] = "Could not find a structure for #{@identifier}. Please try again."
		redirect '/predict'
	end
	@predictions = []
	params[:selection].keys.each do |uri|
		prediction = nil
		confidence = nil
		title = nil
		prediction = RestClient.post uri, :compound_uri => @compound.uri, :accept => "application/x-yaml"
		model = Redland::Model.new Redland::MemoryStore.new
		parser = Redland::Parser.new
		parser.parse_string_into_model(model,prediction,'/')
		f = model.subject(RDF['type'],OT['Feature']) # this can be dangerous if OWL is not properly sorted
		title = model.object(f,DC['title']).to_s
		model.subjects(RDF['type'], OT['FeatureValue']).each do |v|
			feature = model.object(v,OT['feature'])
			feature_name = model.object(feature,DC['title']).to_s
			prediction = model.object(v,OT['value']).to_s if feature_name.match(/classification/)
			confidence = model.object(v,OT['value']).to_s if feature_name.match(/confidence/)
		end
		case prediction.to_s
		when "true"
			prediction = "active"
		when "false"
			prediction = "inactive"
		else
			prediction = "not available"
		end
		@predictions << {:title => title, :prediction => prediction, :confidence => confidence}
	end

	haml :prediction
	#@predictions.to_yaml 
end

post '/task/cancel' do
	task = OpenTox::Task.find(params[:task_uri])
	task.cancel
	redirect url_for('/tasks')
end

delete '/:id' do
	#begin
		OpenTox::Model::LazarClassification.delete(params[:id])
		haml :index
	#rescue
		#"Deletion of model with ID #{params[:id]} failed. Please check your username and password."
	#end
end

# SASS stylesheet
get '/stylesheets/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end
