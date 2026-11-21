module Lucid
  module Backoffice
    class RecordsController < ApplicationController
      before_action :load_scope

      def tables
        authorize!(:browse, { tenant: current_tenant })
        @tables = Catalog.tables(@schema)
      end

      def index
        authorize!(:browse, { tenant: current_tenant, table: params[:table], model: model })
        PanelActivity.browse(table: params[:table], tenant: current_tenant)
        @page = Records.list(schema: @schema, table: params[:table], filters: params.fetch(:filter, {}).to_unsafe_h, page: params[:page],
                             revealed: revealed, resource: resource)
      end

      def show
        authorize!(:browse, { tenant: current_tenant, table: params[:table], model: model })
        PanelActivity.view(table: params[:table], id: params[:id].to_i, tenant: current_tenant)
        @cells = Records.find(schema: @schema, table: params[:table], id: params[:id], revealed: revealed, resource: resource)
      end

      private

      def load_scope
        Current.tenant_identifier = current_tenant && tenancy.identifier(current_tenant)
        @schema = tenancy.schema_for(current_tenant)
        @reveals = Reveal.active.where(operator_type: current_operator.class.name, operator_id: current_operator.id,
                                       tenant_identifier: Reveal.tenant_identifier(current_tenant))
      end

      def resource
        Resource.for(params[:table])
      end

      def model
        params[:table].to_s.classify.safe_constantize if Catalog.table?(@schema, params[:table])
      end

      def revealed
        Reveal.categories_for(operator: current_operator, tenant: current_tenant)
      end
    end
  end
end
