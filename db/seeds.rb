# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

# buyer_id is test user with e-mail "test@artsymail.com". The test user is available on production.
order = Order.create(state: 'pending', payment_method: 'credit card', currency_code: 'USD', mode: 'offer', buyer_id: '55539bfd7261692b13530100')
# "Test artwork" of "Commerce Test Partner". It is available on production so it will be copied over to staging each week.
LineItem.create(artwork_id: '60a675b08287e200135a4784', artwork_version_id: '60c27e0cf448330013d340a5', order: order)
