require "integration_helper"

class ActivityIntegrationTest < PanelTest
  Event = Lucid::Backoffice::Activity::Event

  def setup
    super
    configure_panel(permissions: { 1 => %i[browse view_activity reveal view_dashboard], 2 => %i[browse] })
  end

  def create_event(**attributes)
    Event.create!({ name: "widget.created", actor_type: "System", occurred_at: Time.current }.merge(attributes))
  end

  def rows
    dom.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
  end

  def test_browsing_a_table_records_browse_event_with_operator_and_table
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(1)
    event = events("backoffice.browse").sole

    # assert
    assert_equal [{ "type" => "Table", "name" => "students" }], event.subjects
    assert_equal ["PanelOperator", 1], [event.actor_type, event.actor_id]
    assert_not_nil event.request_id
    refute_leaks event.to_json
  end

  def test_viewing_a_record_records_view_event_with_id
    # arrange
    insert_student

    # act
    get "/backoffice/data/students/1", headers: as(1)
    event = events("backoffice.view").sole

    # assert
    assert_equal [{ "type" => "Table", "name" => "students", "id" => 1 }], event.subjects
    refute_leaks event.to_json
  end

  def test_tenant_browse_records_the_tenant
    # arrange
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[browse view_tenant] }, tenancy: FakeTenancy.new)

    # act
    get "/backoffice/tenants/alfa/data/students", headers: as(1)

    # assert
    assert_equal "alfa", events("backoffice.browse").sole.tenant_identifier
  end

  def test_denied_browse_records_nothing
    # arrange
    insert_student

    # act
    get "/backoffice/data/students", headers: as(3)

    # assert
    assert_empty events
  end

  def test_event_write_failure_refuses_the_data
    # arrange
    insert_student
    failing = ->(*) { raise ActiveRecord::StatementInvalid, "events table unavailable" }

    # act
    statements = capture_sql do
      Event.stub(:create!, failing) do
        assert_raises(ActiveRecord::StatementInvalid) { get "/backoffice/data/students", headers: as(1) }
      end
    end

    # assert
    assert_empty statements.grep(/FROM "public"."students"/)
  end

  def test_event_write_failure_refuses_the_record_detail
    # arrange
    insert_student
    failing = ->(*) { raise ActiveRecord::StatementInvalid, "events table unavailable" }

    # act
    statements = capture_sql do
      Event.stub(:create!, failing) { assert_raises(ActiveRecord::StatementInvalid) { get "/backoffice/data/students/1", headers: as(1) } }
    end

    # assert
    assert_empty statements.grep(/FROM "public"."students"/)
  end

  def test_activity_requires_view_activity_permission
    # arrange
    path = "/backoffice/activity"

    # act
    get path, headers: as(2)

    # assert
    assert_response :forbidden
  end

  def test_activity_lists_most_recent_first
    # arrange
    create_event(name: "old.event", occurred_at: 3.hours.ago)
    create_event(name: "new.event", occurred_at: 1.hour.ago)

    # act
    get "/backoffice/activity", headers: as(1)

    # assert
    assert_equal %w[new.event old.event], rows.map { |row| row[1] }
  end

  def test_activity_paginates
    # arrange
    60.times { |index| create_event(name: "event.n#{index}", occurred_at: (index + 1).minutes.ago) }

    # act
    get "/backoffice/activity", headers: as(1)
    first = rows.map { |row| row[1] }
    pages = dom.css("nav.lb-pager a").map { |a| a["href"] }
    get "/backoffice/activity", params: { page: 3 }, headers: as(1)
    last = rows.map { |row| row[1] }

    # assert
    assert_equal 25, first.size
    assert_equal "event.n0", first.first
    assert_equal ["/backoffice/activity?page=2", "/backoffice/activity?page=3"], pages
    assert_equal 10, last.size
    assert_equal "event.n59", last.last
  end

  def test_activity_filters_by_name_prefix
    # arrange
    create_event(name: "backoffice.browse")
    create_event(name: "purchases.register")

    # act
    get "/backoffice/activity", params: { name: "backoffice" }, headers: as(1)

    # assert
    assert_equal ["backoffice.browse"], rows.map { |row| row[1] }
  end

  def test_activity_name_filter_treats_wildcards_literally
    # arrange
    create_event(name: "purchases.register")

    # act
    get "/backoffice/activity", params: { name: "%" }, headers: as(1)

    # assert
    assert_empty rows
  end

  def test_activity_filters_by_outcome
    # arrange
    create_event(name: "a.ok", outcome: "ok")
    create_event(name: "b.failed", outcome: "last_owner")

    # act
    get "/backoffice/activity", params: { outcome: "last_owner" }, headers: as(1)

    # assert
    assert_equal ["b.failed"], rows.map { |row| row[1] }
  end

  def test_activity_filters_by_tenant
    # arrange
    create_event(name: "a.alfa", tenant_identifier: "alfa")
    create_event(name: "b.beta", tenant_identifier: "beta")

    # act
    get "/backoffice/activity", params: { tenant: "beta" }, headers: as(1)

    # assert
    assert_equal ["b.beta"], rows.map { |row| row[1] }
  end

  def configure_tenant_activity
    create_tenant_schemas
    configure_panel(permissions: { 1 => %i[view_activity view_tenant], 2 => %i[view_tenant browse] }, tenancy: FakeTenancy.new)
  end

  def test_tenant_activity_lists_only_that_tenants_events
    # arrange
    configure_tenant_activity
    create_event(name: "a.alfa", tenant_identifier: "alfa")
    create_event(name: "b.beta", tenant_identifier: "beta")
    create_event(name: "c.shared")

    # act
    get "/backoffice/tenants/alfa/activity", headers: as(1)

    # assert
    assert_response :ok
    assert_equal ["a.alfa"], rows.map { |row| row[1] }
  end

  def test_tenant_activity_ignores_the_tenant_param
    # arrange
    configure_tenant_activity
    create_event(name: "a.alfa", tenant_identifier: "alfa")
    create_event(name: "b.beta", tenant_identifier: "beta")

    # act
    get "/backoffice/tenants/alfa/activity", params: { tenant: "beta" }, headers: as(1)

    # assert
    assert_equal ["a.alfa"], rows.map { |row| row[1] }
  end

  def test_tenant_activity_still_applies_the_other_filters
    # arrange
    configure_tenant_activity
    create_event(name: "backoffice.browse", tenant_identifier: "alfa")
    create_event(name: "purchases.register", tenant_identifier: "alfa")
    create_event(name: "backoffice.view", tenant_identifier: "beta")

    # act
    get "/backoffice/tenants/alfa/activity", params: { name: "backoffice" }, headers: as(1)

    # assert
    assert_equal ["backoffice.browse"], rows.map { |row| row[1] }
  end

  def test_tenant_activity_hides_the_tenant_filter_field
    # arrange
    configure_tenant_activity

    # act
    get "/backoffice/tenants/alfa/activity", headers: as(1)
    inside_tenant = dom.css("form [name=tenant]").size
    get "/backoffice/activity", headers: as(1)

    # assert
    assert_equal 0, inside_tenant
    assert_equal 1, dom.css("form [name=tenant]").size
  end

  def test_tenant_activity_requires_view_activity
    # arrange
    configure_tenant_activity

    # act
    get "/backoffice/tenants/alfa/activity", headers: as(2)

    # assert
    assert_response :forbidden
  end

  def test_tenant_activity_for_an_unknown_tenant_is_not_found
    # arrange
    configure_tenant_activity

    # act
    get "/backoffice/tenants/zeta/activity", headers: as(1)

    # assert
    assert_response :not_found
  end

  def test_activity_filters_by_actor
    # arrange
    create_event(name: "a.user", actor_type: "User", actor_id: 5)
    create_event(name: "b.system", actor_type: "System")

    # act
    get "/backoffice/activity", params: { actor_type: "User" }, headers: as(1)

    # assert
    assert_equal ["a.user"], rows.map { |row| row[1] }
    assert_includes rows.first[2], "User #5"
  end

  def test_activity_filters_by_period
    # arrange
    create_event(name: "recent", occurred_at: 2.hours.ago)
    create_event(name: "stale", occurred_at: 3.days.ago)

    # act
    get "/backoffice/activity", params: { period: "24h" }, headers: as(1)
    day = rows.map { |row| row[1] }
    get "/backoffice/activity", headers: as(1)

    # assert
    assert_equal ["recent"], day
    assert_equal %w[recent stale], rows.map { |row| row[1] }
  end

  def test_activity_groups_events_by_request_id
    # arrange
    create_event(name: "e1", request_id: "req-a", occurred_at: 1.minute.ago)
    create_event(name: "e2", request_id: "req-b", occurred_at: 2.minutes.ago)
    create_event(name: "e3", request_id: "req-a", occurred_at: 3.minutes.ago)

    # act
    get "/backoffice/activity", headers: as(1)
    grouped = dom.css("tbody tr").map { |tr| [tr.css("td")[1].text.strip, tr["class"].to_s] }

    # assert
    assert_equal [["e1", "lb-grouped"], ["e3", "lb-grouped"], ["e2", ""]], grouped
  end

  def test_activity_shows_subjects_and_reason_without_values
    # arrange
    insert_student
    get "/backoffice/data/students/1", headers: as(1)
    post "/backoffice/reveals", params: { category: "contact", reason: "investigar chamado 123" }, headers: as(1)

    # act
    get "/backoffice/activity", headers: as(1)
    text = response.body

    # assert
    assert_includes text, "backoffice.view"
    assert_includes text, "Table students 1"
    assert_includes text, "investigar chamado 123"
    refute_leaks text
  end

  def test_activity_screen_is_escaped
    # arrange
    create_event(name: "<script>alert(1)</script>")

    # act
    get "/backoffice/activity", headers: as(1)

    # assert
    refute_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;"
  end

  def test_app_screen_activity_carries_actor_and_request_from_context
    # arrange
    configure_panel(permissions: { 1 => %i[manage_organizations] })

    # act
    get "/backoffice-app/organizations", headers: as(1)
    event = events("dummy.organizations.index").sole

    # assert
    assert_equal ["PanelOperator", 1], [event.actor_type, event.actor_id]
    assert_not_nil event.request_id
  end
end
