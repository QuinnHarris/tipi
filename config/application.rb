require File.expand_path('../boot', __FILE__)

#require 'rails/all' # Don't use ActiveRecord
require "action_controller/railtie"
# require "active_record/railtie"
require "action_mailer/railtie"
require "rails/test_unit/railtie"
require "sprockets/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Tipi
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Sequel Config
    # Allowed options: :sql, :ruby.
    # Dump in SQL to capture stored proceedures and triggers 
    config.sequel.schema_format = :sql

    # Whether to dump the schema after successful migrations.
    # Defaults to false in production and test, true otherwise.
    #config.sequel.schema_dump = true

    # These override corresponding settings from the database config.
    #config.sequel.max_connections = 16
    #config.sequel.search_path = %w(mine public)

    # Configure whether database's rake tasks will be loaded or not
    # Defaults to true
    #config.sequel.load_database_tasks = false
    config.assets.paths << Rails.root.join("app", "assets", "fonts")
    config.autoload_paths << File::join(Rails.root, 'lib')

    config.sequel.after_connect = proc do
      Sequel::Model.db.extension :pg_array
      Sequel.extension :pg_array_ops
      Sequel::Model.plugin :timestamps
    end
  end
end
