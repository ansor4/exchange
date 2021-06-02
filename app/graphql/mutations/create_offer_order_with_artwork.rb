class Mutations::CreateOfferOrderWithArtwork < Mutations::BaseMutation
  null true

  argument :artwork_id, String, 'Artwork Id', required: true
  argument :edition_set_id, String, 'EditionSet Id', required: false
  argument :quantity, Integer, 'Number of items in the line item, default is 1', required: false
  argument :find_active_or_create, Boolean, 'When set to false, we will create a new order. Otherwise if current user has pending/submitted orders on same artwork/edition with same quantity, we will return that', required: false, default_value: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure. If find_active_or_create is not false, it will return existing pending/submitted order for current user if exists, otherwise it will return newly created order',
        null: false

  def resolve(artwork_id:, find_active_or_create:, edition_set_id: nil, quantity: 1)
    order = OrderService.create_with_artwork!(
      buyer_id: context[:current_user][:id],
      buyer_type: Order::USER,
      mode: Order::OFFER,
      artwork_id: artwork_id,
      edition_set_id: edition_set_id,
      quantity: quantity,
      user_agent: context[:user_agent],
      user_ip: context[:user_ip],
      find_active_or_create: find_active_or_create
    )
    {
      order_or_error: { order: order }
    }
  end
end
