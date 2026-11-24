require "action_helper"

class ActionFieldTest < ActionTest
  def field(type, name: :value, choices: nil, default: nil, required: true)
    Action::Field.new(name: name, type: type, choices: choices, default: default, of: nil, scope: nil, partial: nil, required: required)
  end

  def coerce(field, value, action = Action.new)
    field.coerce(value, action)
  end

  def test_string_becomes_a_string
    # arrange
    field = field(:string)

    # act
    value = coerce(field, 123)

    # assert
    assert_equal "123", value
  end

  def test_text_becomes_a_string
    # arrange
    field = field(:text)

    # act
    value = coerce(field, "long\ntext")

    # assert
    assert_equal "long\ntext", value
  end

  def test_integer_becomes_an_integer
    # arrange
    field = field(:integer)

    # act
    value = coerce(field, "42")

    # assert
    assert_equal 42, value
  end

  def test_integer_rejects_text
    # arrange
    field = field(:integer, name: :level)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "abc") }

    # assert
    assert_equal "level must be an integer", error.message
  end

  def test_integer_rejects_decimals
    # arrange
    field = field(:integer)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "4.5") }

    # assert
    assert_match(/must be an integer/, error.message)
  end

  def test_boolean_casts_truthy_values
    # arrange
    field = field(:boolean)

    # act
    values = ["1", "true", true].map { |raw| coerce(field, raw) }

    # assert
    assert_equal [true, true, true], values
  end

  def test_boolean_casts_falsy_values
    # arrange
    field = field(:boolean)

    # act
    values = ["0", "false", false].map { |raw| coerce(field, raw) }

    # assert
    assert_equal [false, false, false], values
  end

  def test_date_parses_iso8601
    # arrange
    field = field(:date)

    # act
    value = coerce(field, "2026-11-21")

    # assert
    assert_equal Date.new(2026, 11, 21), value
  end

  def test_date_rejects_an_invalid_date
    # arrange
    field = field(:date, name: :born_on)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "2026-13-45") }

    # assert
    assert_equal "born_on must be a date", error.message
  end

  def test_date_rejects_a_non_iso_format
    # arrange
    field = field(:date)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "21/11/2026") }

    # assert
    assert_match(/must be a date/, error.message)
  end

  def test_select_accepts_a_declared_choice
    # arrange
    field = field(:select, choices: %w[teacher coordinator])

    # act
    value = coerce(field, "coordinator")

    # assert
    assert_equal "coordinator", value
  end

  def test_select_compares_choices_as_strings
    # arrange
    field = field(:select, choices: [1, 2])

    # act
    value = coerce(field, 2)

    # assert
    assert_equal "2", value
  end

  def test_select_rejects_a_value_outside_the_choices
    # arrange
    field = field(:select, name: :role, choices: %w[teacher coordinator])

    # act
    error = assert_raises(ArgumentError) { coerce(field, "director") }

    # assert
    assert_equal "role is not one of the choices", error.message
  end

  def test_select_choices_lambda_runs_in_the_action
    # arrange
    field = field(:select, choices: -> { [tenant[:slug]] })
    action = Action.new(tenant: { slug: "school_a" })

    # act
    value = coerce(field, "school_a", action)

    # assert
    assert_equal "school_a", value
  end

  def test_select_without_choices_rejects_everything
    # arrange
    field = field(:select)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "x") }

    # assert
    assert_match(/not one of the choices/, error.message)
  end

  def test_record_becomes_the_id
    # arrange
    field = field(:record)

    # act
    value = coerce(field, "7")

    # assert
    assert_equal 7, value
  end

  def test_record_rejects_a_non_id
    # arrange
    field = field(:record, name: :owner)

    # act
    error = assert_raises(ArgumentError) { coerce(field, "seven") }

    # assert
    assert_equal "owner must be an integer", error.message
  end

  def test_blank_values_return_the_default
    # arrange
    field = field(:string, default: "fallback")

    # act
    values = [nil, ""].map { |raw| coerce(field, raw) }

    # assert
    assert_equal %w[fallback fallback], values
  end

  def test_blank_value_without_default_is_nil
    # arrange
    field = field(:string)

    # act
    value = coerce(field, "")

    # assert
    assert_nil value
  end

  def test_default_lambda_runs_in_the_action
    # arrange
    field = field(:string, default: -> { record.nickname })
    action = Action.new(record: create_account(nickname: "Mia"))

    # act
    value = coerce(field, nil, action)

    # assert
    assert_equal "Mia", value
  end

  def test_required_field_missing_is_invalid_in_the_runner
    # arrange
    configure_actions
    account = create_account
    action_class = role_action

    # act
    result = run_action(action_class, record: account, params: {}, snapshot: "any")

    # assert
    assert_equal [:invalid, "role is required"], [result.status, result.message]
  end

  def test_required_field_missing_writes_nothing
    # arrange
    configure_actions
    account = create_account
    action_class = role_action

    # act
    run_action(action_class, record: account, params: {}, snapshot: "any")

    # assert
    assert_equal ["teacher", 0], [account.reload.role, action_events.size]
  end

  def test_prepare_raises_when_a_required_field_is_missing
    # arrange
    action = role_action.new(record: create_account, params: {})

    # act
    error = assert_raises(ArgumentError) { action.prepare! }

    # assert
    assert_equal "role is required", error.message
  end

  def test_optional_field_missing_takes_the_current_value_of_the_record
    # arrange
    action_class = build_action do
      on :accounts
      field :role, :select, choices: %w[teacher coordinator], required: false
    end
    action = action_class.new(record: create_account(role: "teacher"), params: {})

    # act
    action.prepare!

    # assert
    assert_equal "teacher", action.role
  end

  def test_initial_values_take_the_current_value_of_the_attribute_named_like_the_field
    # arrange
    configure_actions
    action = role_action.new(record: create_account(role: "teacher"), params: {})

    # act
    values = action.initial_values(revealed: %w[contact])

    # assert
    assert_equal({ role: "teacher" }, values)
  end

  def test_initial_values_use_the_declared_default_when_the_attribute_is_nil
    # arrange
    configure_actions
    action_class = build_action do
      on :accounts
      field :nickname, :string, default: "Anonymous"
    end
    action = action_class.new(record: create_account(nickname: nil))

    # act
    values = action.initial_values

    # assert
    assert_equal({ nickname: "Anonymous" }, values)
  end

  def test_initial_values_use_the_declared_default_when_the_record_has_no_such_attribute
    # arrange
    action_class = build_action do
      on :accounts
      field :confirmation_note, :string, default: "n/a"
    end
    action = action_class.new(record: create_account)

    # act
    values = action.initial_values

    # assert
    assert_equal({ confirmation_note: "n/a" }, values)
  end

  def test_initial_values_run_a_default_lambda_in_the_action
    # arrange
    action_class = build_action do
      on :accounts
      field :confirmation_note, :string, default: -> { "for #{record.role}" }
    end
    action = action_class.new(record: create_account(role: "teacher"))

    # act
    values = action.initial_values

    # assert
    assert_equal({ confirmation_note: "for teacher" }, values)
  end

  def test_initial_values_are_nil_without_default_and_without_attribute
    # arrange
    action_class = build_action do
      on :accounts
      field :confirmation_note, :string
    end
    action = action_class.new(record: create_account)

    # act
    values = action.initial_values

    # assert
    assert_equal({ confirmation_note: nil }, values)
  end

  def test_initial_values_without_record_use_the_declared_default
    # arrange
    action_class = build_action do
      on :global
      field :note, :string, default: "start"
    end
    action = action_class.new

    # act
    values = action.initial_values

    # assert
    assert_equal({ note: "start" }, values)
  end

  def test_initial_values_cover_every_field
    # arrange
    configure_actions
    action_class = build_action do
      on :accounts
      field :role, :string
      field :level, :integer
      field :extra, :string
    end
    action = action_class.new(record: create_account(role: "teacher", level: 3))

    # act
    values = action.initial_values(revealed: %w[contact])

    # assert
    assert_equal({ role: "teacher", level: 3, extra: nil }, values)
  end

  def test_initial_values_lock_a_field_over_a_masked_column
    # arrange
    configure_actions
    action = role_action.new(record: create_account(role: "teacher"), params: {})

    # act
    values = action.initial_values

    # assert
    assert_same Action::Field::LOCKED, values[:role]
    refute_includes values.values.map(&:to_s), "teacher"
  end

  def test_initial_values_unlock_a_field_when_its_category_is_revealed
    # arrange
    configure_actions
    action = role_action.new(record: create_account(role: "teacher"), params: {})

    # act
    values = action.initial_values(revealed: %w[contact])

    # assert
    assert_equal({ role: "teacher" }, values)
  end

  def test_initial_values_stay_locked_when_another_category_is_revealed
    # arrange
    configure_actions
    action = role_action.new(record: create_account(role: "teacher"), params: {})

    # act
    values = action.initial_values(revealed: %w[free_text])

    # assert
    assert_same Action::Field::LOCKED, values[:role]
  end

  def test_initial_values_lock_nothing_without_a_record
    # arrange
    configure_actions
    action = role_action.new(params: {})

    # act
    values = action.initial_values

    # assert
    refute_same Action::Field::LOCKED, values[:role]
  end

  def test_runner_discards_the_submitted_value_of_a_locked_field
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action

    # act
    snapshot = snapshot_for(action_class, record: account, params: { role: "teacher" })
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: snapshot, revealed: [])

    # assert
    assert_equal [:ok, "teacher"], [result.status, account.reload.role]
  end

  def test_runner_hands_the_current_value_of_a_locked_field_to_the_action
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    seen = []
    action_class = role_action do
      perform { seen << role }
    end

    # act
    snapshot = snapshot_for(action_class, record: account, params: { role: "teacher" })
    result = run_action(action_class, record: account, params: { role: "coordinator" }, snapshot: snapshot, revealed: [])

    # assert
    assert_equal [:ok, ["teacher"]], [result.status, seen]
  end

  def test_runner_accepts_the_submitted_value_when_the_category_is_revealed
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action_class = role_action

    # act
    result = run_action(action_class, record: account, params: { role: "coordinator" }, revealed: %w[contact])

    # assert
    assert_equal [:ok, "coordinator"], [result.status, account.reload.role]
  end

  def test_initial_values_do_not_make_a_required_field_optional
    # arrange
    action = role_action.new(record: create_account(role: "teacher"), params: {})
    action.initial_values

    # act
    error = assert_raises(ArgumentError) { action.prepare! }

    # assert
    assert_equal "role is required", error.message
  end

  def test_invalid_value_is_invalid_in_the_runner_and_writes_nothing
    # arrange
    configure_actions
    account = create_account
    action_class = role_action

    # act
    result = run_action(action_class, record: account, params: { role: "janitor" }, snapshot: "any")

    # assert
    assert_equal [:invalid, "role is not one of the choices", "teacher", 0], [result.status, result.message, account.reload.role, action_events.size]
  end

  def gadget_code_action
    build_action("ChangeCode") do
      on :gadgets
      field :name, :string, required: false
      field :secret_code, :string, required: false
      field :kind, :string, required: false
      perform { record.update!(name: name, secret_code: secret_code, kind: kind) }
    end
  end

  def test_secret_column_stays_locked_even_with_every_category_revealed
    # arrange
    configure_actions
    gadget = Gadget.create!(name: "Torno", kind: "k", secret_code: "SEGREDO-ATUAL")
    action = gadget_code_action.new(record: gadget, params: {})

    # act
    values = action.initial_values(revealed: %w[contact free_text documents])

    # assert
    assert_same Action::Field::LOCKED, values[:secret_code]
    refute_same Action::Field::LOCKED, values[:name]
    refute_includes values.values.map(&:to_s), "SEGREDO-ATUAL"
  end

  def test_resource_hidden_column_stays_locked_even_with_every_category_revealed
    # arrange
    configure_actions
    Class.new(Lucid::Backoffice::Resource) do
      table :gadgets
      hide :kind
    end
    gadget = Gadget.create!(name: "Torno", kind: "oculto-9", secret_code: "x")
    action = gadget_code_action.new(record: gadget, params: {})

    # act
    values = action.initial_values(revealed: %w[contact free_text documents])

    # assert
    assert_same Action::Field::LOCKED, values[:kind]
    refute_same Action::Field::LOCKED, values[:name]
  ensure
    Lucid::Backoffice::Resource.reset!
  end

  def test_runner_keeps_the_current_value_of_a_hidden_column_even_when_revealed
    # arrange
    configure_actions
    gadget = Gadget.create!(name: "Torno", kind: "k", secret_code: "SEGREDO-ATUAL")
    action_class = gadget_code_action

    # act
    snapshot = snapshot_for(action_class, record: gadget, params: { name: "Novo" })
    result = run_action(action_class, record: gadget, params: { name: "Novo", secret_code: "INVADIDO" }, snapshot: snapshot, revealed: %w[contact])

    # assert
    assert_equal [:ok, "Novo", "SEGREDO-ATUAL"], [result.status, gadget.reload.name, gadget.secret_code]
  end

  def test_label_accepts_a_callable_resolved_on_each_read
    # arrange
    counter = 0
    action_class = build_action("Dynamic") { label(-> { "rotulo #{counter += 1}" }) }

    # act
    labels = [action_class.label, action_class.label]

    # assert
    assert_equal ["rotulo 1", "rotulo 2"], labels
  end
end
