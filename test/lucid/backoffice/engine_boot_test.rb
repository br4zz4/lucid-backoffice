require "test_helper"
require "minitest/mock"

class BackofficeEngineBootTest < Minitest::Test
  class EagerLoader
    def eager_load_dir(dir)
      Dir[File.join(dir, "**/*.rb")].sort.each { |file| load file }
    end
  end

  SAMPLE = "class Actions::Sample < Lucid::Backoffice::Action\n  on :users\n  perform { :done }\nend\n".freeze

  def with_app_root(root)
    autoloaders = Struct.new(:main).new(EagerLoader.new)
    Object.const_set(:Actions, Module.new) unless Object.const_defined?(:Actions, false)
    Rails.stub(:root, Pathname.new(root)) { Rails.stub(:autoloaders, autoloaders) { yield } }
  ensure
    Actions.send(:remove_const, :Sample) if Actions.const_defined?(:Sample, false)
    Lucid::Backoffice::Action.reset!
  end

  def run_to_prepare
    engine_file = File.expand_path("../../../lib/lucid/backoffice/engine.rb", __dir__)
    blocks = Lucid::Backoffice::Engine.config.to_prepare_blocks.select { |block| block.source_location.first == engine_file }
    assert_equal 1, blocks.size
    blocks.each(&:call)
  end

  def simulate_reload
    Actions.send(:remove_const, :Sample) if Actions.const_defined?(:Sample, false)
  end

  def write_sample(root)
    dir = File.join(root, "app/backoffice/actions")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "sample.rb"), SAMPLE)
  end

  def test_to_prepare_registers_actions_found_in_app_backoffice
    # arrange
    Dir.mktmpdir do |root|
      write_sample(root)
      with_app_root(root) do
        # act
        run_to_prepare

        # assert
        assert_equal "Actions::Sample", Lucid::Backoffice::Action.for_key("sample").name
      end
    end
  end

  def test_second_to_prepare_does_not_duplicate_the_registration
    # arrange
    Dir.mktmpdir do |root|
      write_sample(root)
      with_app_root(root) do
        run_to_prepare

        # act
        simulate_reload
        run_to_prepare

        # assert
        assert_equal 1, Lucid::Backoffice::Action.registry.count { |action| action.key == "sample" }
        assert_equal 1, Lucid::Backoffice::Action.for_target(:users).size
      end
    end
  end

  def test_to_prepare_drops_actions_removed_from_disk
    # arrange
    Dir.mktmpdir do |root|
      write_sample(root)
      with_app_root(root) do
        run_to_prepare
        simulate_reload
        FileUtils.rm_f(File.join(root, "app/backoffice/actions/sample.rb"))

        # act
        run_to_prepare

        # assert
        assert_nil Lucid::Backoffice::Action.for_key("sample")
      end
    end
  end

  def test_to_prepare_is_a_no_op_when_app_backoffice_is_missing
    # arrange
    Dir.mktmpdir do |root|
      with_app_root(root) do
        # act
        run_to_prepare

        # assert
        assert_empty Lucid::Backoffice::Action.registry
      end
    end
  end
end
