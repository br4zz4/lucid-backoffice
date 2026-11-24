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
        columns = Records.visible(@schema, params[:table], resource)
        @query, url_ignored = build_query(columns)
        PanelActivity.browse(table: params[:table], tenant: current_tenant, criteria: criteria_names(@query, columns))
        @page = Records.list(schema: @schema, table: params[:table], query: @query, page: params[:page], revealed: revealed, resource: resource)
        @ignored = (@page.ignored_filters + url_ignored).uniq
        @revealed = revealed
        @query_path = query_path
      end

      def query
        authorize!(:browse, { tenant: current_tenant, table: params[:table], model: model })
        Records.visible(@schema, params[:table], resource)
        token = SecureRandom.urlsafe_base64(12)
        criteria = params.fetch(:criteria, {}).permit(:search, :sort, :dir, filters: {}).to_h
        sort, direction = params[:sort_toggle].to_s.split(":", 2)
        criteria.merge!("sort" => sort, "dir" => direction) if sort.present?
        criteria["filters"] = criteria.fetch("filters", {}).merge(params[:filter_column].to_s => params[:filter_value].to_s) if params[:filter_column].present?
        store_query(token, criteria)
        redirect_to index_path(q: token)
      end

      def show
        authorize!(:browse, { tenant: current_tenant, table: params[:table], model: model })
        PanelActivity.view(table: params[:table], id: params[:id].to_i, tenant: current_tenant)
        @cells = Records.find(schema: @schema, table: params[:table], id: params[:id], revealed: revealed, resource: resource)
      end

      private

      MAX_STORED_QUERIES = 20

      def store_query(token, criteria)
        store = (session[:lb_queries] ||= {})
        filters = criteria.fetch("filters", {}).reject { |_name, value| value.to_s.strip.empty? }
        store[token] = { "table" => params[:table], "tenant" => Current.tenant_identifier.to_s, "filters" => filters,
                         "search" => criteria["search"].to_s, "sort" => criteria["sort"].to_s, "dir" => criteria["dir"].to_s }
        store.delete(store.keys.first) while store.size > MAX_STORED_QUERIES
      end

      def stored_query
        entry = session.dig(:lb_queries, params[:q].to_s)
        return nil unless entry && entry["table"] == params[:table] && entry["tenant"] == Current.tenant_identifier.to_s

        Records::Query.new(filters: entry["filters"], search: entry["search"], sort: entry["sort"], dir: entry["dir"])
      end

      def build_query(columns)
        stored = stored_query
        url = Records::Query.new(filters: params.fetch(:filter, {}).to_unsafe_h, sort: params[:sort], dir: params[:dir])
        safe, ignored = url_criteria(url, columns)
        query = Records::Query.new(filters: (stored&.filters || {}).merge(safe[:filters]), search: stored&.search,
                                   sort: safe[:sort] || stored&.sort, dir: safe[:sort] ? url.dir : stored&.dir)
        [query, ignored]
      end

      def url_criteria(url, columns)
        public_names = columns.select { |column| column.category == Classification::PUBLIC }.map(&:name)
        filters = url.filters.slice(*public_names)
        ignored = url.filters.keys - filters.keys
        sort = url.sort if public_names.include?(url.sort)
        ignored << url.sort if url.sort && sort.nil?
        [{ filters: filters, sort: sort }, ignored]
      end

      def criteria_names(query, columns)
        searched = query.search ? query.searchable_columns(columns, revealed, declared: resource&.searchable.presence).map(&:name) : []
        query.filters.keys + [query.sort].compact + searched
      end

      helper_method :sort_header

      def sort_header(column)
        return column.name unless Records::Query.usable?(column, @revealed)

        direction = @query.sort == column.name && @query.dir == "asc" ? "desc" : "asc"
        mark = @query.sort == column.name ? (@query.dir == "asc" ? " ▲" : " ▼") : ""
        return view_context.link_to("#{column.name}#{mark}", index_path(q: params[:q], sort: column.name, dir: direction)) if column.category == Classification::PUBLIC

        view_context.button_tag("#{column.name}#{mark}", type: "submit", form: "lb-sort-form", name: "sort_toggle", value: "#{column.name}:#{direction}", class: "lb-sort")
      end

      def index_path(**options)
        current_tenant ? tenant_table_path(tenant_id: tenancy.identifier(current_tenant), table: params[:table], **options) : table_path(table: params[:table], **options)
      end

      def query_path
        current_tenant ? tenant_table_query_path(tenant_id: tenancy.identifier(current_tenant), table: params[:table]) : table_query_path(table: params[:table])
      end

      def load_scope
        Current.tenant_identifier = current_tenant && tenancy.identifier(current_tenant)
        @schema = tenancy.schema_for(current_tenant)
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
