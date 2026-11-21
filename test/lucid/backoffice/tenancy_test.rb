require "data_helper"

class TenancyAdapterTest < DataTest
  Tenancy = Lucid::Backoffice::Tenancy

  def test_null_has_no_tenants
    # arrange
    adapter = Tenancy::Null.new

    # act
    tenants = adapter.tenants

    # assert
    assert_empty tenants
    refute adapter.multi_tenant?
    assert_nil adapter.find("alfa")
    assert_nil adapter.identifier(:any)
    assert_nil adapter.label(:any)
  end

  def test_null_schema_is_the_current_schema
    # arrange
    adapter = Tenancy::Null.new
    current = connection.current_schema

    # act
    schemas = [adapter.schema_for(nil), adapter.schema_for(:anything), adapter.shared_schema]

    # assert
    assert_equal [current, current, current], schemas
  end

  def test_null_health_is_nil
    # arrange
    adapter = Tenancy::Null.new

    # act
    health = adapter.health(nil)

    # assert
    assert_nil health
  end

  def test_default_adapter_is_null
    # arrange
    configure_minimal

    # act
    adapter = Tenancy.adapter

    # assert
    assert_instance_of Tenancy::Null, adapter
    assert_same adapter, Tenancy.adapter
  end

  def test_none_setting_is_null
    # arrange
    configure_minimal { |config| config.tenancy = :none }

    # act
    adapter = Tenancy.adapter

    # assert
    assert_instance_of Tenancy::Null, adapter
  end

  def test_nil_setting_is_null
    # arrange
    configure_minimal { |config| config.tenancy = nil }

    # act
    adapter = Tenancy.adapter

    # assert
    assert_instance_of Tenancy::Null, adapter
  end

  def test_lucid_tenancy_without_the_require_is_a_configuration_conflict
    # arrange
    configure_minimal { |config| config.tenancy = :lucid_tenancy }
    hidden = Lucid::Backoffice::Adapters.send(:remove_const, :LucidTenancy) if defined?(Lucid::Backoffice::Adapters::LucidTenancy)

    # act
    error = assert_raises(Lucid::Backoffice::Error::ConfigurationConflict) { Tenancy.adapter }
    Lucid::Backoffice::Adapters.const_set(:LucidTenancy, hidden) if hidden

    # assert
    assert_match(/lucid\/backoffice\/adapters\/lucid_tenancy/, error.message)
  end

  def test_custom_object_is_used_as_is
    # arrange
    custom = Object.new
    configure_minimal { |config| config.tenancy = custom }

    # act
    adapter = Tenancy.adapter

    # assert
    assert_same custom, adapter
  end

  def test_reset_drops_the_cached_adapter
    # arrange
    configure_minimal
    first = Tenancy.adapter

    # act
    Tenancy.reset!
    second = Tenancy.adapter

    # assert
    refute_same first, second
  end
end
