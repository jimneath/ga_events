require 'rack/utils'

module GaEvents
  class Middleware
    def initialize(app)
      @app = app
    end
    def call(env)
      # Handle events stored in flash
      # Parts borrowed from Rails:
      # https://github.com/rails/rails/blob/v3.2.14/actionpack/lib/action_dispatch/middleware/flash.rb
      flash = env['rack.session'] && env['rack.session']['flash']
      
      # Fix for Rails 4
      flash &&= flash['flashes'] if Rails::VERSION::MAJOR > 3

      GaEvents::List.init(flash && flash['ga_events'])
      status, headers, body = @app.call(env)

      if GaEvents::List.present?
        response = Rack::Response.new([], status, headers)
        request = Rack::Request.new(env)
        
        # Can outgrow, headers might get too big
        serialized = GaEvents::List.to_s
        if request.xhr?
          # AJAX request
          response.headers['X-GA-Events'] = serialized

        elsif response.redirection?
          # 30x/redirect? Then add event list to flash to survive the redirect.
          flash_hash = env[ActionDispatch::Flash::KEY]
          flash_hash ||= ActionDispatch::Flash::FlashHash.new
          flash_hash['ga_events'] = serialized
          env[ActionDispatch::Flash::KEY] = flash_hash

        elsif is_html?(status, headers)
          body = body.each.to_a.join if body.respond_to?(:each)
          body = body.gsub('</body>', %Q{<div data-ga-events="#{serialized}"></div></body>})
        end
        
        response.write(fragment)
        response.finish
      else
        [status, headers, body]
      end
    end

    private

    # Taken from:
    # https://github.com/rack/rack-contrib/blob/master/lib/rack/contrib/jsonp.rb
    def is_html?(status, headers)
      !Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(status.to_i) &&
        headers.key?('Content-Type') &&
        headers['Content-Type'].include?('text/html')
    end
  end
end
