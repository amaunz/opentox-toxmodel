['rubygems', "haml", "sass", "rack-flash"].each do |lib|
  require lib
end
gem "opentox-ruby-api-wrapper", "= 1.6.2"
require 'opentox-ruby-api-wrapper'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'
require 'ftools'
require 'tempfile'
require File.join(File.dirname(__FILE__),'model.rb')
require File.join(File.dirname(__FILE__),'helper.rb')
require File.join(File.dirname(__FILE__),'parser.rb')
require File.join(File.dirname(__FILE__),'balancer.rb')

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
    model.destroy!
    flash[:notice] = "#{model.name} model deleted."
  rescue
    flash[:notice] = "#{model.name} model delete error."
  end
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



post '/upload' do # AM: check upload

  if params[:endpoint] == ''
    flash[:notice] = "Please enter an endpoint name."
    redirect url_for('/create')
  end
  unless params[:endpoint] and params[:file] and params[:file][:tempfile]
    flash[:notice] = "Please enter an endpoint name and upload a Excel or CSV file."
    redirect url_for('/create')
  end

  feature_uri = url_for("/feature#"+URI.encode(params[:endpoint]), :full)
  parser = Parser.new params[:file], feature_uri

  unless parser.format_errors.empty?
    flash[:notice] = "Incorrect file format. Please follow the instructions for #{link_to "Excel", "/excel_format"} or #{link_to "CSV", "/csv_format"} formats."
  end

  if parser.dataset.compounds.empty?
    flash[:notice] = "Dataset #{params[:file][:filename]} is empty."
    redirect url_for('/create')
  end


  balancer = Balancer.new (parser.dataset, feature_uri, url_for('/', :full))
  @balanced_datasets = []
  @balanced_models = [] 

  # AM: majority split for classification datasets
  if balancer.datasets.size > 0
    @balanced_datasets = balancer.datasets
  end
  @main_dataset = parser.dataset_uri


  # AM: launch balanced models
  bm_task_uris = []
  @balanced_datasets.each do |d|
    bm_task_uris << OpenTox::Algorithm::Lazar.create_model(:dataset_uri => d, :prediction_feature => feature_uri)
  end
  bm_task_uris.each do |t|
    bm_task=OpenTox::Task.find(t)
    bm_task.wait_for_completion
    @balanced_models << bm_task.resultURI
  end

  # AM: create main model
  begin
    @main_model = ToxCreateModel.new
    @main_model.name = params[:endpoint]
    @main_model.task_uri = OpenTox::Algorithm::Lazar.create_model(:dataset_uri => @main_dataset, :prediction_feature => feature_uri, :models => @balanced_models)
  rescue
    flash[:notice] = "Model creation failed. Please check if the input file is in a valid #{link_to "Excel", "/excel_format"} or #{link_to "CSV", "/csv_format"} format."
  #  redirect url_for('/create')
  end


  # AM: crossvalidation for balanced models
  bm_validation_task_uris = [] # not actually used
  @balanced_datasets.each do |m|
    validation_task_uri = OpenTox::Validation.crossvalidation(
      :algorithm_uri => OpenTox::Algorithm::Lazar.uri,
      :dataset_uri => m,
      :prediction_feature => feature_uri,
      :algorithm_params => "feature_generation_uri=#{OpenTox::Algorithm::Fminer.uri}"
    ).uri
    bm_validation_task_uris << validation_task_uri
  end


  # AM: original crossvalidation
  validation_task_uri = OpenTox::Validation.crossvalidation(
    :algorithm_uri => OpenTox::Algorithm::Lazar.uri,
    :dataset_uri =>  @main_dataset,
    :prediction_feature => feature_uri,
    :algorithm_params => "feature_generation_uri=#{OpenTox::Algorithm::Fminer.uri}"
  ).uri
  @main_model.validation_task_uri = validation_task_uri
  @main_model.nr_compounds = OpenTox::Dataset.find(@main_dataset).compounds.size
  @main_model.save
  @main_model.warnings = ''
  @main_model.warnings += "<p>Incorrect Smiles structures (ignored):</p>" + parser.smiles_errors.join("<br/>") unless parser.smiles_errors.empty?
  @main_model.warnings += "<p>Irregular activities (ignored):</p>" + parser.activity_errors.join("<br/>") unless parser.activity_errors.empty?
  duplicate_warnings = ''
  parser.duplicates.each {|inchi,lines| duplicate_warnings += "<p>#{lines.join('<br/>')}</p>" if lines.size > 1 }
  @main_model.warnings += "<p>Duplicated structures (all structures/activities used for model building, please  make sure, that the results were obtained from <em>independent</em> experiments):</p>" + duplicate_warnings unless duplicate_warnings.empty?
  @main_model.save


  # AM: redirect
  flash[:notice] = "Model creation and validation started - this may last up to several hours depending on the number and size of the training compounds."
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
  params[:selection].keys.each do |id|
    model = ToxCreateModel.get(id.to_i)
    model.process unless model.uri
    prediction = nil
    confidence = nil
    title = nil
    db_activities = []
    #LOGGER.debug "curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}"
    prediction = YAML.load(`curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri} 2>/dev/null`)
    #prediction = YAML.load(OpenTox::Model::Lazar.predict(params[:compound_uri],params[:model_uri]))
    source = prediction.creator
    if prediction.data[@compound.uri]
      if source.to_s.match(/model/) # real prediction
        prediction = prediction.data[@compound.uri].first.values.first
        #LOGGER.debug prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")]
        #LOGGER.debug prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]
        if !prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")].nil?
          @predictions << {
            :title => model.name,
            :model_uri => model.uri,
            :prediction => prediction[File.join(@@config[:services]["opentox-model"],"lazar#classification")],
            :confidence => prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]
          }
        elsif !prediction[File.join(@@config[:services]["opentox-model"],"lazar#regression")].nil?
          @predictions << {
            :title => model.name,
            :model_uri => model.uri,
            :prediction => prediction[File.join(@@config[:services]["opentox-model"],"lazar#regression")],
            :confidence => prediction[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]
          }
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

post "/lazar/?" do
  @page = 0
  @page = params[:page].to_i if params[:page]
  #@highlight = params[:highlight]
  @model_uri = params[:model_uri]
  @prediction = YAML.load(OpenTox::Model::Lazar.predict(params[:compound_uri],params[:model_uri]))
  @compound = OpenTox::Compound.new(:uri => params[:compound_uri])
  @title = @prediction.title
  if @prediction.data[@compound.uri]
    if @prediction.creator.to_s.match(/model/) # real prediction
      p = @prediction.data[@compound.uri].first.values.first
      if !p[File.join(@@config[:services]["opentox-model"],"lazar#classification")].nil?
        feature = File.join(@@config[:services]["opentox-model"],"lazar#classification")
      elsif !p[File.join(@@config[:services]["opentox-model"],"lazar#regression")].nil?
        feature = File.join(@@config[:services]["opentox-model"],"lazar#regression")
      end
      @activity = p[feature]
      @confidence = p[File.join(@@config[:services]["opentox-model"],"lazar#confidence")]
      @neighbors = p[File.join(@@config[:services]["opentox-model"],"lazar#neighbors")]
      @features = p[File.join(@@config[:services]["opentox-model"],"lazar#features")]
    else # database value
      @measured_activities = @prediction.data[@compound.uri].first.values
    end
  else
    @activity = "not available (no similar compounds in the training dataset)"
  end
  haml :lazar
end

# proxy to get data from compound service
# (jQuery load does not work with external URIs)
get %r{/compound/(.*)} do |inchi|
  OpenTox::Compound.new(:inchi => inchi).names.gsub(/\n/,', ')
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
