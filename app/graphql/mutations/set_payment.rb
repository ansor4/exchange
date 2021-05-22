class Mutations::SetPayment < Mutations::BaseMutation
  null true

  argument :id, ID, required: true
  argument :credit_card_id, String, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:, credit_card_id:)
    order = Order.find(id)
    authorize_buyer_request!(order)

    raise Errors::ValidationError.new(:invalid_state, state: order.state) unless order.state == Order::PENDING

    {
      order_or_error: { order: OrderService.set_payment!(order, credit_card_id) }
    }
  end
end
