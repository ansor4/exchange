source 'https://rubygems.org'

ruby File.read('.ruby-version')

gem 'rails', '6.0'

gem 'pg'
gem 'puma', '~> 3.12.2'

gem 'activeadmin'
gem 'artsy-auth'
gem 'artsy-eventservice'
gem 'carmen'
gem 'dalli'
gem 'ddtrace', '>= 0.15.0' # datadog instrumentation
gem 'dogstatsd-ruby', require: 'datadog/statsd' # send metrics to datadog agent
gem 'faraday'
gem 'graphql'
gem 'jwt'
gem 'micromachine'
gem 'money' # Library for dealing with money and currency conversion
# omniauth-artsy version specifier is required since otherwise Bundler will downgrade omniauth-artsy in order to upgrade omniauth-oauth2 and faraday. See https://github.com/artsy/exchange/pull/225#issuecomment-428999929 for more info.
gem 'omniauth-artsy', '~> 0.2.3'
gem 'paper_trail'
gem 'sentry-raven'
gem 'sidekiq', '<6' # for sending emails in the background (<6 necessary for Redis 3 compatibility)
gem 'stripe'
gem 'taxjar-ruby', require: 'taxjar'

group :development, :test do
  gem 'byebug'
  gem 'graphlient'
  gem 'rspec-rails'
  gem 'rubocop'
end

group :development do
  gem 'listen'
end

group :test do
  gem 'capybara'
  gem 'coveralls', require: false
  gem 'danger'
  gem 'fabrication'
  gem 'selenium-webdriver'
  gem 'stripe-ruby-mock', '~> 2.5.8', require: 'stripe_mock'
  gem 'timecop'
  gem 'webmock'
end

gem "artemis", "~> 0.5.2"
