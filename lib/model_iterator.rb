# Iterates over large models, storing state in Redis.
class ModelIterator
  VERSION = "1.0.4"

  class MaxIterations < StandardError
    attr_reader :iterator
    def initialize(iter)
      @iterator = iter
      super "Hit the max (#{iter.max}), stopping at id #{iter.current_id}."
    end
  end

  class << self
    # Gets or sets a default Redis client object for iterators.
    attr_accessor :redis
  end

  # Gets a reference to the ActiveRecord::Base class that is iterated.
  #
  # Returns a Class.
  attr_reader :klass

  # Gets or sets the number of records that are returned in each database
  # query.
  #
  # Returns a Fixnum.
  attr_accessor :limit

  # Gets a String SQL Where clause fragment.  Use `?` for variable 
  # substitution.
  #
  # Returns a String.
  attr_reader :clause

  # Gets an Array of values to be sql-escaped and joined with the clause.
  #
  # Returns an Array of unescaped sql values.
  attr_reader :clause_args

  # Gets a String used to prefix the redis keys used by this object.
  attr_reader :prefix

  # Gets a Fixnum value of the maximum iterations to run, or 0.
  attr_reader :max

  # Gets the String name of the ID field.
  attr_reader :id_field

  # Gets the String fully qualified ID field (with the table name).
  attr_reader :id_clause

  # Gets the :joins value for ActiveRecord::Base.find.
  attr_reader :joins

  # Gets or sets a Proc that is called with each model instance while
  # iterating.  This is set automatically by #each.
  attr_accessor :job

  # Gets or sets the Redis client object.
  attr_accessor :redis

  # Initializes a ModelIterator instance.
  #
  # klass   - ActiveRecord::Base class to iterate.
  # clause  - String SQL WHERE clause, with '?' placeholders for values.
  # *values - Optional array of values to be added to a custom SQL WHERE
  #           clause.
  # options - Optional Hash options.
  #           :redis     - A Redis object for storing the state.
  #           :order     - Symbol specifying the order to iterate.  :asc or
  #                        :desc.  Default: :asc
  #           :id_field  - String name of the ID column.  Default: "id"
  #           :id_clause - String name of the fully qualified ID column.
  #                        Prepends the model's table name to the front of
  #                        the ID field.  Default: "table_name.id"
  #           :start_id  - Fixnum to start iterating from.  Default: 1
  #           :prefix    - Custom String prefix for redis keys.
  #           :select    - Optional String of the columns to retrieve.
  #           :joins     - Optional Symbol or Hash :joins option for 
  #                        ActiveRecord::Base.find.
  #           :max       - Optional Fixnum of the maximum number of iterations.
  #                        Use max * limit to process a known number of records
  #                        at a time.
  #           :limit     - Fixnum limit of objects to fetch from the db.
  #                        Default: 100
  #           :conditions - Array of String SQL WHERE clause and optional values
  #                         (Will override clause/values given in arguments.)
  #
  #   ModelIterator.new(Repository, :start_id => 5000)
  #   ModelIterator.new(Repository, 'public=?', true, :start_id => 1000)
  #
  def initialize(klass, *args)
    @klass = klass
    @options = if args.last.respond_to?(:fetch)
      args.pop
    else
      {}
    end
    @redis = @options[:redis] || self.class.redis
    @id_field = @options[:id_field] || klass.primary_key
    @id_clause = @options[:id_clause] || "#{klass.table_name}.#{@id_field}"
    @order = @options[:order] == :desc ? :desc : :asc
    op = @order == :asc ? '>' : '<'
    @max = @options[:max].to_i
    @joins = @options[:joins]
    @clause =  "#{@id_clause} #{op} ?"

    if !(conditions = Array(@options[:conditions] || args)).empty?
      @clause += " AND (#{conditions.shift})"
    end

    @clause_args = conditions

    @current_id = @options[:start_id]
    @limit = @options[:limit] || 100
    @job = @prefix = @key = nil
  end

  # Public: Points to the latest record that was yielded, by database ID.
  #
  # refresh - Boolean that determines if the instance variable cache should
  #           be reset first.  Default: false.
  #
  # Returns a Fixnum.
  def current_id(refresh = false)
    @current_id = nil if refresh
    @current_id ||= @redis.get(key).to_i
  end

  # Public: Sets the latest processed Integer ID.
  attr_writer :current_id

  # Public: Iterates through the whole dataset, yielding individual records as
  # they are received.  This calls #records multiple times, setting the
  # #current_id after each run.  If an exception is raised, the ModelIterator
  # instance can safely be restarted, since all state is stored in Redis.
  #
  # &block - Block that gets called with each ActiveRecord::Base instance.
  #
  # Returns nothing.
  def each
    @job = block = (block_given? ? Proc.new : @job)
    each_set do |records|
      records.each do |record|
        block.call(record)
        update_current_id(record)
      end
    end
    cleanup
  end

  # Public: Iterates through the whole dataset.  This calls #records multiple
  # times, but does not set the #current_id after each record.
  #
  # &block - Block that gets called with each ActiveRecord::Base instance.
  #
  # Returns nothing.
  def each_set(&block)
    loops = 0
    while records = self.records
      begin
        block.call(records)
        loops += 1
        if @max > 0 && loops >= @max
          raise MaxIterations, self
        end
      ensure
        @redis.set(key, @current_id) if @current_id
      end
    end
  end

  # Public: Simple alias for #each with no block.  Useful if the job errors,
  # and you want to retry it again from where it left off.
  alias run each

  # Public: Cleans up any redis keys.
  #
  # Returns nothing.
  def cleanup
    @redis.del(key)
    @current_id = nil
  end

  def prefix
    @prefix = [@options[:prefix], self.class.name, @klass.name].
      compact.join(":")
  end

  def key
    @key ||= "#{prefix}:current"
  end

  # Public: Gets an ActiveRecord :connections value, ready for
  # ActiveRecord::Base.all.
  #
  # Returns an Array with a String query clause, and unescaped db values.
  def conditions
    [@clause, current_id, *@clause_args]
  end

  # Public: Queries the database for the next page of records.
  #
  # Returns an Array of ActiveRecord::Base instances if any results are
  # returned, or nil.
  def records
    options = find_options
    query = @klass.where(options[:conditions]).limit(options[:limit]).order(options[:order])
    query = query.select(options[:select]) if options[:select]
    query = query.joins(options[:joins]) if options[:joins]
    arr = query.to_a
    arr.empty? ? nil : arr
  end

  # Public: Builds the ActiveRecord::Base.find options for a single query.
  #
  # Returns a Hash.
  def find_options
    opt = {:conditions => conditions, :limit => @limit, :order => "#{@id_clause} #{@order}"}
    if columns = @options[:select]
      opt[:select] = columns
    end
    opt[:joins] = @joins if @joins
    opt
  end

  # Updates the current ID for the given record.
  #
  # record - A single record from the iteration.
  #
  # Returns nothing.
  def update_current_id(record)
    @current_id = record.send(@id_field)
  end

  # Pass this to ModelIterator if you don't want to store state anywhere.
  class NullRedis
    @instance = new

    def self.new
      @instance
    end

    def get(key)
      0
    end

    def set(key, value)
    end

    def del(key)
    end
  end
end

