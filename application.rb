['rubygems', 'opentox-ruby-api-wrapper', "haml", "sass"].each do |lib|
	require lib
end
require 'rack-flash'
require 'benchmark'
require 'ambit'

use Rack::Flash
set :sessions, true

get '/' do
	redirect 'create'
end

get '/predict/?' do 
	@models = OpenTox::Model::Lazar.find_all#.each { |uri| @models << OpenTox::Model::Generic.new(uri) }
	haml :predict
end

get '/create' do
	@datasets = Ambit.datasets
	haml :create
end

get '/about' do
	haml :about
end

get '/csv_format' do
	haml :csv_format
end

post '/select' do # create a new model
	@dataset_uri = params[:dataset_uri]
	@features = Ambit.features params[:dataset_uri]
	if @features.size == 1
		OpenTox::Algorithm::Lazar.create_model(:dataset_uri => training_data.uri, :feature_uri => @features.first)
		flash[:notice] = "Model creation started. If you reload this page the new model will appear in the selection list as soon as it is finished."
		haml :predict
	else
		haml :features
	end
end

post '/create' do
	#OpenTox::Algorithm::Lazar.create_model(:dataset_uri => params[:dataset_uri], :feature_uri => params[:feature_uri])
	#flash[:notice] = "Model creation started. If you reload this page the new model will appear in the selection list as soon as it is finished."
=begin
	flash[:notice] = "curl -X POST "
	params.each do |k,v|
		flash[:notice] += "-d \"" + k + "=" + v + "\" "
	end
	flash[:notice] += File.join @@config[:services]['opentox-algorithm'],"fminer"
=end
	flash[:notice] = "curl \"#{params[:dataset_uri]}?feature_uris\\[\\]=#{CGI.escape(params[:feature_uri])}\""
	dataset_uri = "#{params[:dataset_uri]}?feature_uris\\[\\]=#{CGI.escape(params[:feature_uri])}"
	OpenTox::Algorithm::Lazar.create_model(:dataset_uri => dataset_uri, :feature_uri => params[:feature_uri])
	flash[:notice] = "Model creation started. If you reload this page the new model will appear in the selection list as soon as it is finished."
	redirect "/tasks"
	#haml :predict
end

get '/tasks' do
	@tasks = OpenTox::Task.all
	haml :tasks
end

post '/upload' do # create a new model
	data = params[:file][:tempfile].read
	training_data = OpenTox::Dataset.create(data)
	@features = training_data.features
	if @features.size == 1
		OpenTox::Algorithm::Lazar.create_model(:dataset_uri => training_data.uri, :feature_uri => @features.first)
		flash[:notice] = "Model creation started. If you reload this page the new model will appear in the selection list as soon as it is finished."
		redirect '/predict'
		haml :index
	else
		halt 400, "The dataset contains more than one target variable:\n#{@features.collect{|f| f.to_s}.join("\n")}\nPlease clean up and submit again."
		redirect "/features"
	end
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
