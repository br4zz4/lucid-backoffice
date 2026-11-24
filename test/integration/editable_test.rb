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
  PERMISSIONS = { 1 => %i[run_action update_record create_record destroy_record browse view_dashboard view_tenant],
                  2 => %i[browse view_dashboard view_tenant] }.freeze
  DATA = "/backoffice/data".freeze
  CLASSIFICATION = <<~YAML.freeze
    profiles:
      name: contact
      city: public
      secret_code: contact
      age: public
    gadgets:
      name: public
      kind: public
      secret_code: contact
  YAML

  def setup
    super
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Profile.delete_all
    Part.delete_all
    Gadget.delete_all
  end

  def teardown
    Lucid::Backoffice::Action.reset!
    Lucid::Backoffice::Resource.reset!
    Profile.delete_all
    Part.delete_all
    Gadget.delete_all
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

  def grant_contact_reveal
    Lucid::Backoffice::Reveal.create!(operator_type: "PanelOperator", operator_id: 1, tenant_identifier: Lucid::Backoffice::Reveal.tenant_identifier(nil),
                                      category: "contact", reason: REASON, expires_at: 1.hour.from_now)
  end

  def snapshot_value = dom.at_css("input[name=snapshot]")&.[]("value")

  def test_form_only_offers_the_declared_fields
    # arrange
    configure_profiles
    profile = create_profile
    grant_contact_reveal

    # act
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id }, headers: as(1)

    # assert
    assert_response :ok
    assert_equal %w[fields[city] fields[name]], dom.css("form [name^='fields[']").map { |input| input["name"] }.sort
  end

  def test_locked_name_is_masked_and_post_writes_only_the_declared_open_fields_with_event
    # arrange
    configure_profiles
    profile = create_profile
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda" } }, headers: as(1)
    snapshot = snapshot_value
    preview = dom.at_css("section.lb-section").text
    locked = dom.at_css("input#fields_name")

    # act
    post "#{ACTIONS}/edit_profiles", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda", secret_code: "hacked", age: 99 },
                                               snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_equal [MASKED, "disabled", nil], [locked["value"], locked["disabled"], locked["name"]]
    refute_includes preview, "Ana"
    refute_includes preview, "Bia"
    assert_includes preview, "Olinda"
    assert_response :redirect
    assert_equal ["Ana", "Olinda", "s3", 30], profile.reload.then { |p| [p.name, p.city, p.secret_code, p.age] }
    assert_equal REASON, events("backoffice.action.edit_profiles").sole.reason
  end

  def test_revealed_name_shows_the_preview_in_clear_and_post_writes_it_with_event
    # arrange
    configure_profiles
    profile = create_profile
    grant_contact_reveal
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda" } }, headers: as(1)
    snapshot = snapshot_value
    preview = dom.at_css("section.lb-section").text

    # act
    post "#{ACTIONS}/edit_profiles", params: { record_id: profile.id, fields: { name: "Bia", city: "Olinda", secret_code: "hacked", age: 99 },
                                               snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_includes preview, "Ana → Bia"
    assert_includes preview, "Olinda"
    refute_includes preview, MASKED
    assert_response :redirect
    assert_equal ["Bia", "Olinda", "s3", 30], profile.reload.then { |p| [p.name, p.city, p.secret_code, p.age] }
    assert_equal REASON, events("backoffice.action.edit_profiles").sole.reason
  end

  def test_blank_field_keeps_the_current_value_through_the_controller
    # arrange
    configure_profiles
    profile = create_profile
    grant_contact_reveal
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id, fields: { name: "Bia", city: "" } }, headers: as(1)
    snapshot = snapshot_value

    # act
    post "#{ACTIONS}/edit_profiles", params: { record_id: profile.id, fields: { name: "Bia", city: "" }, snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    assert_response :redirect
    assert_equal %w[Bia Recife], profile.reload.then { |p| [p.name, p.city] }
  end

  def configure_gadgets(&block)
    path = write_yaml(CLASSIFICATION)
    configure_panel(permissions: PERMISSIONS) { |config| config.classification_path = path }
    Class.new(Lucid::Backoffice::Resource) do
      table :gadgets
      class_eval(&block)
    end
  end

  def alert_text = dom.at_css(".lb-flash-error")&.text.to_s
  def header_actions = dom.css(".lb-page-actions a").map { |node| node.text.strip }

  def creation_snapshot(fields)
    get "#{ACTIONS}/create_gadgets/new", params: { fields: fields }, headers: as(1)
    snapshot_value
  end

  def test_list_header_offers_new_record_and_the_record_page_does_not
    # arrange
    configure_gadgets { creatable :name, :kind; destroyable }
    gadget = Gadget.create!(name: "Torno")

    # act
    get "#{DATA}/gadgets", headers: as(1)
    on_list = header_actions
    get "#{DATA}/gadgets/#{gadget.id}", headers: as(1)
    on_record = header_actions

    # assert
    assert_equal ["Novo registro"], on_list
    assert_equal ["Excluir registro"], on_record
  end

  def test_new_record_button_is_absent_without_create_record
    # arrange
    configure_gadgets { creatable :name, :kind }

    # act
    get "#{DATA}/gadgets", headers: as(2)

    # assert
    assert_response :ok
    assert_empty header_actions
  end

  def test_creating_redirects_to_the_created_record_and_records_the_event
    # arrange
    configure_gadgets { creatable :name, :kind }
    fields = { name: "Torno", kind: "ferramenta", secret_code: "hacked" }
    snapshot = creation_snapshot(fields)

    # act
    post "#{ACTIONS}/create_gadgets", params: { fields: fields, snapshot: snapshot, reason: REASON }, headers: as(1)

    # assert
    gadget = Gadget.sole
    assert_redirected_to "#{DATA}/gadgets/#{gadget.id}"
    assert_equal ["Torno", "ferramenta", nil], [gadget.name, gadget.kind, gadget.secret_code]
    assert_equal REASON, events("backoffice.action.create_gadgets").sole.reason
  end

  def test_creating_with_invalid_values_shows_the_validation_error_and_writes_nothing
    # arrange
    configure_gadgets { creatable :name, :kind }
    fields = { name: "", kind: "ferramenta" }
    snapshot = creation_snapshot(fields)

    # act
    post "#{ACTIONS}/create_gadgets", params: { fields: fields, snapshot: snapshot, reason: REASON }, headers: as(1)
    follow_redirect! if response.redirect?

    # assert
    assert_equal 0, Gadget.count
    assert_includes alert_text, "Name"
  end

  def test_creating_without_create_record_is_403_on_get_and_post
    # arrange
    configure_gadgets { creatable :name }

    # act
    get "#{ACTIONS}/create_gadgets/new", headers: as(2)
    get_status = response.status
    post "#{ACTIONS}/create_gadgets", params: { fields: { name: "Torno" }, snapshot: "x", reason: REASON }, headers: as(2)

    # assert
    assert_equal 403, get_status
    assert_response :forbidden
    assert_equal 0, Gadget.count
  end

  def test_creating_on_a_table_not_declared_is_404_on_get_and_post
    # arrange
    configure_gadgets { editable :name }

    # act
    get "#{ACTIONS}/create_gadgets/new", headers: as(1)
    get_status = response.status
    post "#{ACTIONS}/create_gadgets", params: { fields: { name: "Torno" }, snapshot: "x", reason: REASON }, headers: as(1)

    # assert
    assert_equal 404, get_status
    assert_response :not_found
    assert_equal 0, Gadget.count
  end

  def test_destroying_asks_for_the_record_id_and_redirects_to_the_list
    # arrange
    configure_gadgets { destroyable }
    gadget = Gadget.create!(name: "Torno")
    get "#{ACTIONS}/destroy_gadgets/new", params: { record_id: gadget.id }, headers: as(1)
    snapshot = snapshot_value
    expected = dom.at_css("input[name=confirmation][data-lb-confirmation]")
    wrong = nil

    # act
    post "#{ACTIONS}/destroy_gadgets", params: { record_id: gadget.id, snapshot: snapshot, reason: REASON, confirmation: "0" }, headers: as(1)
    wrong = Gadget.count
    post "#{ACTIONS}/destroy_gadgets", params: { record_id: gadget.id, snapshot: snapshot, reason: REASON, confirmation: gadget.id.to_s }, headers: as(1)

    # assert
    assert expected
    assert_equal 1, wrong
    assert_redirected_to "#{DATA}/gadgets"
    assert_equal 0, Gadget.count
    assert_equal REASON, events("backoffice.action.destroy_gadgets").sole.reason
  end

  def test_destroying_refused_by_the_model_shows_its_message_and_keeps_the_record
    # arrange
    configure_gadgets { destroyable }
    gadget = Gadget.create!(name: "Torno")
    Part.create!(gadget_id: gadget.id, label: "eixo")
    get "#{ACTIONS}/destroy_gadgets/new", params: { record_id: gadget.id }, headers: as(1)
    snapshot = snapshot_value

    # act
    post "#{ACTIONS}/destroy_gadgets", params: { record_id: gadget.id, snapshot: snapshot, reason: REASON, confirmation: gadget.id.to_s }, headers: as(1)
    follow_redirect! if response.redirect?

    # assert
    assert_equal 1, Gadget.count
    assert_includes alert_text, "Cannot delete record because dependent parts exist"
  end

  def test_destroying_without_destroy_record_is_403
    # arrange
    configure_gadgets { destroyable }
    gadget = Gadget.create!(name: "Torno")

    # act
    get "#{ACTIONS}/destroy_gadgets/new", params: { record_id: gadget.id }, headers: as(2)

    # assert
    assert_response :forbidden
    assert_equal 1, Gadget.count
  end

  def test_editing_without_update_record_is_403
    # arrange
    configure_profiles
    profile = create_profile

    # act
    get "#{ACTIONS}/edit_profiles/new", params: { record_id: profile.id }, headers: as(2)

    # assert
    assert_response :forbidden
  end
end
