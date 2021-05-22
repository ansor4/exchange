class Mutations::CreateOrderWithArtwork < Mutations::BaseMutation
  null true

  argument :artwork_id, String, 'Artwork Id', required: true
  argument :edition_set_id, String, 'EditionSet Id', required: false
  argument :quantity, Integer, 'Number of items in the line item', required: false

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(artwork_id:, edition_set_id: nil, quantity: 1)
    order = OrderService.create_with_artwork!(
      buyer_id: context[:current_user][:id],
      buyer_type: Order::USER,
      mode: Order::BUY,
      artwork_id: artwork_id,
      edition_set_id: edition_set_id,
      quantity: quantity,
      user_agent: context[:user_agent],
      user_ip: context[:user_ip]
    )
    {
      order_or_error: { order: order }
    }
  end
end
