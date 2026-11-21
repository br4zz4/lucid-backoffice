Lucid::Backoffice::Engine.routes.draw do
  root "dashboard#show"

  get "assets/:name", to: "assets#show", as: :lb_asset, constraints: { name: /lucid_backoffice\.(css|js)/ }, format: false
  get "activity", to: "activity_events#index", as: :activity
  resources :reveals, only: %i[create destroy]

  scope "tenants/:tenant_id", constraints: { tenant_id: %r{[^/]+} } do
    get "/", to: "tenants#show", as: :tenant
    get "data", to: "records#tables", as: :tenant_data
    get "data/:table", to: "records#index", as: :tenant_table
    get "data/:table/:id", to: "records#show", as: :tenant_record
  end

  get "data", to: "records#tables", as: :data
  get "data/:table", to: "records#index", as: :table
  get "data/:table/:id", to: "records#show", as: :record
end
