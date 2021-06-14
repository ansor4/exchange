# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

# buyer_id is test user with e-mail "test@artsymail.com". The test user is available on production.
order = Order.create(state: 'pending', payment_method: 'credit card', currency_code: 'USD', mode: 'buy', buyer_id: '55539bfd7261692b13530100', items_total_cents: 30000)
# Artwork of partner "Commerce Test Partner". It is available on production so it will be copied over to staging each week.
line_item = LineItem.create(artwork_id: '5f8f0426eb44c100104053ff', artwork_version_id: '5fb2e1fbae05620012675854', order: order, list_price_cents: 3000)
order.update!(items_total_cents: line_item.total_list_price_cents)
