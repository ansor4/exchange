class Mutations::AddInitialOfferToOrder < Mutations::BaseMutation
  argument :order_id, ID, required: true
  argument :amount_cents, Integer, required: true
  argument :note, String, required: false

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(order_id:, amount_cents:, note: nil)
    order = Order.find(order_id)
    authorize_buyer_request!(order)
    raise Errors::ValidationError, :cannot_offer unless order.state == Order::PENDING

    OfferService.create_pending_offer(order, amount_cents: amount_cents, note: note, from_id: current_user_id, from_type: Order::USER, creator_id: current_user_id)
    { order_or_error: { order: order } }
  end
end
