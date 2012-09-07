require 'rubygems'
require 'test/unit'
require 'active_record'
require File.expand_path("../../lib/model_iterator", __FILE__)

class ModelIterator::TestCase < Test::Unit::TestCase
  class Model < ActiveRecord::Base
    establish_connection :adapter => 'sqlite3', :database => ':memory:'
    connection.create_table table_name do |c|
      c.column :name, :string
    end

    %w(a b c).each do |s|
      create!(:name => s)
    end
  end

  class RedisClient
    def initialize(hash = nil)
      @hash = hash || {}
    end

    def [](key)
      @hash[key]
    end
    alias get []

    def []=(key, value)
      @hash[key] = value
    end
    alias set []=

    def delete(key)
      @hash.delete(key)
    end

    alias del delete
  end
end

