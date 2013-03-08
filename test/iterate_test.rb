require File.expand_path("../helper", __FILE__)

class IterateTest < ModelIterator::TestCase
  def test_finds_current_iteration_of_records
    iter = ModelIterator.new Model, :redis => RedisClient.new
    assert_equal %w(a b c), iter.records.map(&:name)
  end

  def test_loops_through_all_records
    names = []
    iter = ModelIterator.new Model, :redis => RedisClient.new, :limit => 1
    iter.each do |m|
      names << m.name
    end

    assert_equal %w(a b c), names
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

  class ExpectedError < StandardError; end
end

