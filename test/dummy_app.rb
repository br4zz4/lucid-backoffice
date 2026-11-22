require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "lucid/backoffice"

module DummyApp
  class Application < Rails::Application
    config.root = File.expand_path("dummy", __dir__)
    config.secret_key_base = "dummy-secret-key-base-for-tests"
    config.eager_load = false
    config.enable_reloading = false
    config.logger = ActiveSupport::Logger.new(nil)
    config.log_level = :debug
    config.hosts.clear
    config.action_dispatch.show_exceptions = :none
    config.consider_all_requests_local = true
    config.action_controller.allow_forgery_protection = false
    config.session_store :cookie_store, key: "_dummy_session"
  end
end

unless DummyApp::Application.initialized?
  DummyApp::Application.initialize!
  module Dummy
    class OrganizationsController < Lucid::Backoffice::ApplicationController
      def index
        authorize!(:manage_organizations)
        Lucid::Backoffice::Activity.record(name: "dummy.organizations.index")
        render inline: "<h1>Escolas</h1>", layout: true
      end
    end
  end
  DummyApp::Application.routes.draw do
    mount Lucid::Backoffice::Engine => "/backoffice"
    get "/backoffice-app/organizations", to: "dummy/organizations#index"
    get "lucid_backoffice/impersonation/enter", to: "lucid/backoffice/impersonations#enter"
    delete "lucid_backoffice/impersonation", to: "lucid/backoffice/impersonations#destroy"
  end
end
