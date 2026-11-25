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

  def test_field_title_is_the_string_label
    # arrange
    action_class = build_action { field :email, :string, label: "E-mail" }

    # act
    title = action_class.fields[:email].title

    # assert
    assert_equal "E-mail", title
  end

  def test_field_title_calls_a_callable_label
    # arrange
    action_class = build_action { field :email, :string, label: -> { "E-mail #{1 + 1}" } }

    # act
    title = action_class.fields[:email].title

    # assert
    assert_equal "E-mail 2", title
  end

  def test_field_title_without_label_is_the_humanized_name
    # arrange
    action_class = build_action { field :contact_email }

    # act
    title = action_class.fields[:contact_email].title

    # assert
    assert_equal "Contact email", title
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

  def test_on_is_a_record_target_by_default
    # arrange
    action_class = build_action { on :accounts }

    # act
    collection = action_class.collection?

    # assert
    refute collection
  end

  def test_on_collection_marks_the_action_as_collection
    # arrange
    action_class = build_action { on :accounts, collection: true }

    # act
    values = [action_class.collection?, action_class.target]

    # assert
    assert_equal [true, "accounts"], values
  end

  def test_landing_defaults_to_nil_and_stores_a_symbol
    # arrange
    plain = build_action { on :accounts }
    landing = build_action { on :accounts; landing "list" }

    # act
    values = [plain.landing, landing.landing]

    # assert
    assert_equal [nil, :list], values
  end

  def test_failure_exposes_type_and_errors
    # arrange
    failure = Action::Failure.new(type: :invalid, errors: ["Name can't be blank"])

    # act
    values = [failure.type, failure.errors, failure[:errors], failure.failure?]

    # assert
    assert_equal [:invalid, ["Name can't be blank"], ["Name can't be blank"], true], values
  end

  def test_submit_is_stored_with_key_label_and_condition
    # arrange
    condition = -> { true }
    action_class = build_action do
      submit :email, label: "Enviar por e-mail", if: condition
      submit :screen, label: "Mostrar na tela"
    end

    # act
    submits = action_class.submits

    # assert
    assert_equal [[:email, "Enviar por e-mail", condition], [:screen, "Mostrar na tela", nil]], submits.map { |option| [option[:key], option[:label], option[:condition]] }
  end

  def test_submit_key_is_a_symbol
    # arrange
    action_class = build_action { submit "email", label: "Enviar" }

    # act
    key = action_class.submits.sole[:key]

    # assert
    assert_equal :email, key
  end

  def test_action_without_submit_declares_no_submits
    # arrange
    action_class = build_action { on :accounts }

    # act
    submits = action_class.submits

    # assert
    assert_empty submits
  end

  def test_submits_are_not_shared_between_actions
    # arrange
    first = build_action("First") { submit :email, label: "Enviar" }
    second = build_action("Second") { on :accounts }

    # act
    submits = [first.submits.size, second.submits.size]

    # assert
    assert_equal [1, 0], submits
  end

  def test_available_submits_keep_the_declared_order_and_drop_the_ones_whose_condition_fails
    # arrange
    action_class = build_action do
      submit :screen, label: "Mostrar na tela"
      submit :email, label: "Enviar por e-mail", if: -> { false }
      submit :both, label: "Os dois", if: -> { true }
    end

    # act
    keys = action_class.new.available_submits.map { |option| option[:key] }

    # assert
    assert_equal %i[screen both], keys
  end

  def test_submit_condition_is_evaluated_in_the_action_instance
    # arrange
    action_class = build_action do
      on :accounts
      submit :email, label: "Enviar por e-mail", if: -> { record.nickname == "Mia" }
    end
    mia = Account.new(nickname: "Mia")
    zed = Account.new(nickname: "Zed")

    # act
    keys = [mia, zed].map { |account| action_class.new(record: account).available_submits.map { |option| option[:key] } }

    # assert
    assert_equal [[:email], []], keys
  end

  def test_submit_condition_can_read_the_email_availability
    # arrange
    configure_minimal { |config| config.email_available = -> { false } }
    action_class = build_action { submit :email, label: "Enviar por e-mail", if: -> { email_available? } }
    action = action_class.new

    # act
    before = action.available_submits
    Lucid::Backoffice.configuration.email_available = -> { true }
    after = action.available_submits.map { |option| option[:key] }

    # assert
    assert_empty before
    assert_equal [:email], after
  end

  def test_submitted_is_the_chosen_option_as_a_symbol
    # arrange
    action_class = build_action { submit :email, label: "Enviar" }

    # act
    submitted = [action_class.new(submit: "email").submitted, action_class.new(submit: :screen).submitted]

    # assert
    assert_equal %i[email screen], submitted
  end

  def test_submitted_is_nil_when_nothing_was_chosen
    # arrange
    action_class = build_action { on :accounts }

    # act
    submitted = [action_class.new.submitted, action_class.new(submit: "").submitted]

    # assert
    assert_equal [nil, nil], submitted
  end

  def test_secret_for_is_nil_without_a_block
    # arrange
    action = build_action { on :accounts }.new

    # act
    secret = action.secret_for(:value)

    # assert
    assert_nil secret
  end

  def test_secret_for_returns_the_block_string_with_the_value
    # arrange
    action = build_action { on :accounts; secret { |value| "tok-#{value}" } }.new

    # act
    secret = action.secret_for(7)

    # assert
    assert_equal "tok-7", secret
  end

  def test_secret_for_is_nil_when_the_block_returns_nil_or_blank
    # arrange
    nil_action = build_action { on :accounts; secret { |_value| nil } }.new
    blank_action = build_action { on :accounts; secret { |_value| "  " } }.new

    # act
    secrets = [nil_action.secret_for(1), blank_action.secret_for(1)]

    # assert
    assert_equal [nil, nil], secrets
  end
end
