require "action_helper"
require "lucid/case"
require "lucid/backoffice/integrations/lucid_case"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :profiles, force: true do |t|
    t.string :name
    t.string :city
    t.string :secret_code
    t.integer :age
    t.boolean :active
    t.date :born_on
    t.text :bio
    t.timestamps
  end
end

class Profile < ActiveRecord::Base
end

module Profiles
  class Update < Lucid::Case::Command
    attributes :record, :name, :city

    fail_if :frozen_name?

    def call!
      record.update!(name: name, city: city)
      success(profile: record)
    end

    private

    def frozen_name? = record.name == "Frozen"
  end
end

class EditableTest < ActionTest
  PROFILES_CLASSIFICATION = <<~YAML.freeze
    profiles:
      name: contact
      city: public
      secret_code: contact
      age: public
      active: public
      born_on: public
      bio: free_text
  YAML

  def setup
    super
    Profile.delete_all
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    I18n.backend.send(:init_translations)
    @observers_before = Lucid::Case.configuration.events.observers.dup
    Lucid::Backoffice::Integrations::LucidCase.install!
  end

  def teardown
    Lucid::Case.configuration.events.observers.replace(@observers_before)
    Lucid::Case.configuration.events.recording = :disabled
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    I18n.backend.reload!
    super
  end

  def configure_profiles
    path = write_yaml(PROFILES_CLASSIFICATION)
    configure_minimal do |config|
      config.classification_path = path
      config.authorize = ->(_operator, permission, _context) { %i[run_action update_record].include?(permission) }
    end
  end

  def editable_resource(*fields, **options, &block)
    Class.new(Lucid::Backoffice::Resource) do
      table :profiles
      editable(*fields, **options, &block)
    end
  end

  def create_profile(**attributes)
    Profile.create!({ name: "Ana", city: "Recife", secret_code: "s3", age: 30, active: false, born_on: Date.new(2000, 1, 2), bio: "hi" }.merge(attributes))
  end

  def test_editable_generates_the_edit_action_on_the_table
    # arrange
    configure_profiles

    # act
    resource = editable_resource(:name, :city)
    action = resource.editable_action

    # assert
    assert_equal ["edit_profiles", "profiles", I18n.t("lucid_backoffice.edit")], [action.key, action.target, action.label]
    assert_equal %i[name city], action.fields.keys
  end

  def test_action_is_found_by_key_and_by_target
    # arrange
    configure_profiles
    resource = editable_resource(:name, :city)

    # act
    by_key = Lucid::Backoffice::Action.for_key("edit_profiles")
    by_target = Lucid::Backoffice::Action.for_target(:profiles)

    # assert
    assert_same resource.editable_action, by_key
    assert_equal [resource.editable_action], by_target
  end

  def test_reset_clears_the_generated_action
    # arrange
    configure_profiles
    editable_resource(:name)

    # act
    Lucid::Backoffice::Action.reset!

    # assert
    assert_nil Lucid::Backoffice::Action.for_key("edit_profiles")
    assert_empty Lucid::Backoffice::Action.for_target(:profiles)
  end

  def test_fields_are_not_required_and_types_come_from_the_schema
    # arrange
    configure_profiles

    # act
    fields = editable_resource(:name, :age, :active, :born_on, :bio).editable_action.fields

    # assert
    assert_equal %i[string integer boolean date text], fields.values.map(&:type)
    assert_equal [false] * 5, fields.values.map(&:required)
  end

  def test_editing_writes_only_the_declared_fields
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name, :city).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia", city: "Olinda", secret_code: "hacked" })

    # assert
    assert_equal :ok, result.status
    assert_equal %w[Bia Olinda s3], profile.reload.then { |p| [p.name, p.city, p.secret_code] }
  end

  def test_empty_value_keeps_the_current_one
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name, :city).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia", city: "" })

    # assert
    assert_equal :ok, result.status
    assert_equal %w[Bia Recife], profile.reload.then { |p| [p.name, p.city] }
  end

  def test_typed_values_are_coerced_and_written
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:age, :active, :born_on, :bio).editable_action

    # act
    result = run_action(action, record: profile, params: { age: "41", active: "1", born_on: "2001-02-03", bio: "novo" },
                        revealed: %w[contact free_text])

    # assert
    assert_equal :ok, result.status
    assert_equal [41, true, Date.new(2001, 2, 3), "novo"], profile.reload.then { |p| [p.age, p.active, p.born_on, p.bio] }
  end

  def test_invalid_typed_value_is_refused
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:age).editable_action

    # act
    result = run_action(action, record: profile, params: { age: "abc" }, snapshot: "x")

    # assert
    assert_equal [:invalid, "age must be an integer"], [result.status, result.message]
    assert_equal 30, profile.reload.age
  end

  def test_preview_shows_before_and_after_masked_by_the_category
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name, :city).editable_action
    preview = action.new(record: profile, params: { name: "Bia", city: "Olinda" }).prepare!.build_preview

    # act
    masked = preview.masked.to_h { |change| [change.label.split.last, [change.before, change.after]] }

    # assert
    assert_equal [Lucid::Backoffice::Mask.call(value: "Ana", category: "contact", column_type: :string, revealed: false)] * 2,
                 [masked["name"][0], masked["name"][0]]
    refute_includes masked["name"].join, "Bia"
    assert_equal %w[Recife Olinda], masked["city"]
  end

  def test_event_is_recorded_with_the_reason
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name).editable_action

    # act
    run_action(action, record: profile, params: { name: "Bia" })

    # assert
    event = action_events("backoffice.action.edit_profiles").sole
    assert_equal ["ok", REASON], [event.outcome, event.reason]
  end

  def test_reason_is_required
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia" }, reason: "x")

    # assert
    assert_equal :invalid, result.status
    assert_equal "Ana", profile.reload.name
    assert_empty action_events
  end

  def test_with_command_calls_the_command_and_emits_both_events
    # arrange
    configure_profiles
    profile = create_profile
    action = editable_resource(:name, :city, with: Profiles::Update).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia", city: "Olinda" })

    # assert
    assert_equal :ok, result.status
    assert_equal %w[Bia Olinda], profile.reload.then { |p| [p.name, p.city] }
    assert_equal ["backoffice.action.edit_profiles", "profiles.update"], action_events.map(&:name).sort
  end

  def test_with_command_guard_blocks_the_write
    # arrange
    configure_profiles
    profile = create_profile(name: "Frozen")
    I18n.backend.store_translations(:en, profiles: { update: { frozen_name: "Name is frozen" } })
    action = editable_resource(:name, :city, with: Profiles::Update).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia", city: "Olinda" })

    # assert
    assert_equal [:failed, "Name is frozen"], [result.status, result.message]
    assert_equal %w[Frozen Recife], profile.reload.then { |p| [p.name, p.city] }
    assert_equal "frozen_name", action_events("backoffice.action.edit_profiles").sole.outcome
  end

  def configure_records(permissions: %i[run_action create_record destroy_record])
    path = write_yaml(ActionTest::CLASSIFICATION)
    configure_minimal do |config|
      config.classification_path = path
      config.authorize = ->(_operator, permission, _context) { permissions.include?(permission) }
    end
  end

  def gadget_resource(&block)
    Class.new(Lucid::Backoffice::Resource) do
      table :gadgets
      class_eval(&block)
    end
  end

  def test_creatable_generates_the_collection_action
    # arrange
    configure_records

    # act
    action = gadget_resource { creatable :name, :kind }.creatable_action

    # assert
    assert_equal ["create_gadgets", "gadgets", I18n.t("lucid_backoffice.new_record"), :create_record, :record, true], [action.key, action.target, action.label, action.permission, action.landing, action.collection?]
    assert_equal %i[name kind], action.fields.keys
    assert_same action, Lucid::Backoffice::Action.for_key("create_gadgets")
  end

  def test_creating_writes_the_declared_fields_and_records_the_event
    # arrange
    configure_records
    action = gadget_resource { creatable :name, :kind }.creatable_action

    # act
    result = run_action(action, params: { name: "Torno", kind: "ferramenta", secret_code: "hacked" })

    # assert
    gadget = Gadget.sole
    assert_equal :ok, result.status
    assert_equal ["Torno", "ferramenta", nil], [gadget.name, gadget.kind, gadget.secret_code]
    assert_equal gadget, result.value
    assert_equal REASON, action_events("backoffice.action.create_gadgets").sole.reason
  end

  def test_creating_preview_lists_the_values_to_be_created
    # arrange
    configure_records
    action = gadget_resource { creatable :name, :kind }.creatable_action

    # act
    listing = action.new(params: { name: "Torno", kind: "ferramenta" }).prepare!.build_preview.listings.sole

    # assert
    assert_equal [I18n.t("lucid_backoffice.new_record"), ["name: Torno", "kind: ferramenta"]], [listing.title, listing.items]
  end

  def test_creating_with_invalid_values_fails_with_the_validation_message_and_writes_nothing
    # arrange
    configure_records
    action = gadget_resource { creatable :name, :kind }.creatable_action

    # act
    result = run_action(action, params: { name: "", kind: "ferramenta" })

    # assert
    assert_equal :failed, result.status
    assert_includes result.message, "Name"
    assert_equal 0, Gadget.count
  end

  def test_creating_without_the_permission_is_forbidden
    # arrange
    configure_records(permissions: %i[run_action update_record destroy_record])
    action = gadget_resource { creatable :name }.creatable_action

    # act
    result = run_action(action, params: { name: "Torno" })

    # assert
    assert_equal :forbidden, result.status
    assert_equal 0, Gadget.count
  end

  def test_creating_with_command_calls_the_command_and_emits_both_events
    # arrange
    configure_records
    command = Class.new(Lucid::Case::Command) do
      def self.name = "Gadgets::Create"
      attributes :name, :kind

      def call!
        success(resource: Gadget.create!(name: name, kind: kind))
      end
    end
    action = gadget_resource { creatable :name, :kind, with: command }.creatable_action

    # act
    result = run_action(action, params: { name: "Torno", kind: "x" })

    # assert
    assert_equal :ok, result.status
    assert_equal "Torno", Gadget.sole.name
    assert_equal ["backoffice.action.create_gadgets", "gadgets.create"], action_events.map(&:name).sort
  end

  def test_destroyable_generates_the_high_danger_record_action
    # arrange
    configure_records

    # act
    action = gadget_resource { destroyable }.destroyable_action

    # assert
    assert_equal ["destroy_gadgets", "gadgets", I18n.t("lucid_backoffice.destroy_record"), :destroy_record, :high, :list, false],
                 [action.key, action.target, action.label, action.permission, action.danger, action.landing, action.collection?]
  end

  def test_destroying_removes_the_record_and_records_the_event
    # arrange
    configure_records
    gadget = Gadget.create!(name: "Torno")
    action = gadget_resource { destroyable }.destroyable_action

    # act
    result = run_action(action, record: gadget, confirmation: gadget.id.to_s)

    # assert
    assert_equal :ok, result.status
    assert_equal 0, Gadget.count
    assert_equal REASON, action_events("backoffice.action.destroy_gadgets").sole.reason
  end

  def test_destroying_requires_the_confirmation
    # arrange
    configure_records
    gadget = Gadget.create!(name: "Torno")
    action = gadget_resource { destroyable }.destroyable_action

    # act
    result = run_action(action, record: gadget, confirmation: "0")

    # assert
    assert_equal :invalid, result.status
    assert_equal 1, Gadget.count
  end

  def test_destroying_refused_by_the_model_fails_with_its_message_and_keeps_the_record
    # arrange
    configure_records
    gadget = Gadget.create!(name: "Torno")
    Part.create!(gadget_id: gadget.id, label: "eixo")
    action = gadget_resource { destroyable }.destroyable_action

    # act
    result = run_action(action, record: gadget, confirmation: gadget.id.to_s)

    # assert
    assert_equal :failed, result.status
    assert_includes result.message, "Cannot delete record because dependent parts exist"
    assert_equal 1, Gadget.count
  end

  def test_destroying_without_the_permission_is_forbidden
    # arrange
    configure_records(permissions: %i[run_action update_record create_record])
    gadget = Gadget.create!(name: "Torno")
    action = gadget_resource { destroyable }.destroyable_action

    # act
    result = run_action(action, record: gadget, confirmation: gadget.id.to_s)

    # assert
    assert_equal :forbidden, result.status
    assert_equal 1, Gadget.count
  end

  def test_editing_without_update_record_is_forbidden
    # arrange
    configure_records(permissions: %i[run_action])
    profile = create_profile
    action = editable_resource(:name).editable_action

    # act
    result = run_action(action, record: profile, params: { name: "Bia" })

    # assert
    assert_equal :forbidden, result.status
    assert_equal "Ana", profile.reload.name
  end

  def test_creatable_refuses_a_hidden_or_secret_column
    # arrange
    configure_records
    hidden = Class.new(Lucid::Backoffice::Resource) do
      table :gadgets
      hide :kind
    end

    # act
    hidden_error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { hidden.creatable :name, :kind }
    secret_error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { gadget_resource { creatable :secret_code } }

    # assert
    assert_includes hidden_error.message, ":kind"
    assert_includes secret_error.message, ":secret_code"
  end

  def test_creatable_block_overrides_the_label_and_the_field_type_and_choices
    # arrange
    configure_records

    # act
    action = gadget_resource do
      creatable :name, :kind do
        label "Cadastrar equipamento"
        field :kind, :select, choices: -> { %w[ferramenta peca] }, default: "peca", required: true
      end
    end.creatable_action
    kind = action.fields[:kind]

    # assert
    assert_equal "Cadastrar equipamento", action.label
    assert_equal [:select, "peca", true, %w[ferramenta peca]], [kind.type, kind.default, kind.required, kind.choices.call]
    assert_equal %i[name kind], action.fields.keys
  end

  def test_creatable_block_adds_a_submit_and_keeps_the_generated_defaults
    # arrange
    configure_records

    # act
    action = gadget_resource do
      creatable :name, :kind do
        submit :screen, label: "Criar"
        submit :email, label: "Criar e avisar", if: -> { email_available? }
      end
    end.creatable_action

    # assert
    assert_equal %i[screen email], action.submits.map { |option| option[:key] }
    assert_equal [:create_record, :record, true], [action.permission, action.landing, action.collection?]
  end

  def test_creatable_block_runs_after_the_defaults_so_it_can_override_the_permission
    # arrange
    configure_records

    # act
    action = gadget_resource { creatable(:name) { permission :run_action } }.creatable_action

    # assert
    assert_equal :run_action, action.permission
  end

  def test_creatable_with_a_submit_runs_the_chosen_option
    # arrange
    configure_records
    action = gadget_resource { creatable(:name) { submit :screen, label: "Criar" } }.creatable_action

    # act
    result = run_action(action, params: { name: "Torno" }, submit: "screen")

    # assert
    assert_equal [:ok, ["Torno"]], [result.status, Gadget.pluck(:name)]
  end

  def test_creatable_without_a_block_keeps_the_defaults
    # arrange
    configure_records

    # act
    action = gadget_resource { creatable :name, :kind }.creatable_action

    # assert
    assert_equal [I18n.t("lucid_backoffice.new_record"), []], [action.label, action.submits]
  end

  def test_editable_block_overrides_the_label_and_the_field
    # arrange
    configure_profiles

    # act
    action = editable_resource(:name, :age) do
      label "Corrigir cadastro"
      field :age, :string, default: "18"
      submit :email, label: "Salvar e avisar"
    end.editable_action

    # assert
    assert_equal "Corrigir cadastro", action.label
    assert_equal [:string, "18"], [action.fields[:age].type, action.fields[:age].default]
    assert_equal [:email], action.submits.map { |option| option[:key] }
    assert_equal :update_record, action.permission
  end

  def test_destroyable_block_overrides_the_label_and_adds_a_submit
    # arrange
    configure_records

    # act
    action = gadget_resource do
      destroyable do
        label "Remover equipamento"
        submit :screen, label: "Remover"
      end
    end.destroyable_action

    # assert
    assert_equal ["Remover equipamento", %i[screen], :high, :list], [action.label, action.submits.map { |option| option[:key] }, action.danger, action.landing]
  end

  def test_destroyable_block_does_not_leak_into_other_resources
    # arrange
    configure_records
    gadget_resource { destroyable { label "Remover equipamento" } }

    # act
    other = Class.new(Lucid::Backoffice::Resource) do
      table :profiles
      destroyable
    end.destroyable_action

    # assert
    assert_equal I18n.t("lucid_backoffice.destroy_record"), other.label
  end

  def labels_in(locale)
    I18n.with_locale(locale) do
      [editable_resource(:name).editable_action.label,
       gadget_resource { creatable :name }.creatable_action.label,
       gadget_resource { destroyable }.destroyable_action.label]
    end
  end

  def test_generated_action_labels_follow_the_english_locale
    # arrange
    configure_records
    configure_profiles

    # act
    labels = labels_in(:en)

    # assert
    assert_equal ["Edit", "New record", "Delete record"], labels
  end

  def test_generated_action_labels_follow_the_portuguese_locale
    # arrange
    configure_records
    configure_profiles

    # act
    labels = labels_in(:"pt-BR")

    # assert
    assert_equal ["Editar", "Novo registro", "Excluir registro"], labels
  end

  def test_editable_refuses_a_hidden_or_secret_column
    # arrange
    configure_profiles
    hidden = Class.new(Lucid::Backoffice::Resource) do
      table :profiles
      hide :city
    end

    # act
    hidden_error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { hidden.editable :name, :city }
    secret_error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { editable_resource(:secret_code) }

    # assert
    assert_includes hidden_error.message, ":city"
    assert_includes secret_error.message, ":secret_code"
  end

  def test_reject_hidden_also_refuses_a_column_classified_as_secret
    # arrange
    path = write_yaml("profiles:\n  name: secret\n  city: public\n")
    configure_minimal do |config|
      config.categories = %w[public unclassified contact secret]
      config.secret_columns = /\Anever_matches\z/
      config.classification_path = path
    end

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { editable_resource(:name) }

    # assert
    assert_includes error.message, ":name"
  end
end
