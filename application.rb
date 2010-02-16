['rubygems', "haml", "sass"].each do |lib|
	require lib
end
require 'rack-flash'
gem 'opentox-ruby-api-wrapper', '= 1.2.7'
require 'opentox-ruby-api-wrapper'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'

use Rack::Flash
set :sessions, true

#class ToxPredictModel
#	include DataMapper::Resource
#	property :id, Serial
#	property :name, String
#	property :uri, String, :length => 255
#	property :task_uri, String, :length => 255
#	property :status, String, :length => 255
#	property :messages, Text, :length => 2**32-1 
#	property :created_at, DateTime
#end

#DataMapper.auto_upgrade!

helpers do
	def activity(a)
		case a.to_s
		when "true"
			act = "active"
		when "false"
			act = "inactive"
		else
			act = "not available"
		end
		act
	end
end

get '/?' do
	redirect url_for('/create')
end

get '/model/:id/?' do
	#@model = ToxPredictModel.get(params[:id])
	@model = YAML.load(RestClient.get params[:uri], :accept => "application/x-yaml")
	haml :model
end

get '/predict/?' do 
	#@models = ToxPredictModel.all
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
	unless params[:endpoint] and params[:file] and params[:file][:tempfile]
		flash[:notice] = "Please enter an endpoint name and upload a CSV file."
		redirect url_for('/create')
	end
	unless params[:file][:type] == "text/csv"
		flash[:notice] = "Please upload a CSV file - at present we cannot handle other file types."
		redirect url_for('/create')
	end
	#@model = ToxPredictModel.new
	#@model.name = params[:endpoint]
	#@model.status = "started"
	#@model.save
	title = URI.encode params[:endpoint]#.gsub(/\s+/,'_')
	dataset = OpenTox::Dataset.new
	dataset.title = title
	feature_uri = url_for("/feature#"+title, :full)
	feature = dataset.find_or_create_feature(feature_uri)
	smiles_errors = []
	activity_errors = []
	duplicates = {}
	nr_compounds = 0
	line_nr = 1
	params[:file][:tempfile].each_line do |line|
		items = line.chomp.split(/\s*,\s*/)
		smiles = items[0]
		c = OpenTox::Compound.new(:smiles => smiles)
		if c.inchi != ""
			duplicates[c.inchi] = [] unless duplicates[c.inchi]
			duplicates[c.inchi] << "Line #{line_nr}: " + line.chomp
			compound_uri = c.uri
			compound = dataset.find_or_create_compound(compound_uri)
			case items[1].to_s
			when '1'
				dataset.add(compound,feature,true)
				nr_compounds += 1
			when '0'
				dataset.add(compound,feature,false)
				nr_compounds += 1
			else
				activity_errors << "Line #{line_nr}: " + line.chomp
			end
		else
			smiles_errors << "Line #{line_nr}: " + line.chomp
		end
		line_nr += 1
	end
	dataset_uri = dataset.save 
	task_uri = OpenTox::Algorithm::Lazar.create_model(:dataset_uri => dataset_uri, :feature_uri => feature_uri)

	@notice = "Model creation for <b>#{params[:endpoint]}</b> (#{nr_compounds} compounds) started - this may take some time (up to several hours for large datasets). As soon as the has been finished it will appear in the list below, if you #{link_to("reload this page", "/predict")}."

	if smiles_errors.size > 0
		@notice += "<p>The following Smiles structures were not readable and have been ignored:</p>"
		@notice += smiles_errors.join("<br/>")
	end
	if activity_errors.size > 0
		@notice += "<p>The following structures had irregular activities and have been ignored (please use 1 for active and 0 for inactive compounds):</p>"
		@notice += activity_errors.join("<br/>")
	end
	duplicate_warnings = ''
	duplicates.each {|inchi,lines| duplicate_warnings += "<p>#{lines.join('<br/>')}</p>" if lines.size > 1 }
	LOGGER.debug duplicate_warnings
	unless duplicate_warnings == ''
		@notice += "<p>The following structures were duplicated in the dataset (this is not a problem for the algorithm, but you should make sure, that the results were obtained from <em>independent</em> experiments):</p>" 
		@notice +=  duplicate_warnings
	end
	session[:task_uri] = task_uri
	#redirect url_for('/predict')
	@models = OpenTox::Model::Lazar.find_all
	haml :predict

end

post '/predict/?' do # post chemical name to model
	@identifier = params[:identifier]
	begin
		@compound = OpenTox::Compound.new(:name => params[:identifier])
	rescue
		flash[:notice] = "Could not find a structure for '#{@identifier}'. Please try again."
		redirect url_for('/predict')
	end
	unless params[:selection]
		flash[:notice] = "Please select an endpoint from the list!"
		redirect url_for('/predict')
	end
	@predictions = []
	params[:selection].keys.each do |uri|
		prediction = nil
		confidence = nil
		title = nil
		db_activities = []
		prediction = RestClient.post uri, :compound_uri => @compound.uri#, :accept => "application/x-yaml"
		model = Redland::Model.new Redland::MemoryStore.new
		parser = Redland::Parser.new
		parser.parse_string_into_model(model,prediction,'/')
		yaml = RestClient.get uri, :accept => 'application/x-yaml'
		yaml = YAML.load yaml
		title = URI.decode yaml[:endpoint].split(/#/).last
		#f = model.subject(RDF['type'],OT['Feature']) # this can be dangerous if OWL is not properly sorted
		#title = RestClient.get(File.join(uri,"name")).to_s
		#title = model.object(f,DC['title']).to_s
		model.subjects(RDF['type'], OT['FeatureValue']).each do |v|
			feature = model.object(v,OT['feature'])
			feature_name = model.object(feature,DC['title']).to_s
			prediction = model.object(v,OT['value']).to_s if feature_name.match(/classification/)
			confidence = model.object(v,OT['value']).to_s if feature_name.match(/confidence/)
			db_activities << model.object(v,OT['value']).to_s if feature_name.match(/#{title}/)
		end
		@predictions << {:title => title, :prediction => prediction, :confidence => confidence, :measured_activities => db_activities}
	end

		LOGGER.debug @predictions.to_yaml
	haml :prediction
	#@predictions.to_yaml 
end

post '/task/cancel' do
	puts params[:task_uri]
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
