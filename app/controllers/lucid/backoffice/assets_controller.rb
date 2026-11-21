module Lucid
  module Backoffice
    class AssetsController < ActionController::Base
      TYPES = { "css" => "text/css", "js" => "text/javascript" }.freeze

      def show
        path = Lucid::Backoffice::Engine.root.join("app/assets", params[:name])
        expires_in 1.hour, public: true
        render plain: path.read, content_type: TYPES.fetch(File.extname(params[:name]).delete("."))
      end
    end
  end
end
