require "action_helper"

class ActionDslTest < ActionTest
  def test_key_is_the_underscored_class_name_without_namespace
    # arrange
    action_class = build_action("Admin::ChangeUserRole") { on :accounts }

    # act
    key = action_class.key

    # assert
    assert_equal "change_user_role", key
  end

  def test_defaults
    # arrange
    action_class = build_action("ChangeUserRole") { on :accounts }

    # act
    values = [action_class.label, action_class.permission, action_class.danger, action_class.transaction]

    # assert
    assert_equal ["Change user role", :run_action, :normal, true], values
  end

  def test_on_stores_the_target_as_string
    # arrange
    action_class = build_action { on :accounts }

    # act
    targets = [action_class.on, action_class.target]

    # assert
    assert_equal %w[accounts accounts], targets
  end

  def test_declared_settings_override_defaults
    # arrange
    action_class = build_action do
      on :tenant
      label "Fix role"
      permission :rewrite
      danger :high
      transaction false
    end

    # act
    values = [action_class.label, action_class.permission, action_class.danger, action_class.transaction]

    # assert
    assert_equal ["Fix role", :rewrite, :high, false], values
  end

  def test_field_is_stored_with_its_options
    # arrange
    choices = -> { %w[a b] }
    action_class = build_action do
      field :role, :select, choices: choices, required: false
    end

    # act
    field = action_class.fields[:role]

    # assert
    assert_equal [:role, :select, choices, false], [field.name, field.type, field.choices, field.required]
  end

  def test_field_defaults_to_string_and_required
    # arrange
    action_class = build_action { field :nickname }

    # act
    field = action_class.fields[:nickname]

    # assert
    assert_equal [:string, true], [field.type, field.required]
  end

  def test_fields_keep_declaration_order
    # arrange
    action_class = build_action do
      field :role
      field :nickname
      field :level, :integer
    end

    # act
    names = action_class.fields.keys

    # assert
    assert_equal %i[role nickname level], names
  end

  def test_field_defines_a_reader_for_the_coerced_value
    # arrange
    action_class = role_action
    action = action_class.new(record: create_account, params: { role: "coordinator" })

    # act
    action.prepare!

    # assert
    assert_equal "coordinator", action.role
  end

  def test_fields_are_not_shared_between_actions
    # arrange
    first = build_action("First") { field :role }
    second = build_action("Second") { field :nickname }

    # act
    names = [first.fields.keys, second.fields.keys]

    # assert
    assert_equal [[:role], [:nickname]], names
  end

  def test_only_if_registers_a_condition_and_hides
    # arrange
    action_class = build_action { only_if("not an owner") { record.owner? } }

    # act
    sizes = [action_class.conditions.size, action_class.guards.size]

    # assert
    assert_equal [1, 0], sizes
  end

  def test_unavailable_registers_a_guard_and_does_not_hide
    # arrange
    action_class = build_action { unavailable "No owner left", if: -> { record.last_owner? } }

    # act
    sizes = [action_class.conditions.size, action_class.guards.size]

    # assert
    assert_equal [0, 1], sizes
  end

  def test_unavailable_reason_is_nil_when_nothing_blocks
    # arrange
    action_class = build_action do
      only_if { record.owner? }
      unavailable "No owner left", if: -> { false }
    end
    action = action_class.new(record: create_account(role: "owner"))

    # act
    reason = action.unavailable_reason

    # assert
    assert_nil reason
  end

  def test_unavailable_reason_is_the_guard_explanation
    # arrange
    action_class = build_action { unavailable "No owner left", if: -> { record.last_owner? } }
    action = action_class.new(record: create_account(role: "owner"))

    # act
    reason = action.unavailable_reason

    # assert
    assert_equal "No owner left", reason
  end

  def test_unavailable_reason_is_the_only_if_reason
    # arrange
    action_class = build_action { only_if("Only owners") { record.owner? } }
    action = action_class.new(record: create_account(role: "teacher"))

    # act
    reason = action.unavailable_reason

    # assert
    assert_equal "Only owners", reason
  end

  def test_only_if_without_reason_has_a_generic_reason
    # arrange
    action_class = build_action { only_if { record.owner? } }
    action = action_class.new(record: create_account(role: "teacher"))

    # act
    reason = action.unavailable_reason

    # assert
    assert_equal "not available", reason
  end

  def test_blocks_run_with_the_record_and_tenant_of_the_action
    # arrange
    tenant = { slug: "school_a" }
    action_class = build_action { unavailable "wrong tenant", if: -> { tenant[:slug] == "school_a" } }
    action = action_class.new(tenant: tenant)

    # act
    reason = action.unavailable_reason

    # assert
    assert_equal "wrong tenant", reason
  end

  def test_subclasses_register_themselves
    # arrange
    action_class = build_action("ChangeUserRole") { on :accounts }

    # act
    registered = Action.registry

    # assert
    assert_includes registered, action_class
  end

  def test_for_key_finds_by_string_or_symbol
    # arrange
    action_class = build_action("ChangeUserRole") { on :accounts }

    # act
    found = [Action.for_key("change_user_role"), Action.for_key(:change_user_role)]

    # assert
    assert_equal [action_class, action_class], found
  end

  def test_for_key_returns_nil_when_unknown
    # arrange
    build_action("ChangeUserRole") { on :accounts }

    # act
    found = Action.for_key("missing")

    # assert
    assert_nil found
  end

  def test_for_target_returns_only_the_actions_of_that_target
    # arrange
    account = build_action("ChangeUserRole") { on :accounts }
    tenant = build_action("Rebuild") { on :tenant }
    global = build_action("Sweep") { on :global }

    # act
    found = [Action.for_target(:accounts), Action.for_target("tenant"), Action.for_target(:global)]

    # assert
    assert_equal [[account], [tenant], [global]], found
  end

  def test_for_target_returns_empty_when_nothing_matches
    # arrange
    build_action("ChangeUserRole") { on :accounts }

    # act
    found = Action.for_target(:students)

    # assert
    assert_empty found
  end

  def test_reset_clears_the_registry
    # arrange
    build_action("ChangeUserRole") { on :accounts }

    # act
    Action.reset!

    # assert
    assert_empty Action.registry
  end

  def test_reset_configuration_clears_the_registry
    # arrange
    build_action("ChangeUserRole") { on :accounts }

    # act
    Lucid::Backoffice.reset_configuration!

    # assert
    assert_empty Action.registry
  end

  def test_params_are_indifferent
    # arrange
    action = role_action.new(params: { "role" => "coordinator" })

    # act
    value = action.params[:role]

    # assert
    assert_equal "coordinator", value
  end
end
