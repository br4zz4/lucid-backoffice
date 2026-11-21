module Lucid
  module Backoffice
    class DashboardController < ApplicationController
      def show
        authorize!(:view_dashboard)
        @period = Registry::Period.for(params[:period])
        @cards = Registry.cards.select { |card| allowed?(card.permission) }.map { |card| [card, card.value.call(@period)] }
        @tenants = allowed?(:view_tenant) ? tenancy.tenants : []
      end
    end
  end
end
