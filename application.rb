['rubygems', "haml", "sass", "rack-flash"].each do |lib|
	require lib
end
gem "opentox-ruby-api-wrapper", "= 1.5.7"
require 'opentox-ruby-api-wrapper'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'
require 'ftools'
require File.join(File.dirname(__FILE__),'model.rb')
require File.join(File.dirname(__FILE__),'helper.rb')
require File.join(File.dirname(__FILE__),'parser.rb')

LOGGER.progname = File.expand_path __FILE__

use Rack::Flash
set :sessions, true

get '/?' do
	redirect url_for('/create')
end

get '/models/?' do
	@models = ToxCreateModel.all(:order => [ :created_at.desc ])
	@models.each { |model| model.process }
	haml :models
end

delete '/model/:id/?' do
	model = ToxCreateModel.get(params[:id])
	begin
		RestClient.delete model.uri if model.uri
		RestClient.delete model.task_uri if model.task_uri
	rescue
	  flash[:notice] = "#{model.name} model delete error."
	end
	model.destroy!
	flash[:notice] = "#{model.name} model deleted."
	redirect url_for('/models')
end

get '/model/:id/status/?' do
  response['Content-Type'] = 'text/plain'
	model = ToxCreateModel.get(params[:id])
	begin
		haml :model_status, :locals=>{:model=>model}, :layout => false
	rescue
    return "unavailable"
	end
end

get '/model/:id/:view/?' do
  response['Content-Type'] = 'text/plain'
	model = ToxCreateModel.get(params[:id])
  model.process

  #begin
    case params[:view]
      when "model"
		    haml :model, :locals=>{:model=>model}, :layout => false
		  when "classification_validation"
		    haml :classification_validation, :locals=>{:model=>model}, :layout => false
		  when "regression_validation"
		    haml :regression_validation, :locals=>{:model=>model}, :layout => false
		  else
		    return "render error"
		end
	#rescue
  #  return "unable to render model"
	#end
end

get '/predict/?' do 
	@models = ToxCreateModel.all(:order => [ :created_at.desc ])
	@models = @models.collect{|m| m if m.status == 'Completed'}.compact
	haml :predict
end

get '/create' do
	haml :create
end

get '/help' do
	haml :help
end

get "/confidence" do
	haml :confidence
end

post '/upload' do # create a new model

	if params[:endpoint] == ''
		flash[:notice] = "Please enter an endpoint name."
		redirect url_for('/create')
	end
	unless params[:endpoint] and params[:file] and params[:file][:tempfile]
		flash[:notice] = "Please enter an endpoint name and upload a Excel or CSV file."
		redirect url_for('/create')
	end

	@model = ToxCreateModel.new
	@model.name = params[:endpoint]
	feature_uri = url_for("/feature#"+URI.encode(params[:endpoint]), :full)
	parser = Parser.new params[:file], feature_uri

	unless parser.format_errors.empty?
		flash[:notice] = "Incorrect file format. Please follow the instructions for #{link_to "Excel", "/excel_format"} or #{link_to "CSV", "/csv_format"} formats."
	end

	if parser.dataset.compounds.empty?
		flash[:notice] = "Dataset #{params[:file][:filename]} is empty."
		redirect url_for('/create')
	end

	begin
		@model.task_uri = OpenTox::Algorithm::Lazar.create_model(:dataset_uri => parser.dataset_uri, :prediction_feature => feature_uri)
	rescue
		flash[:notice] = "Model creation failed. Please check if the input file is in a valid #{link_to "Excel", "/excel_format"} or #{link_to "CSV", "/csv_format"} format."
		redirect url_for('/create')
	end

	validation_task_uri = OpenTox::Validation.crossvalidation(
		:algorithm_uri => OpenTox::Algorithm::Lazar.uri,
		:dataset_uri => parser.dataset_uri,
		:prediction_feature => feature_uri,
		:algorithm_params => "feature_generation_uri=#{OpenTox::Algorithm::Fminer.uri}"
	).uri
	LOGGER.debug "Validation task: " + validation_task_uri
	@model.validation_task_uri = validation_task_uri

=begin
	if parser.nr_compounds < 10
		flash[:notice] = "Too few compounds to create a prediction model. Did you provide compounds in SMILES format and classification activities as described in the #{link_to "instructions", "/excel_format"}? As a rule of thumb you will need at least 100 training compounds for nongeneric datasets. A lower number could be sufficient for congeneric datasets."
		redirect url_for('/create')
	end
=end

	@model.nr_compounds = parser.nr_compounds
	@model.warnings = ''

	@model.warnings += "<p>Incorrect Smiles structures (ignored):</p>" + parser.smiles_errors.join("<br/>") unless parser.smiles_errors.empty?
	@model.warnings += "<p>Irregular activities (ignored):</p>" + parser.activity_errors.join("<br/>") unless parser.activity_errors.empty?
	duplicate_warnings = ''
	parser.duplicates.each {|inchi,lines| duplicate_warnings += "<p>#{lines.join('<br/>')}</p>" if lines.size > 1 }
	@model.warnings += "<p>Duplicated structures (all structures/activities used for model building, please  make sure, that the results were obtained from <em>independent</em> experiments):</p>" + duplicate_warnings unless duplicate_warnings.empty?
	@model.save

	flash[:notice] = "Model creation started. Please be patient - model building may take up to several hours depending on the number and size of the input molecules."
	redirect url_for('/models')

	# TODO: check for empty model
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
	params[:selection].keys.each do |id|
		model = ToxCreateModel.get(id.to_i)
		prediction = nil
		confidence = nil
		title = nil
		db_activities = []
		LOGGER.debug "curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}"
		prediction = YAML.load(`curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}`)
		# TODO check if prediction failed - returns string
		source = prediction.creator
		if prediction.data[@compound.uri]
			if source.to_s.match(/model/) # real prediction
				prediction = prediction.data[@compound.uri].first.values.first
				LOGGER.debug prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")]
				LOGGER.debug prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]
				if !prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")].nil?
					@predictions << {:title => model.name, :prediction => prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")], :confidence => prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]}
				elsif !prediction[File.join(@@config[:services]["opentox-model"],"lazar#regression")].nil?
					@predictions << {:title => model.name, :prediction => prediction[File.join(@@config[:services]["opentox-model"],"lazar#regression")], :confidence => prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]}
				end
			else # database value
				prediction = prediction.data[@compound.uri].first.values
				@predictions << {:title => model.name, :measured_activities => prediction}
			end
		else
			@predictions << {:title => model.name, :prediction => "not available (no similar compounds in the training dataset)"}
		end
	end
	LOGGER.debug @predictions.inspect

	haml :prediction
end

delete '/?' do
  ToxCreateModel.auto_migrate!
	response['Content-Type'] = 'text/plain'
	"All Models deleted."
end

# SASS stylesheet
get '/stylesheets/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end

