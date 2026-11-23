module Lucid
  module Backoffice
    # Preview and execution of corrective actions. Nothing is written without a reason, the permission of
    # the action and a preview whose state still matches.
    class ActionsController < ApplicationController
      before_action :load_action

      def new
        authorize!(@action_class.permission, context)
        tenancy.with(current_tenant) do
          @record = find_record
          @action = @action_class.new(record: @record, tenant: current_tenant, params: field_params)
          @initial = @action.initial_values
          prepare_preview
        end
      end

      def create
        authorize!(@action_class.permission, context)
        result = tenancy.with(current_tenant) do
          Action::Runner.call(@action_class, operator: current_operator, reason: params[:reason], snapshot: params[:snapshot].to_s,
                              record: find_record, tenant: current_tenant, params: field_params, confirmation: params[:confirmation])
        end
        if result.ok?
          notice = result.message.presence || I18n.t("lucid_backoffice.action_done")
          return redirect_to(result.redirect, allow_other_host: true, notice: notice) if result.redirect.present?

          return redirect_back(fallback_location: lb_routes.root_path, notice: notice)
        end

        flash.now[:alert] = I18n.t("lucid_backoffice.action_#{result.status}", message: result.message, default: result.message.to_s)
        render_form
      end

      private

      def load_action
        @action_class = Action.for_key(params[:action_key]) || raise(Records::NotFound, "no such action")
      end

      def context
        { tenant: current_tenant, action: @action_class.key }
      end

      def field_params
        params.fetch(:fields, {}).permit(*@action_class.fields.keys).to_h
      end

      def find_record
        return nil unless @action_class.target && !%w[tenant global].include?(@action_class.target)

        model = @action_class.target.to_s.classify.safe_constantize
        raise Records::NotFound, "no such record" unless model && model < ActiveRecord::Base

        model.find(params[:record_id])
      end

      def prepare_preview
        @reason = @action.unavailable_reason
        return if @reason
        return unless params.key?(:fields) || @action_class.fields.empty?

        values = @initial.merge(field_params.symbolize_keys.compact_blank)
        @action = @action_class.new(record: @record, tenant: current_tenant, params: values).prepare!
        preview = @action.build_preview
        @snapshot = preview.snapshot
        @changes = preview.masked(revealed: Reveal.categories_for(operator: current_operator, tenant: current_tenant))
        @listings = preview.listings
      rescue ArgumentError => e
        @invalid = e.message
      end

      def render_form
        tenancy.with(current_tenant) do
          @record = find_record
          @action = @action_class.new(record: @record, tenant: current_tenant, params: field_params)
          @initial = @action.initial_values
          prepare_preview
        end
        render :new, status: :unprocessable_entity
      end
    end
  end
end
