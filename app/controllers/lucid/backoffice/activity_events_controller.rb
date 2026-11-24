module Lucid
  module Backoffice
    class ActivityEventsController < ApplicationController
      PERIODS = { "24h" => 1.day, "7d" => 7.days, "30d" => 30.days }.freeze

      def index
        authorize!(:view_activity, { tenant: current_tenant })
        scope = Activity::Event.order(occurred_at: :desc, id: :desc)
        if current_tenant
          scope = scope.where(tenant_identifier: tenancy.identifier(current_tenant))
        elsif params[:tenant].present?
          scope = scope.where(tenant_identifier: params[:tenant])
        end
        scope = scope.where(actor_type: params[:actor_type]) if params[:actor_type].present?
        scope = scope.where("name LIKE ?", "#{Activity::Event.sanitize_sql_like(params[:name])}%") if params[:name].present?
        scope = scope.where(outcome: params[:outcome]) if params[:outcome].present?
        scope = scope.where("occurred_at >= ?", Time.current - PERIODS.fetch(params[:period], 7.days))
        per = Lucid::Backoffice.configuration.page_size
        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @pages = [(@total / per.to_f).ceil, 1].max
        @events = scope.limit(per).offset((@page - 1) * per).to_a
        @groups = @events.group_by(&:request_id)
      end
    end
  end
end
