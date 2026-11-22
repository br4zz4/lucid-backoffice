require "dummy_app"
require "integration_helper"
require "lucid/backoffice/test_helpers"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :pupils, force: true do |t|
    t.string :name
    t.date :birthdate
    t.string :status
    t.string :cpf
    t.integer :age
    t.timestamps
  end
end

class MaskedRecord < ActiveRecord::Base
  self.abstract_class = true
  include Lucid::Backoffice::ImpersonationMask
end

class Student < MaskedRecord
  self.table_name = "pupils"
end

class UnmaskedStudent < MaskedRecord
  self.table_name = "pupils"
  self.lucid_backoffice_unmasked = true
end

class BackofficeReveal < MaskedRecord
  self.table_name = "lucid_backoffice_reveals"
end

class GuardedApplicationController < ActionController::Base
  include Lucid::Backoffice::ImpersonationGuard

  def login
    session[:signed_in_user] = 1
    render plain: "logged"
  end

  def status
    render plain: "impersonating=#{Lucid::Backoffice.impersonating?} actor=#{Lucid::Backoffice::Current.actor.inspect}"
  end

  def page
    render inline: "<%= lucid_backoffice_impersonation_banner %><p>page</p>", layout: false
  end

  def mutate
    Widget.create!(label: "written")
    render plain: "written"
  end
end

module GuardedApp
  class StudentsController < GuardedApplicationController
    def index = render(plain: "index")
    def show = render(plain: "show")
    def show2 = render(plain: "show2")
  end
end

class Reports2Controller < GuardedApplicationController
  def index = render(plain: "reports")
end

unless Rails.application.routes.named_routes.key?(:guarded_app_page)
  Rails.application.routes.disable_clear_and_finalize = true
  Rails.application.routes.draw do
    post "/app/login", to: "guarded_application#login"
    get "/app/status", to: "guarded_application#status"
    get "/app/page", to: "guarded_application#page", as: :guarded_app_page
    get "/app/students", to: "guarded_app/students#index"
    get "/app/students/:id", to: "guarded_app/students#show"
    get "/app/digits", to: "guarded_app/students#show2"
    get "/app/reports2", to: "reports2#index"
    post "/app/students", to: "guarded_application#mutate"
    post "/app/allowed", to: "guarded_application#mutate"
    patch "/app/students/:id", to: "guarded_application#mutate"
    put "/app/students/:id", to: "guarded_application#mutate"
    delete "/app/students/:id", to: "guarded_application#mutate"
  end
end

module ImpersonationAppSupport
  CLASSIFICATION = "pupils:\n  name: contact\n  birthdate: minors\n  status: public\n  cpf: documents\n".freeze

  def reset_app_data
    reset_impersonation_data
    Widget.delete_all
    Student.delete_all
    Lucid::Backoffice::Reveal.delete_all
  end

  def configure_classification
    Lucid::Backoffice.configuration.classification_path = write_yaml(CLASSIFICATION)
    Lucid::Backoffice::Classification.reset!
  end

  def enter_impersonation(operator)
    _, url = start_impersonation(operator)
    get url
  end

  def page_views
    impersonation_events("backoffice.impersonation.page_view")
  end

  def freeze_now
    travel_to Time.zone.now.change(usec: 0)
  end
end
