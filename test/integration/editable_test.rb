require "action_helper"
require "integration_helper"
require "lucid/case"
require "lucid/backoffice/integrations/lucid_case"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :profiles, force: true do |t|
    t.string :name
    t.string :city
    t.string :secret_code
    t.integer :age
    t.timestamps
  end
end

class Profile < ActiveRecord::Base
end unless defined?(Profile)

class EditableIntegrationTest < PanelTest
  ACTIONS = "/backoffice/actions".freeze
  REASON = "corrigir cadastro 77".freeze
  PERMISSIONS = { 1 => %i[run_action browse view_dashboard view_tenant] }.freeze
  CLASSIFICATION = <<~YAML.freeze
    profiles:
      name: contact
      city: public
      secret_code: contact
      age: public
  YAML

  def setup
    super
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Profile.delete_all
  end

  def teardown
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Profile.delete_all
    super
  end

  def configure_profiles
    path = write_yaml(CLASSIFICATION)
    configure_panel(permissions: PERMISSIONS) { |config| config.classification_path = path }
    Class.new(Lucid::Backoffice::Resource) do
      table :profiles
      editable :name, :city
    end
  end

  def create_profile
    Profile.create!(name: "Ana", city: "Recife", secret_code: "s3", age: 30)
  end

  def snapshot_value = dom.at_css("input[name=snapshot]")&.[]("value")

  def test_form_only_offers_the_declared_fields
    # arrange
    configure_profiles
    profile = create_profile

    # act
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id }, headers: as(1)

    # assert
    assert_response :ok
    assert_equal %w[fields[city] fields[name]], dom.css("form [name^='fields[']").map { |input| input["name"] }.sort
  end

  def test_preview_is_masked_and_post_writes_only_declared_fields_with_event
    # arrange
    configure_profiles
    profile = create_profile
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda" } }, headers: as(1)
    snapshot = snapshot_value
    preview = dom.at_css("section.lb-section").text

    # act
    post "#{ACTIONS}/edit_profiles", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda", secret_code: "hacked", age: 99 },
                                               snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_includes preview, MASKED
    refute_includes preview, "Ana"
    refute_includes preview, "Bia"
    assert_includes preview, "Olinda"
    assert_response :redirect
    assert_equal ["Bia", "Olinda", "s3", 30], profile.reload.then { |p| [p.name, p.city, p.secret_code, p.age] }
    assert_equal REASON, events("backoffice.action.edit_profiles").sole.reason
  end

  def test_blank_field_keeps_the_current_value_through_the_controller
    # arrange
    configure_profiles
    profile = create_profile
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id, fields: { name: "Bia", city: "" } }, headers: as(1)
    snapshot = snapshot_value

    # act
    post "#{ACTIONS}/edit_profiles", params: { record_id: profile.id, fields: { name: "Bia", city: "" }, snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_response :redirect
    assert_equal %w[Bia Recife], profile.reload.then { |p| [p.name, p.city] }
  end
end
