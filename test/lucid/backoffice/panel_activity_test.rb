require "data_helper"

class PanelActivityTest < DataTest
  PanelActivity = Lucid::Backoffice::PanelActivity
  Records = Lucid::Backoffice::Records
  Operator = Struct.new(:id)

  def setup
    super
    Lucid::Backoffice::Current.reset
    Lucid::Backoffice::Activity::Event.unscoped.delete_all
  end

  def teardown
    Lucid::Backoffice::Current.reset
    super
  end

  def events(name)
    Lucid::Backoffice::Activity::Event.where(name: name).order(:id).to_a
  end

  def test_browse_records_the_event_with_the_table_subject
    # arrange
    configure_minimal

    # act
    PanelActivity.browse(table: "students")

    # assert
    event = events("backoffice.browse").sole
    assert_equal [{ "type" => "Table", "name" => "students" }], event.subjects
  end

  def test_view_records_the_event_with_the_table_and_id_subject
    # arrange
    configure_minimal

    # act
    PanelActivity.view(table: "students", id: 42)

    # assert
    event = events("backoffice.view").sole
    assert_equal [{ "type" => "Table", "name" => "students", "id" => 42 }], event.subjects
  end

  def test_events_carry_no_column_values
    # arrange
    configure_minimal
    insert_student(cpf: "999.888.777-66", email: "secret@example.com")
    id = connection.select_value("SELECT id FROM public.students").to_i

    # act
    PanelActivity.browse(table: "students")
    PanelActivity.view(table: "students", id: id)

    # assert
    stored = Lucid::Backoffice::Activity::Event.order(:id).map { |event| event.attributes.values.join(" ") }.join(" ")
    refute_match(/999\.888|secret@example|Maria/, stored)
    assert_equal({}, events("backoffice.view").sole.payload)
    assert_equal [], events("backoffice.view").sole.changed_fields
  end

  def test_the_tenant_is_taken_from_the_argument_when_there_is_none_current
    # arrange
    configure_minimal

    # act
    PanelActivity.browse(table: "students", tenant: "school_a")

    # assert
    assert_equal "school_a", events("backoffice.browse").sole.tenant_identifier
  end

  def test_the_actor_comes_from_current
    # arrange
    configure_minimal
    Lucid::Backoffice::Current.actor = Operator.new(9)

    # act
    PanelActivity.browse(table: "students")

    # assert
    event = events("backoffice.browse").sole
    assert_equal "PanelActivityTest::Operator", event.actor_type
    assert_equal 9, event.actor_id
  end

  def test_a_failed_record_propagates_the_error
    # arrange
    configure_minimal
    boom = Class.new(StandardError)

    # act and assert
    Lucid::Backoffice::Activity.stub(:record, ->(**) { raise boom, "audit down" }) do
      assert_raises(boom) { PanelActivity.browse(table: "students") }
      assert_raises(boom) { PanelActivity.view(table: "students", id: 1) }
    end
  end

  def test_a_failed_record_stops_the_flow_before_any_select_on_the_data_table
    # arrange
    configure_minimal
    insert_student
    boom = Class.new(StandardError)
    reached = false

    # act
    statements = capture_sql do
      Lucid::Backoffice::Activity.stub(:record, ->(**) { raise boom, "audit down" }) do
        assert_raises(boom) do
          PanelActivity.browse(table: "students")
          reached = true
          Records.list(schema: "public", table: "students")
        end
      end
    end

    # assert
    refute reached
    assert_empty statements.grep(/FROM "?public"?\."?students"?/i)
  end

  def test_when_the_record_succeeds_the_flow_reads_the_rows
    # arrange
    configure_minimal
    insert_student

    # act
    statements = capture_sql do
      PanelActivity.browse(table: "students")
      Records.list(schema: "public", table: "students")
    end

    # assert
    assert_equal 1, events("backoffice.browse").size
    refute_empty statements.grep(/FROM "?public"?\."?students"?/i)
  end
end
