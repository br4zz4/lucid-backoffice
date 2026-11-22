module Lucid
  module Backoffice
    # Serves the gem's static CSS and JS and the theme tokens. Public on purpose: it carries no data, so the
    # login page of an app can use it and nothing needs inline styles (CSP friendly).
    class AssetsController < ActionController::Base
      TYPES = { "css" => "text/css", "js" => "text/javascript" }.freeze

      before_action :harden_headers

      def show
        path = Lucid::Backoffice::Engine.root.join("app/assets", params[:name])
        expires_in 1.hour, public: true
        return unless stale?(etag: [Lucid::Backoffice::VERSION, params[:name]], public: true)

        render plain: path.read, content_type: TYPES.fetch(File.extname(params[:name]).delete("."))
      end

      def theme
        expires_in 1.hour, public: true
        return unless stale?(etag: Lucid::Backoffice::Theme.digest, public: true)

        render plain: Lucid::Backoffice::Theme.css, content_type: TYPES.fetch("css")
      end

      private

      def harden_headers
        response.headers["X-Content-Type-Options"] = "nosniff"
      end
    end
  end
end
