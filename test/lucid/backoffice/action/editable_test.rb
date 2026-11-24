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
      config.authorize = ->(_operator, permission, _context) { permission == :run_action }
    end
  end

  def editable_resource(*fields, **options)
    Class.new(Lucid::Backoffice::Resource) do
      table :profiles
      editable(*fields, **options)
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
    assert_equal ["edit_profiles", "profiles", "Edit"], [action.key, action.target, action.label]
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
end
