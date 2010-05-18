['rubygems', "haml", "sass", "rack-flash"].each do |lib|
	require lib
end
gem 'opentox-ruby-api-wrapper', '= 1.5.0'
require 'opentox-ruby-api-wrapper'
gem 'sinatra-static-assets'
require 'sinatra/static_assets'
require 'spreadsheet'
LOGGER.progname = File.expand_path __FILE__

use Rack::Flash
set :sessions, true

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
		RestClient.get(File.join(@validation_task_uri, 'hasStatus')).body if @validation_task_uri
	end

	def validation_report_status
		RestClient.get(File.join(@validation_report_task_uri, 'hasStatus')).body
	end

	def algorithm
		begin
			RestClient.get(File.join(@uri, 'algorithm')).body
		rescue
			""
		end
	end

	def training_dataset
		RestClient.get(File.join(@uri, 'trainingDataset')).body
	end

	def feature_dataset
		RestClient.get(File.join(@uri, 'feature_dataset')).body
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
		if !model.uri and model.status == "Completed"
			model.uri = RestClient.get(File.join(model.task_uri, 'resultURI')).body
			model.save
		end
		unless @@config[:services]["opentox-model"].match(/localhost/)
			if !model.validation_uri and model.validation_status == "Completed"
				model.validation_uri = RestClient.get(File.join(model.validation_task_uri, 'resultURI')).body
				LOGGER.debug "Validation URI: #{model.validation_uri}"
				model.validation_report_task_uri = RestClient.post(File.join(@@config[:services]["opentox-validation"],"/report/crossvalidation"), :validation_uris => model.validation_uri).body
				LOGGER.debug "Validation Report Task URI: #{model.validation_report_task_uri}"
				model.save
			end
			if model.validation_report_task_uri and !model.validation_report_uri and model.validation_report_status == 'Completed'
				model.validation_report_uri = RestClient.get(File.join(model.validation_report_task_uri, 'resultURI')).body
			end
		end
	end
	@refresh = true #if @models.collect{|m| m.status}.grep(/started|created/)
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

get '/model/:id/?' do
  response['Content-Type'] = 'text/plain'
	model = ToxCreateModel.get(params[:id])
  if !model.uri and model.status == "Completed"
	  model.uri = RestClient.get(File.join(model.task_uri, 'resultURI')).body
	  model.save
  end
=begin
		unless @@config[:services]["opentox-model"].match(/localhost/)
			if !model.validation_uri and model.validation_status == "Completed"
				model.validation_uri = RestClient.get(File.join(model.validation_task_uri, 'resultURI')).body
				LOGGER.debug "Validation URI: #{model.validation_uri}"
				model.validation_report_task_uri = RestClient.post(File.join(@@config[:services]["opentox-validation"],"/report/crossvalidation"), :validation_uris => model.validation_uri).body
				LOGGER.debug "Validation Report Task URI: #{model.validation_report_task_uri}"
				model.save
			end
			if model.validation_report_task_uri and !model.validation_report_uri and model.validation_report_status == 'Completed'
				model.validation_report_uri = RestClient.get(File.join(model.validation_report_task_uri, 'resultURI')).body
			end
		end
=end

	@refresh = true #if @models.collect{|m| m.status}.grep(/started|created/)

  begin
		haml :model, :locals=>{:model=>model}, :layout => false
	rescue
    return "unable to renderd model"
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
	dataset = OpenTox::Dataset.new
	dataset.title = params[:endpoint]
	feature_uri = url_for("/feature#"+URI.encode(params[:endpoint]), :full)
	dataset.features << feature_uri
	smiles_errors = []
	activity_errors = []
	duplicates = {}
	nr_compounds = 0
	line_nr = 1

  case params[:file][:type] 
  when "application/csv", "text/csv"
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
  			dataset.compounds << compound_uri
  			dataset.data[compound_uri] = [] unless dataset.data[compound_uri]
  			case items[1].to_s
  			when '1'
  				dataset.data[compound_uri] << {feature_uri => true }
  				nr_compounds += 1
  			when '0'
  				dataset.data[compound_uri] << {feature_uri => false }
  				nr_compounds += 1
  			else
  				activity_errors << "Line #{line_nr}: " + line.chomp
  			end
  		else
  			smiles_errors << "Line #{line_nr}: " + line.chomp
  		end
  		line_nr += 1
  	end	
  when "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    require 'roo'
    require 'ftools'
    excel = 'tmp/' + params[:file][:filename]
    name = params[:file][:filename]
    File.mv(params[:file][:tempfile].path,excel)
    if params[:file][:type] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"    
      book = Excelx.new(excel)
    else
      book = Excel.new(excel)
    end
    book.default_sheet = 0
    1.upto(book.last_row) do |row|
      smiles = book.cell(row,1)
      c = OpenTox::Compound.new(:smiles => smiles)
      if c.inchi != ""
    	duplicates[c.inchi] = [] unless duplicates[c.inchi]
    	duplicates[c.inchi] << "Line #{line_nr}: " + book.cell(row,1).chomp
    	compound_uri = c.uri
    			dataset.compounds << compound_uri
    			dataset.data[compound_uri] = [] unless dataset.data[compound_uri]
    			case book.cell(row,2).to_s
    			when '1'
    				dataset.data[compound_uri] << {feature_uri => true }
    				nr_compounds += 1
    			when '0'
    				dataset.data[compound_uri] << {feature_uri => false }
    				nr_compounds += 1
    			else
    				activity_errors << "Line #{line_nr}: " + book.cell(row,1).chomp
    			end
    		else
    			smiles_errors << "Line #{line_nr}: " + book.cell(row,1).chomp
    		end
    		line_nr += 1
    end
  else
    LOGGER.error "Fileupload Error: " +  params[:file].inspect 
  end	
	dataset_uri = dataset.save 
	task_uri = OpenTox::Algorithm::Lazar.create_model(:dataset_uri => dataset_uri, :prediction_feature => feature_uri)
	@model.task_uri = task_uri

	unless @@config[:services]["opentox-model"].match(/localhost/)
		validation_task_uri = OpenTox::Validation.crossvalidation(
			:algorithm_uri => OpenTox::Algorithm::Lazar.uri,
			:dataset_uri => dataset_uri,
			:prediction_feature => feature_uri,
			:algorithm_params => "feature_generation_uri=#{OpenTox::Algorithm::Fminer.uri}"
		).uri
		#LOGGER.debug "Validation task: " + validation_task_uri
		@model.validation_task_uri = validation_task_uri
	end

	@model.nr_compounds = nr_compounds
	@model.warnings = ''

	if smiles_errors.size > 0
		@model.warnings += "<p>Incorrect Smiles structures (ignored):</p>"
		@model.warnings += smiles_errors.join("<br/>")
	end
	if activity_errors.size > 0
		@model.warnings += "<p>Irregular activities (ignored - please use 1 for active and 0 for inactive compounds):</p>"
		@model.warnings += activity_errors.join("<br/>")
	end
	duplicate_warnings = ''
	duplicates.each {|inchi,lines| duplicate_warnings += "<p>#{lines.join('<br/>')}</p>" if lines.size > 1 }
	unless duplicate_warnings == ''
		@model.warnings += "<p>Duplicated structures (all structures/activities used for model building, please  make sure, that the results were obtained from <em>independent</em> experiments):</p>" 
		@model.warnings +=  duplicate_warnings
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
	params[:selection].keys.each do |id|
		model = ToxCreateModel.get(id.to_i)
		prediction = nil
		confidence = nil
		title = nil
		db_activities = []
		LOGGER.debug model.inspect
		prediction = YAML.load(`curl -X POST -d 'compound_uri=#{@compound.uri}' -H 'Accept:application/x-yaml' #{model.uri}`)
		source = prediction.creator
		if prediction.data[@compound.uri]
			if source.to_s.match(/model/)
				prediction = prediction.data[@compound.uri].first.values.first
				@predictions << {:title => model.name, :prediction => prediction[:classification], :confidence => prediction[:confidence]}
			else
				prediction = prediction.data[@compound.uri].first.values
				@predictions << {:title => model.name, :measured_activities => prediction}
			end
		else
			@predictions << {:title => model.name, :prediction => "not available (no similar compounds in the training dataset)"}
		end
	end

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
