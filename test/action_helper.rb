require "test_helper"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :accounts, force: true do |t|
    t.string :role
    t.string :nickname
    t.integer :level
    t.timestamps
  end
  create_table :gadgets, force: true do |t|
    t.string :name
    t.string :kind
    t.string :secret_code
    t.timestamps
  end
  create_table :parts, force: true do |t|
    t.integer :gadget_id
    t.string :label
  end
end

class Gadget < ActiveRecord::Base
  has_many :parts, dependent: :restrict_with_error
  validates :name, presence: true
end

class Part < ActiveRecord::Base
  belongs_to :gadget
end

class Account < ActiveRecord::Base
  def owner? = role == "owner"
  def last_owner? = owner?
end

class ActionTest < ActivityTest
  Action = Lucid::Backoffice::Action
  Runner = Lucid::Backoffice::Action::Runner
  Operator = Struct.new(:id)
  Failure = Struct.new(:type) do
    def failure? = true
  end
  TenantAdapter = Class.new do
    def identifier(tenant) = tenant.fetch(:slug)
  end

  REASON = "support ticket 1234".freeze
  UNLOCKED_BY_DEFAULT = %w[role name].freeze
  CLASSIFICATION = <<~YAML.freeze
    accounts:
      role: contact
      nickname: public
      level: public
    gadgets:
      name: public
      kind: public
      secret_code: contact
  YAML

  def setup
    super
    Account.delete_all
    Part.delete_all
    Gadget.delete_all
    Lucid::Backoffice::Current.reset
  end

  def configure_actions(permissions: %i[run_action reveal])
    path = write_yaml(CLASSIFICATION)
    configure_minimal do |config|
      config.classification_path = path
      config.authorize = ->(_operator, permission, _context) { permissions.include?(permission) }
    end
  end

  def build_action(name = "ChangeUserRole", &body)
    klass = Class.new(Action)
    klass.define_singleton_method(:name) { name }
    klass.class_eval(&body)
    klass
  end

  def role_action(name = "ChangeUserRole", &extra)
    build_action(name) do
      on :accounts
      field :role, :select, choices: -> { %w[teacher coordinator director] }
      perform { record.update!(role: role) }
      class_eval(&extra) if extra
    end
  end

  def create_account(**attributes)
    Account.create!({ role: "teacher", nickname: "Mia", level: 1 }.merge(attributes))
  end

  def snapshot_for(action_class, record: nil, tenant: nil, params: {})
    action_class.new(record: record, tenant: tenant, params: params).prepare!.build_preview.snapshot
  end

  def run_action(action_class, record: nil, tenant: nil, params: {}, reason: REASON, snapshot: :auto, operator: Operator.new(1), unlocked: UNLOCKED_BY_DEFAULT, **options)
    snapshot = snapshot_for(action_class, record: record, tenant: tenant, params: params) if snapshot == :auto
    Runner.call(action_class, operator: operator, reason: reason, snapshot: snapshot, record: record, tenant: tenant, params: params,
                              unlocked: unlocked, **options)
  end

  def action_events(name = nil)
    scope = Lucid::Backoffice::Activity::Event.order(:id)
    (name ? scope.where(name: name) : scope).to_a
  end
end
