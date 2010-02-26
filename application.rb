['rubygems', "haml", "sass", "rack-flash"].each do |lib|
	require lib
end
gem 'opentox-ruby-api-wrapper', '= 1.2.7'
require 'opentox-ruby-api-wrapper'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'
LOGGER.progname = File.expand_path __FILE__

use Rack::Flash
set :sessions, true

class ToxCreateModel
	include DataMapper::Resource
	property :id, Serial
	property :name, String, :length => 255
	property :uri, String, :length => 255
	property :task_uri, String, :length => 255
	property :messages, Text, :length => 2**32-1 
	property :created_at, DateTime

	def status
		RestClient.get File.join(self.task_uri, 'status')
	end
end

DataMapper.auto_upgrade!

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

get '/models/?' do
	@models = ToxCreateModel.all(:order => [ :created_at.desc ])
	@models.each do |model|
		if !model.uri and model.status == "completed"
			model.uri = RestClient.get(File.join(model.task_uri, 'resource')).to_s
			model.save
		end
	end
	@refresh = true #if @models.collect{|m| m.status}.grep(/started|created/)
	haml :models
end

get '/model/:id/delete/?' do
	model = ToxCreateModel.get(params[:id])
	begin
		RestClient.delete model.uri if model.uri
		RestClient.delete model.task_uri if model.task_uri
	rescue
	end
	model.destroy!
	flash[:notice] = "#{model.name} model deleted."
	redirect url_for('/models')
end

get '/predict/?' do 
	@models = ToxCreateModel.all(:order => [ :created_at.desc ])
	@models = @models.collect{|m| m if m.status == 'completed'}.compact
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
	#LOGGER.debug "ENDPOINT '#{params[:endpoint]}'"
	if params[:endpoint] == ''
		flash[:notice] = "Please enter an endpoint name."
		redirect url_for('/create')
	end
	unless params[:endpoint] and params[:file] and params[:file][:tempfile]
		flash[:notice] = "Please enter an endpoint name and upload a CSV file."
		redirect url_for('/create')
	end
	@model = ToxCreateModel.new
	@model.name = params[:endpoint]
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
		unless line.chomp.match(/^.+[,;].*$/) # check CSV format - not all browsers provide correct content-type
			flash[:notice] = "Please upload a CSV file created according to these #{link_to "instructions", "csv_format"}."
			redirect url_for('/create')
		end
		items = line.chomp.split(/\s*[,;]\s*/)
		smiles = items[0]
		c = OpenTox::Compound.new(:smiles => smiles)
		if c.inchi != ""
			duplicates[c.inchi] = [] unless duplicates[c.inchi]
			duplicates[c.inchi] << "Line #{line_nr}: " + line.chomp
			compound_uri = c.uri
			compound = dataset.find_or_create_compound(compound_uri)
			#activity_errors << "Empty activity at line #{line_nr}: " + line.chomp unless items.size == 2 # empty activity value
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
	@model.task_uri = task_uri

	@model.messages = "#{nr_compounds} compounds"

	if smiles_errors.size > 0
		@model.messages += "<p>Incorrect Smiles structures (ignored):</p>"
		@model.messages += smiles_errors.join("<br/>")
	end
	if activity_errors.size > 0
		@model.messages += "<p>Irregular activities (ignored - please use 1 for active and 0 for inactive compounds):</p>"
		@model.messages += activity_errors.join("<br/>")
	end
	duplicate_warnings = ''
	duplicates.each {|inchi,lines| duplicate_warnings += "<p>#{lines.join('<br/>')}</p>" if lines.size > 1 }
	#LOGGER.debug duplicate_warnings
	unless duplicate_warnings == ''
		@model.messages += "<p>Duplicated structures (all structures/activities used for model building, please  make sure, that the results were obtained from <em>independent</em> experiments):</p>" 
		@model.messages +=  duplicate_warnings
	end
	@model.save
	flash[:notice] = "Model creation started. Please be patient - model building may take up to several hours depending on the number and size of the input molecules."
	redirect url_for('/models')

end

post '/predict/?' do # post chemical name to model
	@identifier = params[:identifier]
	unless params[:selection] and params[:identifier] != ''
		flash[:notice] = "Please enter a compound identifier and select an endpoint from the list."
		redirect url_for('/predict')
	end
	begin
		@compound = OpenTox::Compound.new(:name => params[:identifier])
	rescue
		flash[:notice] = "Could not find a structure for '#{@identifier}'. Please try again."
		redirect url_for('/predict')
	end
	@predictions = []
	#LOGGER.debug params[:selection].to_yaml
	params[:selection].keys.each do |id|
		model = ToxCreateModel.get(id.to_i)
		#LOGGER.debug model.to_yaml
		prediction = nil
		confidence = nil
		title = nil
		db_activities = []
		#prediction = RestClient.post model.uri, :compound_uri => @compound.uri#, :accept => "application/x-yaml"
		resource = RestClient::Resource.new(model.uri, :user => @@users[:users].keys[0], :password => @@users[:users].values[0])		
		prediction = resource.post :compound_uri => @compound.uri#, :accept => "application/x-yaml"
		#LOGGER.debug "Prediction OWL-DL: "
		#LOGGER.debug prediction
		redland_model = Redland::Model.new Redland::MemoryStore.new
		parser = Redland::Parser.new
		parser.parse_string_into_model(redland_model,prediction,'/')
		title = model.name
		redland_model.subjects(RDF['type'], OT['FeatureValue']).each do |v|
			feature = redland_model.object(v,OT['feature'])
			feature_name = redland_model.object(feature,DC['title']).to_s
			#LOGGER.debug "DEBUG: #{feature_name}"
			prediction = redland_model.object(v,OT['value']).to_s if feature_name.match(/classification/)
			confidence = redland_model.object(v,OT['value']).to_s if feature_name.match(/confidence/)
			db_activities << redland_model.object(v,OT['value']).to_s if feature_name.match(/#{URI.encode title}/)
		end
		@predictions << {:title => title, :prediction => prediction, :confidence => confidence, :measured_activities => db_activities}
	end

	LOGGER.debug @predictions.to_yaml
	haml :prediction
end

# SASS stylesheet
get '/stylesheets/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end
