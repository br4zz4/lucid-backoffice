require "lucid/backoffice"
require "minitest/autorun"
require "tmpdir"

DATABASE_URL = ENV.fetch("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/lucid_backoffice_test")

def ensure_test_database(url)
  uri = URI.parse(url)
  name = uri.path.delete_prefix("/")
  ActiveRecord::Base.establish_connection(url.sub(%r{/#{Regexp.escape(name)}\z}, "/postgres"))
  connection = ActiveRecord::Base.connection
  exists = connection.select_value("SELECT 1 FROM pg_database WHERE datname = #{connection.quote(name)}")
  connection.create_database(name) unless exists
ensure
  ActiveRecord::Base.remove_connection
end

ensure_test_database(DATABASE_URL)
ActiveRecord::Base.establish_connection(DATABASE_URL)

class BackofficeTest < Minitest::Test
  def setup
    Lucid::Backoffice.reset_configuration!
  end

  def teardown
    Lucid::Backoffice.reset_configuration!
  end

  def configure_minimal
    Lucid::Backoffice.configure do |config|
      config.current_operator = ->(_request) { :operator }
      config.authenticate = ->(_request) { true }
      yield config if block_given?
    end
  end

  def write_yaml(content)
    dir = Dir.mktmpdir
    path = File.join(dir, "classification.yml")
    File.write(path, content)
    path
  end
end
