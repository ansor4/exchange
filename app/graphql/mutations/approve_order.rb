class Mutations::ApproveOrder < Mutations::BaseMutation
  null true

  argument :id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:)
    order = Order.find(id)
    authorize_seller_request!(order)
    OrderService.approve!(order, current_user_id)
    {
      order_or_error: { order: order }
    }
  end
end
