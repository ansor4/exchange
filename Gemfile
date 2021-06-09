source 'https://rubygems.org'

ruby File.read('.ruby-version')

gem 'rails', '6.1.3.1'

gem 'pg'
gem 'puma'

gem 'activeadmin'
gem 'artemis'
gem 'artsy-auth'
gem 'artsy-eventservice'
gem 'carmen'
gem 'dalli'
gem 'ddtrace' # datadog instrumentation
gem 'dogstatsd-ruby', require: 'datadog/statsd' # send metrics to datadog agent
gem 'faraday'
gem 'graphql'
gem 'graphql-page_cursors'
gem 'graphql-rails_logger'
gem 'jwt'
gem 'micromachine'
gem 'money' # Library for dealing with money and currency conversion
# omniauth-artsy version specifier is required since otherwise Bundler will downgrade omniauth-artsy in order to upgrade omniauth-oauth2 and faraday. See https://github.com/artsy/exchange/pull/225#issuecomment-428999929 for more info.
gem 'omniauth-artsy', '~> 0.2.3'
gem 'paper_trail'
gem 'sentry-raven'
gem 'sidekiq', '<6' # for sending emails in the background (<6 necessary for Redis 3 compatibility)
gem 'stripe'
gem 'strong_migrations' # automate detection of potentially dangerous migrations
gem 'taxjar-ruby', require: 'taxjar'
gem 'tzinfo-data' # overrides system TZ database

group :development, :test do
  gem 'byebug'
  gem 'graphlient'
  gem 'guard-rspec', require: false
  gem 'rspec-rails'
  gem 'rubocop-rails', require: false
  gem 'sassc-rails'
end

group :development do
  gem 'listen'
  gem 'rails-erd'
end

group :test do
  gem 'capybara'
  gem 'danger'
  gem 'fabrication'
  gem 'selenium-webdriver'
  gem 'simplecov', require: false
  gem 'stripe-ruby-mock', require: 'stripe_mock'
  gem 'timecop'
  gem 'webmock'
end
