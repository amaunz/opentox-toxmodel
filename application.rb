['rubygems', "haml", "sass", "rack-flash"].each do |lib|
	require lib
end
gem "opentox-ruby-api-wrapper", "= 1.6.0"
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

# SASS stylesheet
get '/stylesheets/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end

class ToxCreateModel
	include DataMapper::Resource
	property :id, Serial
	property :name, String, :length => 255
	property :uri, String, :length => 255
	property :task_uri, String, :length => 255
	property :validation_task_uri, String, :length => 255
	property :validation_uri, String, :length => 255
	property :validation_report_task_uri, String, :length => 255
	property :validation_report_uri, String, :length => 255
	property :warnings, Text, :length => 2**32-1 
	property :nr_compounds, Integer
	property :created_at, DateTime
	
	def status
		RestClient.get(File.join(@task_uri, 'hasStatus')).body
	end

	def validation_status
		begin
			RestClient.get(File.join(@validation_task_uri, 'hasStatus')).body
		rescue
			"Service offline"
		end
	end

	def validation_report_status
		begin
			RestClient.get(File.join(@validation_report_task_uri, 'hasStatus')).body
		rescue
			"Service offline"
		end
	end

	def algorithm
		begin
			RestClient.get(File.join(@uri, 'algorithm')).body
		rescue
			""
		end
	end

	def training_dataset
		begin
			RestClient.get(File.join(@uri, 'trainingDataset')).body
		rescue
			""
		end
	end

	def feature_dataset
		begin
			RestClient.get(File.join(@uri, 'feature_dataset')).body
		rescue
			""
		end
	end

	def validation
		begin
			uri = File.join(@validation_uri, 'statistics')
			yaml = RestClient.get(uri).body
			v = YAML.load(yaml)
			tp=0; tn=0; fp=0; fn=0; n=0
			v[:classification_statistics][:confusion_matrix][:confusion_matrix_cell].each do |cell|
				if cell[:confusion_matrix_predicted] == "true" and cell[:confusion_matrix_actual] == "true"
					tp = cell[:confusion_matrix_value]
					n += tp
				elsif cell[:confusion_matrix_predicted] == "false" and cell[:confusion_matrix_actual] == "false"
					tn = cell[:confusion_matrix_value]
					n += tn
				elsif cell[:confusion_matrix_predicted] == "false" and cell[:confusion_matrix_actual] == "true"
					fn = cell[:confusion_matrix_value]
					n += fn
				elsif cell[:confusion_matrix_predicted] == "true" and cell[:confusion_matrix_actual] == "false"
					fp = cell[:confusion_matrix_value]
					n += fp
				end
			end
			{
				:n => n,
				:tp => tp,
				:fp => fp,
				:tn => tn,
				:fn => fn, 
				:correct_predictions => sprintf("%.2f", 100*(tp+tn).to_f/n),
				:weighted_area_under_roc => sprintf("%.3f", v[:classification_statistics][:weighted_area_under_roc].to_f),
				:sensitivity => sprintf("%.3f", tp.to_f/(tp+fn)),
				:specificity => sprintf("%.3f", tn.to_f/(tn+fp))
			}
		rescue
			"Service offline"
		end
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

  def process_model(model)
    if !model.uri and model.status == "Completed"
			model.uri = RestClient.get(File.join(model.task_uri, 'resultURI')).body
			model.save
		end
		#unless @@config[:services]["opentox-model"].match(/localhost/)
		if !model.validation_uri and model.validation_status == "Completed"
			begin
				model.validation_uri = RestClient.get(File.join(model.validation_task_uri, 'resultURI')).body
				LOGGER.debug "Validation URI: #{model.validation_uri}"
				model.validation_report_task_uri = RestClient.post(File.join(@@config[:services]["opentox-validation"],"/report/crossvalidation"), :validation_uris => model.validation_uri).body
				LOGGER.debug "Validation Report Task URI: #{model.validation_report_task_uri}"
				model.save
			rescue
			end
		end
		if model.validation_report_task_uri and !model.validation_report_uri and model.validation_report_status == 'Completed'
			model.validation_report_uri = RestClient.get(File.join(model.validation_report_task_uri, 'resultURI')).body
		end
		#end
  end
end

=======
>>>>>>> helma/master
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
	model.save

  begin
    case params[:view]
      when "model"
		    haml :model, :locals=>{:model=>model}, :layout => false
		  when /validation/
				if model.type == "classification"
					haml :classification_validation, :locals=>{:model=>model}, :layout => false
				elsif model.type == "regression"
					haml :regression_validation, :locals=>{:model=>model}, :layout => false
				else
					return "Unknown model type '#{model.type}'"
				end
		  else
				return "unable to render model: id #{params[:id]}, view #{params[:view]}"
		    #return "render error"
		end
	rescue
    return "unable to render model: id #{params[:id]}, view #{params[:view]}"
	end
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

	flash[:notice] = "Model creation and validation started - this may last up to several hours depending on the number and size of the training compounds."
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
		model.process unless model.uri
		LOGGER.debug model.to_yaml
		prediction = nil
		confidence = nil
		title = nil
		db_activities = []
		LOGGER.debug "curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}"
		prediction = YAML.load(`curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}`)
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

