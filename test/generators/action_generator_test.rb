require "test_helper"
require "rails/generators/test_case"
require "generators/lucid/backoffice/action/action_generator"

class BackofficeActionGeneratorTest < Rails::Generators::TestCase
  tests Lucid::Backoffice::Generators::ActionGenerator
  destination File.expand_path("../../tmp/generators_action", __dir__)

  setup { prepare_destination }

  def generated(path)
    File.read(File.join(destination_root, path))
  end

  test "creates the action file under app/backoffice/actions" do
    # arrange
    # act
    run_generator %w[ChangeUserRole]

    # assert
    assert_file "app/backoffice/actions/change_user_role.rb"
  end

  test "the generated class inherits from Lucid::Backoffice::Action inside Actions" do
    # arrange
    # act
    run_generator %w[ChangeUserRole]

    # assert
    assert_file "app/backoffice/actions/change_user_role.rb", /^class Actions::ChangeUserRole < Lucid::Backoffice::Action$/
  end

  test "accepts an underscored name" do
    # arrange
    # act
    run_generator %w[change_user_role]

    # assert
    assert_file "app/backoffice/actions/change_user_role.rb", /^class Actions::ChangeUserRole < Lucid::Backoffice::Action$/
  end

  test "accepts a namespaced name" do
    # arrange
    # act
    run_generator %w[users/change_role]

    # assert
    assert_file "app/backoffice/actions/users/change_role.rb", /^class Actions::Users::ChangeRole < Lucid::Backoffice::Action$/
  end

  test "the generated file is valid Ruby" do
    # arrange
    run_generator %w[ChangeUserRole]
    path = File.join(destination_root, "app/backoffice/actions/change_user_role.rb")

    # act
    syntax = RubyVM::InstructionSequence.compile_file(path)

    # assert
    assert_kind_of RubyVM::InstructionSequence, syntax
  end

  test "the namespaced generated file is valid Ruby" do
    # arrange
    run_generator %w[users/change_role]
    path = File.join(destination_root, "app/backoffice/actions/users/change_role.rb")

    # act
    syntax = RubyVM::InstructionSequence.compile_file(path)

    # assert
    assert_kind_of RubyVM::InstructionSequence, syntax
  end

  test "the generated file loads and registers the action" do
    # arrange
    run_generator %w[ChangeUserRole]
    path = File.join(destination_root, "app/backoffice/actions/change_user_role.rb")
    Object.const_set(:Actions, Module.new) unless Object.const_defined?(:Actions, false)
    Lucid::Backoffice::Action.reset!

    begin
      # act
      load path

      # assert
      action = Lucid::Backoffice::Action.for_key("change_user_role")
      assert_equal "Actions::ChangeUserRole", action.name
      assert_equal "users", action.target
    ensure
      Actions.send(:remove_const, :ChangeUserRole) if Actions.const_defined?(:ChangeUserRole, false)
      Lucid::Backoffice::Action.reset!
    end
  end

  test "the generated action raises NotImplementedError until the change is written" do
    # arrange
    run_generator %w[ChangeUserRole]
    path = File.join(destination_root, "app/backoffice/actions/change_user_role.rb")
    Object.const_set(:Actions, Module.new) unless Object.const_defined?(:Actions, false)
    Lucid::Backoffice::Action.reset!

    begin
      load path
      action = Lucid::Backoffice::Action.for_key("change_user_role")

      # act
      error = assert_raises(NotImplementedError) { action.allocate.instance_exec(&action.perform) }

      # assert
      assert_match(/write the change here/, error.message)
    ensure
      Actions.send(:remove_const, :ChangeUserRole) if Actions.const_defined?(:ChangeUserRole, false)
      Lucid::Backoffice::Action.reset!
    end
  end
end
