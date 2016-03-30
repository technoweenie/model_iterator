require File.expand_path("../helper", __FILE__)

class IterateTest < ModelIterator::TestCase
  def test_finds_current_iteration_of_records
    iter = ModelIterator.new Model, :redis => RedisClient.new
    assert_equal %w(a b c), iter.records.map(&:name)
  end

  def test_loops_through_all_records
    names = []
    redis = RedisClient.new
    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(a b c), names
  end

  def test_loops_through_all_sets
    names = []
    redis = RedisClient.new
    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    iter.each_set do |records|
      names << records.map(&:name)
      iter.update_current_id(records.last)
    end

    assert_equal [%w(a), %w(b), %w(c)], names

    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    assert_equal 3, iter.current_id
  end

  def test_loops_through_all_sets_with_null_redis
    names = []
    redis = ModelIterator::NullRedis.new
    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    iter.each_set do |records|
      names << records.map(&:name)
      iter.update_current_id(records.last)
    end

    assert_equal [%w(a), %w(b), %w(c)], names

    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    assert_equal 0, iter.current_id
  end

  def test_loops_through_filtered_records
    names = []
    iter = ModelIterator.new Model, 'name != ?', 'a',
      :redis => RedisClient.new, :limit => 1
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(b c), names
  end

  def test_loops_through_filtered_records_from_options
    names = []
    iter = ModelIterator.new Model,
      :redis => RedisClient.new, :limit => 1,
      :conditions => ['name != ?', 'a']
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(b c), names
  end

  def test_loops_through_filtered_records_from_options_as_plain_sql
    names = []
    iter = ModelIterator.new Model,
      :redis => RedisClient.new, :limit => 1,
      :conditions => "name != 'a'"
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(b c), names
  end

  def test_loops_through_records_in_reverse
    names = []
    iter = ModelIterator.new Model, :redis => RedisClient.new, :limit => 1,
      :start_id => 100000, :order => :desc
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(c b a), names
  end

  def test_loops_through_known_number_of_records
    names = []
    iter = ModelIterator.new Model, :redis => RedisClient.new,
      :limit => 1, :start_id => 0, :max => 2

    assert_raises ModelIterator::MaxIterations do
      iter.each do |m|
        names << m.name
      end
    end

    assert_equal %w(a b), names
  end

  def test_allows_restart_of_records_after_error
    redis = RedisClient.new
    names = []
    iter = ModelIterator.new Model, :redis => redis, :start_id => 0
    badjob = lambda do |m|
      raise(ExpectedError) if m.id != 1
      names << m.name
    end

    2.times do
      assert_raises ExpectedError do
        iter.each(&badjob)
      end
    end

    assert_equal badjob, iter.job
    assert_equal %w(a), names

    iter = ModelIterator.new Model, :redis => redis, :limit => 1
    assert_equal 1, iter.current_id
    iter.job = lambda { |m| names << m.name }
    iter.run

    assert_equal %w(a b c), names
  end

  def test_select_option_honored
    names = []
    redis = RedisClient.new
    iter = ModelIterator.new Model, :redis => redis, :limit => 1, :select => :id
    iter.each do |m|
      assert_false m.attributes.has_key?(:name)
    end
  end

  def test_joins_can_be_used
    redis = RedisClient.new
    iter = ModelIterator.new Model, :redis => redis, :limit => 1, :joins => :associated_model
    iter.each do |m|
      assert_not_nil m.associated_model
    end
  end

  class ExpectedError < StandardError; end
end

