class Ambit

	attr_accessor :uri, :model

	def initialize(uri)
		@uri = uri
		@model = Redland::Model.new Redland::MemoryStore.new
		parser = Redland::Parser.new
		benchmark = Benchmark.realtime do
			@rdf = RestClient.get @uri
		end
		LOGGER.debug "Getting RDF took " + sprintf("%.5f", benchmark) + "second(s)."
		benchmark = Benchmark.realtime do
			parser.parse_string_into_model(@model,@rdf,@uri)
		end
		LOGGER.debug "Parsing RDF took " + sprintf("%.5f", benchmark) + "second(s)."
	end

	def self.datasets
		datasets = {}
		index = Ambit.new "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset"
		index.model.subjects(RDF['type'],OT['Dataset']).each do |s|
			title = index.model.object(s,DC['title']).to_s
			identifier = index.model.object(s,DC['identifier']).to_s
			publisher = index.model.object(s,DC['publisher']).to_s
			datasets[identifier] = title
		end
		datasets.sort {|a,b| a[1]<=>b[1]}
	end

	def self.features(uri)
		features = {}
		index = Ambit.new File.join(uri,"features")
		LOGGER.debug index.uri
		index.model.subjects(RDF['type'],OT['Feature']).each do |s|
			title = index.model.object(s,DC['title']).to_s
			identifier = index.model.object(s,DC['identifier']).to_s.split(/\^/).first
			features[identifier] = title
		end
		#index.model.find(nil,nil,nil).each do |s,p,o|
		#index.model.subjects(nil,nil).each do |s|
=begin
		index.model.subjects(DC['type'],'http://www.w3.org/2001/XMLSchema#string').each do |s|
			title = index.model.object(s,DC['title']).to_s
			f = index.model.object(s,RDF['type']).to_s
			identifier = index.model.object(s,DC['identifier']).to_s.split(/\^/).first
			features[identifier] = title + ' (' + f + ')'
		end
		index.model.subjects(DC['type'],'http://www.w3.org/2001/XMLSchema#double').each do |s|
			title = index.model.object(s,DC['title']).to_s
			f = index.model.object(s,RDF['type']).to_s
			identifier = index.model.object(s,DC['identifier']).to_s.split(/\^/).first
			features[identifier] = title +  f 
		end
		index.model.subjects(DC['type'],'http://www.w3.org/2001/XMLSchema#boolean').each do |s|
			title = index.model.object(s,DC['title']).to_s
			f = index.model.object(s,RDF['type']).to_s
			identifier = index.model.object(s,DC['identifier']).to_s.split(/\^/).first
			features[identifier] = title +  f 
		end
=end
		features.sort{|a,b| a[1] <=> b[1]}
	end

	#def method_missing(name,*args)
		#name = name,sub(/_/:/)
	#end

end


