require_relative "test_helper"
require "stringio"

class DummyHostTest < ActiveSupport::TestCase
  test "database adapter connects to the selected database" do
    connection = ActiveRecord::Base.connection
    assert_equal 1, connection.select_value("SELECT 1").to_i
    assert_equal ENV["DB"] == "sqlite" ? "SQLite" : "PostgreSQL", connection.adapter_name
    assert_match(/open_blog_dummy_test/, ActiveRecord::Base.connection_db_config.database)
  end

  test "host migrations provide Action Text and Active Storage" do
    assert ActionText::RichText.table_exists?
    assert ActiveStorage::Blob.table_exists?
    assert ActiveStorage::Attachment.table_exists?
    assert ActiveStorage::VariantRecord.table_exists?

    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("hello"), filename: "hello.txt", content_type: "text/plain")
    assert_equal "hello", blob.download
  ensure
    blob&.purge
  end

  test "host supplies assets and asynchronous framework integrations" do
    service = ActiveStorage::Blob.service
    assert_kind_of ActiveStorage::Service::DiskService, service
    assert_kind_of ActiveJob::QueueAdapters::TestAdapter, ActiveJob::Base.queue_adapter
    assert_kind_of Importmap::Map, Rails.application.importmap
    assert Rails.application.assets
    assert defined?(Tailwindcss::Engine)
  end
end
