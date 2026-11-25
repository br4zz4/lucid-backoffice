require "action_helper"

class ActionPreviewTest < ActionTest
  def preview
    Action::Preview.new
  end

  def test_change_reads_the_current_value_as_before
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    preview = preview()

    # act
    preview.change(account, :role, to: "coordinator")

    # assert
    change = preview.changes.first
    assert_equal ["teacher", "coordinator"], [change.before, change.after]
  end

  def test_change_labels_the_record_and_attribute
    # arrange
    configure_actions
    account = create_account
    preview = preview()

    # act
    preview.change(account, :role, to: "coordinator")

    # assert
    assert_equal "Account ##{account.id} role", preview.changes.first.label
  end

  def test_change_takes_the_category_of_the_column
    # arrange
    configure_actions
    account = create_account
    preview = preview()

    # act
    preview.change(account, :role, to: "coordinator")
    preview.change(account, :level, to: 2)
    preview.change(account, :id, to: 9)

    # assert
    assert_equal %w[contact public public], preview.changes.map(&:category)
  end

  def test_unclassified_column_has_the_unclassified_category
    # arrange
    configure_minimal
    account = create_account
    preview = preview()

    # act
    preview.change(account, :role, to: "coordinator")

    # assert
    assert_equal "unclassified", preview.changes.first.category
  end

  def test_list_stores_title_and_items
    # arrange
    preview = preview()

    # act
    preview.list("Versions", %w[v1 v2])

    # assert
    listing = preview.listings.first
    assert_equal ["Versions", %w[v1 v2]], [listing.title, listing.items]
  end

  def test_list_wraps_a_single_item
    # arrange
    preview = preview()

    # act
    preview.list("Versions", "v1")

    # assert
    assert_equal ["v1"], preview.listings.first.items
  end

  def test_masked_hides_both_values_of_a_classified_column
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    change = preview.masked.first

    # assert
    assert_equal [Lucid::Backoffice::Mask::TEXT, Lucid::Backoffice::Mask::TEXT], [change.before, change.after]
  end

  def test_masked_never_leaks_the_raw_values
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    masked = preview.masked

    # assert
    refute_match(/teacher|coordinator/, masked.map(&:to_h).inspect)
  end

  def test_masked_shows_values_when_the_category_is_revealed
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    change = preview.masked(revealed: ["contact"]).first

    # assert
    assert_equal %w[teacher coordinator], [change.before, change.after]
  end

  def test_masked_flags_only_revealed_non_public_changes
    # arrange
    configure_actions
    preview = preview()
    account = create_account(role: "teacher", level: 1)
    preview.change(account, :role, to: "coordinator")
    preview.change(account, :level, to: 2)

    # act
    changes = preview.masked(revealed: ["contact"])

    # assert
    assert_equal [true, false], changes.map(&:revealed)
  end

  def test_masked_does_not_flag_a_category_that_was_not_revealed
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    flags = [preview.masked.first.revealed, preview.masked(revealed: ["financial"]).first.revealed]

    # assert
    assert_equal [false, false], flags
  end

  def test_change_is_created_as_not_revealed
    # arrange
    configure_actions
    preview = preview()

    # act
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # assert
    assert_equal false, preview.changes.first.revealed
  end

  def test_masked_ignores_a_reveal_of_another_category
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    change = preview.masked(revealed: ["financial"]).first

    # assert
    assert_equal [Lucid::Backoffice::Mask::TEXT, Lucid::Backoffice::Mask::TEXT], [change.before, change.after]
  end

  def test_masked_passes_public_columns_through
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(level: 1), :level, to: 2)

    # act
    change = preview.masked.first

    # assert
    assert_equal [1, 2], [change.before, change.after]
  end

  def test_masked_hides_numbers_and_dates_by_their_type
    # arrange
    configure_minimal
    preview = preview()
    account = create_account(level: 3)
    preview.change(account, :level, to: 4)
    preview.change(account, :nickname, to: Date.new(2026, 1, 1))

    # act
    changes = preview.masked

    # assert
    assert_equal [[Lucid::Backoffice::Mask::NUMBER, Lucid::Backoffice::Mask::NUMBER], [Lucid::Backoffice::Mask::TEXT, Lucid::Backoffice::Mask::TIME]],
                 changes.map { |change| [change.before, change.after] }
  end

  def test_masked_does_not_change_the_raw_preview
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    preview.masked

    # assert
    assert_equal %w[teacher coordinator], [preview.changes.first.before, preview.changes.first.after]
  end

  def test_snapshot_is_stable_for_the_same_state
    # arrange
    configure_actions
    account = create_account
    first = preview()
    second = preview()
    first.change(account, :role, to: "coordinator")
    second.change(account, :role, to: "coordinator")

    # act
    snapshots = [first.snapshot, second.snapshot]

    # assert
    assert_equal snapshots.first, snapshots.last
  end

  def test_snapshot_ignores_the_target_value
    # arrange
    configure_actions
    account = create_account
    first = preview()
    second = preview()
    first.change(account, :role, to: "coordinator")
    second.change(account, :role, to: "director")

    # act
    snapshots = [first.snapshot, second.snapshot]

    # assert
    assert_equal snapshots.first, snapshots.last
  end

  def test_snapshot_changes_when_the_value_read_changes
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    before = preview()
    before.change(account, :role, to: "coordinator")
    account.update!(role: "director")
    after = preview()
    after.change(account, :role, to: "coordinator")

    # act
    snapshots = [before.snapshot, after.snapshot]

    # assert
    refute_equal snapshots.first, snapshots.last
  end

  def test_snapshot_changes_when_a_listing_changes
    # arrange
    first = preview()
    second = preview()
    first.list("Versions", %w[v1])
    second.list("Versions", %w[v1 v2])

    # act
    snapshots = [first.snapshot, second.snapshot]

    # assert
    refute_equal snapshots.first, snapshots.last
  end

  def test_snapshot_is_a_sha256_digest_without_the_raw_values
    # arrange
    configure_actions
    preview = preview()
    preview.change(create_account(role: "teacher"), :role, to: "coordinator")

    # act
    snapshot = preview.snapshot

    # assert
    assert_match(/\A\h{64}\z/, snapshot)
  end

  def test_default_preview_shows_the_fields_named_like_attributes
    # arrange
    configure_actions
    account = create_account(role: "teacher")
    action = role_action.new(record: account, params: { role: "coordinator" }).prepare!

    # act
    change = action.build_preview.changes.first

    # assert
    assert_equal ["Account ##{account.id} role", "teacher", "coordinator"], [change.label, change.before, change.after]
  end

  def test_default_preview_skips_fields_that_are_not_attributes
    # arrange
    configure_actions
    action_class = build_action do
      on :accounts
      field :confirmation_note, :string
    end
    action = action_class.new(record: create_account, params: { confirmation_note: "x" }).prepare!

    # act
    changes = action.build_preview.changes

    # assert
    assert_empty changes
  end

  def test_default_preview_is_masked_by_the_category_of_the_column
    # arrange
    configure_actions
    action = role_action.new(record: create_account(role: "teacher"), params: { role: "coordinator" }).prepare!

    # act
    change = action.build_preview.masked.first

    # assert
    assert_equal [Lucid::Backoffice::Mask::TEXT, Lucid::Backoffice::Mask::TEXT], [change.before, change.after]
  end

  def test_custom_preview_defines_the_lines_and_the_snapshot
    # arrange
    configure_actions
    owner = create_account(role: "teacher")
    action_class = build_action do
      on :accounts
      field :role, :select, choices: %w[owner]
      preview do |p|
        p.change(record, :role, to: "owner")
        p.list "Versions", %w[v1 v2]
      end
    end
    action = action_class.new(record: owner, params: { role: "owner" }).prepare!

    # act
    preview = action.build_preview

    # assert
    expected = preview()
    expected.change(owner, :role, to: "owner")
    expected.list("Versions", %w[v1 v2])
    assert_equal [1, ["Versions"], expected.snapshot], [preview.changes.size, preview.listings.map(&:title), preview.snapshot]
  end

  def test_custom_preview_replaces_the_default_one
    # arrange
    configure_actions
    action_class = build_action do
      on :accounts
      field :role, :select, choices: %w[owner]
      preview { |p| p.list "Only a list", %w[x] }
    end
    action = action_class.new(record: create_account, params: { role: "owner" }).prepare!

    # act
    preview = action.build_preview

    # assert
    assert_equal [0, 1], [preview.changes.size, preview.listings.size]
  end

  def test_custom_preview_can_change_another_record
    # arrange
    configure_actions
    other = create_account(role: "teacher")
    action_class = build_action do
      on :accounts
      preview { |p| p.change(params[:new_owner], :role, to: "owner") }
    end
    action = action_class.new(record: create_account, params: { new_owner: other })

    # act
    change = action.build_preview.changes.first

    # assert
    assert_equal ["Account ##{other.id} role", "teacher", "owner"], [change.label, change.before, change.after]
  end

  def test_custom_preview_snapshot_is_the_state_read
    # arrange
    configure_actions
    other = create_account(role: "teacher")
    action_class = build_action do
      on :accounts
      preview { |p| p.change(params[:new_owner], :role, to: "owner") }
    end
    build = -> { action_class.new(record: create_account, params: { new_owner: Account.find(other.id) }).build_preview.snapshot }
    first = build.call
    other.update!(role: "coordinator")

    # act
    second = build.call

    # assert
    refute_equal first, second
  end
end
