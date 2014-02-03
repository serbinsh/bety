class BulkUploadController < ApplicationController

  # step 1: Choose a file to upload.
  def start_upload
  end

  # step 2: Display the CSV file as a table.
  #
  # Session variables set:
  #     "csvpath", the path to where the uploaded file is stored
  # Instance variables set:
  #     @data, a CSV object containing the CSV file data
  #     @headers, an array of the headers of the CSV file; equals the corresponding session variable
  #     @errors (if there are any)
  def display_csv_file
    error = nil

    # Store the selected CSV file if we got here via the "upload file" button:
    if params["new upload"]
      uploaded_io = params["CSV file"]
      if uploaded_io
        file = File.open(Rails.root.join('public', 'uploads', uploaded_io.original_filename), 'wb')
        file.write(uploaded_io.read)
        session[:csvpath] = file.path
        file.close
      else
        # blank submission; no file was chosen
        session[:csvpath] = nil
      end
      session[:mapping] = nil # any existing mapping was for a (possibly) different file
    end

    # Get data out of the file and store in @headers and @data:
    if session[:csvpath]
      begin
        validate_csv = true # check CSV file is well-formed and throw exception if not
        read_data(validate_csv) # read CSV file at session[:cvspath] and set @data and @headers
      rescue CSV::MalformedCSVError => e
        errors = e.message
      end
    else
      errors = "No file chosen"
    end

    # Display the data in the file:
    respond_to do |format|
      format.html {
        if errors
          flash[:notice] = errors
          redirect_to(action: "start_upload")
        else
          render
        end
      }
    end
  end


  # step 3
  def map_data
    # reads CSV file and sets @data and @headers
    read_data # uses session[:csvpath] to set @headers and @data
    @displayed_columns = displayed_columns
  end


  # step 4
  def confirm_data

    # reads CSV file and sets @data and @headers
    read_data

    # Only set the mapping session value if the value from params is
    # non-nil: we might get here from a failed attempt at insert_data.
    if !params["mapping"].nil?
      session[:mapping] = params["mapping"]
    end
    @mapping = session[:mapping]

    # set @mapped_data from @data based on the mapping
    get_insertion_data

    @displayed_columns = displayed_columns
  end

  # step 5
  def insert_data
    # reads CSV file and sets @data and @headers
    read_data
    get_insertion_data

    errors = nil
    begin
      Trait.transaction do
        @mapped_data.each do |row|
          logger.info("about to insert #{row.inspect}")
          Trait.create(row)
        end
      end
    rescue => e
      errors = e.message
    end

    respond_to do |format|
      format.html {
        if errors
          flash[:notice] = errors
          redirect_to(action: "confirm_data")
        else
          redirect_to(action: "start_upload")
        end
      }
    end
  end
    




  private
  # Uses: 
  #     session[:csvpath], the path to the uploaded CSV file
  # Sets:
  #     @headers, the CSV file's header info
  #     @data, a CSV object corresponding to the uploaded file,
  #         positioned to read the first line after the header line
  def read_data(validate_csv = false)
    
    csvpath = session[:csvpath]
    
    csv = CSV.open(csvpath, { headers: true })

    if validate_csv
      # Checks that the file referenced by the CSV object @data is
      # well formed and triggers a CSV::MalformedCSVError exception if
      # it is not.
      csv.each do |row| # force exception if not well formed
        row.each do |c|
        end
      end

      csv.rewind # rewinds to the first line
    end

    csv.readline # need to read first line to get headers
    @headers = csv.headers

    # store CSV object in instance variable
    @data = csv

  end

  # Uses the specified data mapping to convert @data from a CSV object
  # to an Array of Hashes suitable for inserting into the traits
  # table.
  def get_insertion_data
    mapping = session[:mapping]
    default_values = mapping["value"]

    @mapped_data = Array.new
    @data.each do |csv_row|
      csv_row_as_hash = csv_row.to_hash

      # look up scientificname to get specie_id (if needed)
      species_key = nil
      if @headers.include?("scientificname")
        species_key = "scientificname"
      elsif @headers.include?("species.scientificname")
        species_key = "species.scientificname"
      end
      if !species_key.nil?
        sp = nil
        begin
          sp = Specie.find_by_scientificname(csv_row_as_hash[species_key])
        rescue
        end
        csv_row_as_hash["specie_id"] = sp ? sp.id.to_s : "NOT FOUND"
      end

      mapped_row = default_values.merge(csv_row_as_hash)

      # eliminate extraneous data from CSV row
      mapped_row.keep_if { |key, value| Trait.columns.collect { |column| column.name }.include?(key) }

      @mapped_data << mapped_row

    end

    @mapped_data
  end

  def displayed_columns
    Trait.columns.select { |col| !['id', 'created_at', 'updated_at'].include?(col.name) }
  end

end