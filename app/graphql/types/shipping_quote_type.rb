class Types::ShippingQuoteType < Types::BaseObject
  description 'A shipping quote'
  graphql_name 'ShippingQuote'

  field :id, ID, null: false
  field :name, String, null: true
  field :tier, String, null: false
  field :price_cents, Integer, null: false
  field :price_currency, String, null: false
  field :created_at, Types::DateTimeType, null: false
  field :updated_at, Types::DateTimeType, null: false
  field :is_selected, Boolean, null: false

  # rubocop:disable Naming/PredicateName
  def is_selected
    return false unless object.line_item

    object.line_item.selected_shipping_quote_id == object.id
  end
  # rubocop:enable Naming/PredicateName
end
