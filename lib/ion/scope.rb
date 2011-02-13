class Ion::Scope
  include Ion::Helpers

  attr_writer :key

  def initialize(search, args={}, &blk)
    @search  = search
    @gate    = args[:gate]  || :all
    @score   = args[:score] || 1.0

    yieldie(&blk) and done  if block_given?

    raise Ion::Error  unless [:all, :any].include?(@gate)
  end

  # Returns a unique hash of what the scope contains.
  def search_hash
    @search_hash ||= [[@gate, @score]]
  end

  def any_of(&blk)
    scopes << subscope(:gate => :any, &blk)
  end

  def all_of(&blk)
    scopes << subscope(:gate => :all, &blk)
  end

  def score(score, &blk)
    scopes << subscope(:score => (score * @score), &blk)
  end

  def key
    @key ||= Ion.volatile_key
  end

  def count
    key.zcard
  end

  # Defines the shortcuts `text :foo 'xyz'` => `search :text, :foo, 'xyz'`
  Ion::Indices.names.each do |type|
    define_method(type) do |field, what, args={}|
      search type, field, what, { :score => @score }.merge(args)
    end
  end

  # Searches a given field.
  # @example
  #   class Album
  #     ion { text :name }
  #   end
  #
  #   Album.ion.search {
  #     search :text, :name, "Emotional Technology"
  #     text :name, "Emotional Technology"   # same
  #   }
  def search(type, field, what, args={})
    subkey = options.index(type, field).search(what, args)
    searchkeys  << subkey
    subkeys     << subkey
    search_hash << [type,field,what,args]
  end

  def options
    @search.options
  end

  def ids
    results = key.zrevrange(0, -1)
    expire and results
  end

protected
  def scopes()     @scopes ||= Array.new end
  def subkeys()    @subkeys ||= Array.new end
  def searchkeys() @searchkeys ||= Array.new end

  # Called by #run after doing an instance_eval of DSL stuff.
  # This consolidates the keys into self.key.
  def done
    if subkeys.size == 1
      self.key = subkeys.first
    elsif subkeys.size > 1
      combine subkeys
    end
  end

  # Sets the TTL for the temp keys.
  def expire
    scopes.each { |s| s.send :expire }
    Ion.expire key, *searchkeys
  end

  def combine(subkeys)
    if @gate == :all
      key.zinterstore subkeys
    elsif @gate == :any
      key.zunionstore subkeys
    end
  end

  # Used by all_of and any_of
  def subscope(args={}, &blk)
    opts  = { :gate => @gate, :score => @score }
    scope = Ion::Scope.new(@search, opts.merge(args), &blk)

    subkeys     << scope.key
    search_hash << scope.search_hash
    scope
  end
end
