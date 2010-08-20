require 'spreadsheet'
require 'roo'
class Parser

  attr_accessor :data, :type, :dataset, :format_errors, :smiles_errors, :activity_errors, :duplicates, :nr_compounds, :dataset_uri

  def initialize(file, endpoint_uri)

    @file = file
    @dataset = OpenTox::Dataset.new
    @feature_uri = endpoint_uri
    @dataset.features << endpoint_uri
    @dataset.title = URI.decode(endpoint_uri.split(/#/).last)
      @format_errors = ""
      @smiles_errors = []
    @activity_errors = []
    @duplicates = {}
    @nr_compounds = 0
    @data = []
    @activities = []
    @type = "classification"

    # check format by extension - not all browsers provide correct content-type]) 
    case File.extname(@file[:filename])
    when ".csv"
      self.csv
    when ".xls", ".xlsx"
      self.excel
    else
      @format_errors = "#{@file[:filename]} is a unsupported file type."
      return false
    end

    # create dataset
    @data.each do |items|
      @dataset.compounds << items[0]
      @dataset.data[items[0]] = [] unless @dataset.data[items[0]]
      case @type
      when "classification"
        case items[1].to_s
        when TRUE_REGEXP
          @dataset.data[items[0]] << {@feature_uri => true }
        when FALSE_REGEXP
          @dataset.data[items[0]] << {@feature_uri => false }
        end
      when "regression"
        if items[1].to_f == 0
          @activity_errors << "Row #{items[2]}: Zero values not allowed for regression datasets - entry ignored."
        else
          @dataset.data[items[0]] << {@feature_uri => items[1].to_f}
        end
      end
    end
    @dataset_uri = @dataset.save
  end

  def csv
    row = 0
    @file[:tempfile].each_line do |line|
      row += 1
      unless line.chomp.match(/^.+[,;].*$/) # check CSV format 
        @format_errors = "#{@file[:filename]} is not a valid CSV file."
        return false
      end
      items = line.chomp.gsub(/["']/,'').split(/\s*[,;]\s*/) # remove quotes
      LOGGER.debug items.join(",")
      input = validate(items[0], items[1], row) # smiles, activity
      @data << input if input
    end
  end

  def excel
    excel = 'tmp/' + @file[:filename]
    File.mv(@file[:tempfile].path,excel)
    begin
      if File.extname(@file[:filename]) == ".xlsx"    
        book = Excelx.new(excel)
      else
        book = Excel.new(excel)
      end
      book.default_sheet = 0
      1.upto(book.last_row) do |row|
        input = validate( book.cell(row,1), book.cell(row,2), row ) # smiles, activity
        @data << input if input
      end
      File.safe_unlink(@file[:tempfile])
    rescue
      @format_errors = "#{@file[:filename]} is not a valid Excel input file."
      return false
    end
  end

  def validate(smiles, act, row)
    compound = OpenTox::Compound.new(:smiles => smiles)
    if compound.inchi == ""
      @smiles_errors << "Row #{row}: " + [smiles,act].join(", ") 
      return false
    end
    unless numeric?(act) or OpenTox::Utils.classification?(act)
      @activity_errors << "Row #{row}: " + [smiles,act].join(", ")
      return false
    end
    @duplicates[compound.inchi] = [] unless @duplicates[compound.inchi]
    @duplicates[compound.inchi] << "Row #{row}: " + [smiles, act].join(", ")
    @type = "regression" unless OpenTox::Utils.classification?(act)
    @nr_compounds += 1
    [ compound.uri, act , row ]
  end

  def numeric?(object)
    true if Float(object) rescue false
  end

end
