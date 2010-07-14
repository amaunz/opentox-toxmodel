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
	property :type, String
	property :created_at, DateTime

	def status
		#begin
			RestClient.get(File.join(@task_uri, 'hasStatus')).body
		#rescue
		#	"Service offline"
		#end
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

	def classification_validation
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

	def regression_validation
		begin
			uri = File.join(@validation_uri, 'statistics')
			yaml = RestClient.get(uri).body
			v = YAML.load(yaml)
		rescue
			"Service offline"
		end
	end

  def process

    if @uri.nil? and status == "Completed"
			update :uri => RestClient.get(File.join(@task_uri, 'resultURI')).body
			lazar = YAML.load(RestClient.get(@uri, :accept => "application/x-yaml").body)
			case lazar.dependentVariables
			when /classification/
				update :type => "classification"
			when /regression/
				update :type => "regression"
			else
				update :type => "unknown"
			end

		elsif @validation_uri.nil? and validation_status == "Completed"
			begin
				update :validation_uri => RestClient.get(File.join(@validation_task_uri, 'resultURI')).body
				LOGGER.debug "Validation URI: #{@validation_uri}"
				update :validation_report_task_uri => RestClient.post(File.join(@@config[:services]["opentox-validation"],"/report/crossvalidation"), :validation_uris => @validation_uri).body
				LOGGER.debug "Validation Report Task URI: #{@validation_report_task_uri}"
			rescue
				LOGGER.warn "Cannot create Validation Report Task #{@validation_report_task_uri} for  Validation URI #{@validation_uri} from Task #{@validation_task_uri}"
			end

		elsif @validation_report_uri.nil? and validation_report_status == "Completed"
			begin
				LOGGER.debug File.join(@validation_report_task_uri, 'resultURI')
				LOGGER.debug "Report URI: "+RestClient.get(File.join(@validation_report_task_uri, 'resultURI')).body
				update :validation_report_uri => RestClient.get(File.join(@validation_report_task_uri, 'resultURI')).body
			rescue
				LOGGER.warn "Cannot create Validation Report for  Task URI #{@validation_report_task_uri} "
			end
		end

		#LOGGER.debug self.to_yaml
		#LOGGER.debug @uri
		#LOGGER.debug @validation_uri
		#LOGGER.debug @validation_uri.nil?
		#LOGGER.debug validation_status
		#LOGGER.debug self.validation_report_task_uri
		#LOGGER.debug self.validation_report_uri
		#self.save
  end

end

DataMapper.auto_upgrade!
