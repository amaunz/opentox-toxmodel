['rubygems', 'opentox-ruby-api-wrapper', "haml", "sass"].each do |lib|
	require lib
end

get '/?' do 
	@models = OpenTox::Model::Lazar.find_all
	haml :index
end

get '/create' do
	haml :create
end

get '/:id' do # input form for predictions
	@model = OpenTox::Model::Lazar.find(File.join(@@config[:services]["opentox-model"],params[:id]))
	haml :show
end

get '/validation/:id' do 
	@model = OpenTox::Model::LazarClassification.find(params[:id])
	haml :validation
end

get '/delete/:id' do
	@model = OpenTox::Model::LazarClassification.find(params[:id])
	haml :delete
end

get '/tmp/:id' do
	haml :tmp
end

post '/' do # create a new model
	data = params[:file][:tempfile].read
	training_data = OpenTox::Dataset.create(data)
	@features = training_data.features
	if @features.size == 1
		feature_data = OpenTox::Algorithm::Fminer.create(:dataset_uri => training_data.uri, :feature_uri => @features[0].to_s)
		@model = OpenTox::Model::Lazar.create(:activity_dataset_uri => training_data.uri, :feature_dataset_uri => feature_data.to_s)
		haml :index
	else
		halt 400, "The dataset contains more than one target variable:\n#{@features.collect{|f| f.to_s}.join("\n")}\nPlease clean up and submit it again."
		redirect "/features"
	end
end

post '/:id' do # post chemical name to model

	storage = Redland::MemoryStore.new
	parser = Redland::Parser.new
	serializer = Redland::Serializer.new
	prediction = Redland::Model.new storage

	#begin
		@compound = OpenTox::Compound.new(:name => params[:name])
		#@compound = OpenTox::Compound.new(:smiles => params[:name])
	#rescue
	#	@message = "Can not retrieve Smiles from #{params[:name]}. Please try again."
	#	redirect "/#{params[:id]}"
	#end
	@lazar = OpenTox::Model::Lazar.find(File.join(@@config[:services]["opentox-model"],params[:id]))
	parser.parse_string_into_model(prediction,@lazar.predict(@compound).to_s,'/')
	@classification = prediction.object(Redland::Uri.new(@compound.uri),Redland::Uri.new(File.join(@@config[:services]["opentox-model"],params[:id],"classification")))
	@confidence = prediction.object(Redland::Uri.new(@compound.uri),Redland::Uri.new(File.join(@@config[:services]["opentox-model"],params[:id],"confidence")))
	@measured_activity = prediction.object(Redland::Uri.new(@compound.uri),Redland::Uri.new(@lazar.endpoint))
	haml :prediction
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
