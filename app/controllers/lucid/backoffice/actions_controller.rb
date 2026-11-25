module Lucid
  module Backoffice
    # Preview and execution of corrective actions. Nothing is written without a reason, the permission of
    # the action and a preview whose state still matches.
    class ActionsController < ApplicationController
      before_action :load_action

      def new
        show_form
      end

      def preview
        show_form
      end

      def unlock
        authorize!(@action_class.permission, context)
        field = params[:field].to_s
        tenancy.with(current_tenant) do
          record = find_record
          action = @action_class.new(record: record, tenant: current_tenant)
          raise Records::NotFound, "no such field" unless action.unlock_mode(field)
          raise Error::Forbidden, "not allowed to unlock" unless action.unlock_mode(field) == :read && allowed?(:reveal, { tenant: current_tenant, category: action.unlock_category(field) })

          Activity.record(name: "backoffice.field.unlock", subjects: [{ "type" => "Table", "name" => @action_class.target.to_s, "id" => record.id }],
                          payload: { column: field, action: @action_class.key.to_s })
          response.headers["Cache-Control"] = "no-store"
          render json: { value: record.public_send(field) }
        end
      end

      def create
        authorize!(@action_class.permission, context)
        return redirect_to(replay_path, alert: I18n.t("lucid_backoffice.action_replayed")) unless nonce_valid?
        result = tenancy.with(current_tenant) do
          Action::Runner.call(@action_class, operator: current_operator, reason: params[:reason], snapshot: params[:snapshot].to_s,
                              record: find_record, tenant: current_tenant, params: field_params, confirmation: params[:confirmation],
                              unlocked: unlocked_params, submit: params[:submit])
        end
        if result.ok?
          return render_secret(result) if result.secret.present?

          notice = result.message.presence || I18n.t("lucid_backoffice.action_done")
          return redirect_to(result.redirect, allow_other_host: true, notice: notice) if result.redirect.present?

          landing = landing_path(result.value)
          return redirect_to(landing, notice: notice) if landing

          return redirect_back(fallback_location: lb_routes.root_path, notice: notice)
        end

        flash.now[:alert] = I18n.t("lucid_backoffice.action_#{result.status}", message: result.message, default: result.message.to_s)
        render_form
      end

      private

      def show_form
        authorize!(@action_class.permission, context)
        tenancy.with(current_tenant) do
          @record = find_record
          @action = @action_class.new(record: @record, tenant: current_tenant, params: field_params)
          @initial = @action.initial_values
          prepare_preview
        end
        render :new
      end

      def load_action
        @action_class = Action.for_key(params[:action_key]) || raise(Records::NotFound, "no such action")
      end

      def context
        { tenant: current_tenant, action: @action_class.key }
      end

      def unlocked_params
        Array(params[:unlocked]).map(&:to_s)
      end

      def field_params
        params.fetch(:fields, {}).permit(*@action_class.fields.keys).to_h
      end

      MAX_NONCES = 20

      def issue_nonce
        store = (session[:lb_action_nonces] ||= {})
        nonce = SecureRandom.urlsafe_base64(16)
        store[nonce] = @action_class.key
        store.delete(store.keys.first) while store.size > MAX_NONCES
        nonce
      end

      def nonce_valid?
        return true unless @action_class.secret

        store = session[:lb_action_nonces] || {}
        store.delete(params[:nonce].to_s) == @action_class.key
      end

      def replay_path
        lb_routes.new_action_path(action_key: @action_class.key, record_id: params[:record_id], tenant_id: params[:tenant_id])
      end

      def render_secret(result)
        response.headers["Cache-Control"] = "no-store"
        @secret = result.secret
        @notice = result.message.presence || I18n.t("lucid_backoffice.action_done")
        @continue = result.redirect.presence || landing_path(result.value) || lb_routes.root_path
        render :secret
      end

      def landing_path(value)
        table = @action_class.target
        case @action_class.landing
        when :record
          id = created_id(value)
          return nil unless id

          current_tenant ? lb_routes.tenant_record_path(tenant_id: tenancy.identifier(current_tenant), table: table, id: id) : lb_routes.record_path(table: table, id: id)
        when :list
          current_tenant ? lb_routes.tenant_table_path(tenant_id: tenancy.identifier(current_tenant), table: table) : lb_routes.table_path(table: table)
        end
      end

      def created_id(value)
        record = value.respond_to?(:id) && !value.is_a?(Hash) ? value : (value[:resource] if value.respond_to?(:[]))
        record.respond_to?(:id) ? record.id : nil
      rescue NameError, KeyError, TypeError
        nil
      end

      def revealed_categories
        @revealed_categories ||= Reveal.categories_for(operator: current_operator, tenant: current_tenant)
      end

      def find_record
        return nil unless @action_class.target && !@action_class.collection? && !%w[tenant global].include?(@action_class.target)

        model = @action_class.target.to_s.classify.safe_constantize
        raise Records::NotFound, "no such record" unless model && model < ActiveRecord::Base

        model.find(params[:record_id])
      end

      def prepare_preview
        @unlocked = @action.accepted_unlocks(field_params, unlocked: unlocked_params, operator: current_operator)
        @locked = @action.locked_names - @unlocked
        @reason = @action.unavailable_reason
        return if @reason
        return unless params.key?(:fields) || @action_class.fields.empty?

        submitted = @action.with_locked_current(field_params, unlocked: unlocked_params, operator: current_operator).symbolize_keys.compact_blank
        values = @initial.reject { |_name, value| value.equal?(Action::Field::LOCKED) }.merge(submitted)
        @action = @action_class.new(record: @record, tenant: current_tenant, params: values).prepare!
        preview = @action.build_preview
        @snapshot = preview.snapshot
        @nonce = issue_nonce if @action_class.secret
        @changes = preview.masked(revealed: revealed_categories)
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
