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
  end
end

