class Mutations::ConfirmFulfillment < Mutations::BaseMutation
  null true

  argument :id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:)
    order = Order.find(id)
    authorize_seller_request!(order)

    raise Errors::ValidationError, :wrong_fulfillment_type unless order.fulfillment_type == Order::SHIP

    OrderService.confirm_fulfillment!(order, context[:current_user][:id])
    {
      order_or_error: { order: order }
    }
  end
end
