class Types::LineItemType < Types::BaseObject
  description 'A Line Item'
  graphql_name 'LineItem'

  field :id, ID, null: false
  field :internalID, ID, null: false, method: :id, camelize: false
  field :price_cents, Integer, null: false, deprecation_reason: 'switch to use listPriceCents'
  field :list_price_cents, Integer, null: false
  field :shipping_total_cents, Integer, null: true
  field :artwork_id, String, null: false
  field :artwork_version_id, String, null: false
  field :edition_set_id, String, null: true
  field :quantity, Integer, null: false
  field :commission_fee_cents, Integer, null: true, seller_only: true
  field :created_at, Types::DateTimeType, null: false
  field :updated_at, Types::DateTimeType, null: false
  field :fulfillments, Types::FulfillmentType.connection_type, null: true
  field :order, Types::OrderInterface, null: false
  field :shipping_quote_options, Types::ShippingQuoteType.connection_type, null: true

  def price_cents
    object.list_price_cents
  end

  def shipping_quote_options
    return unless object.order.fulfillment_type == Order::SHIP_ARTA && object.shipping_quote_requests.present?

    # TODO: add a limit and order by most recent/relevant and optimize this
    object.shipping_quote_requests.order(:created_at).last.shipping_quotes
  end
end
