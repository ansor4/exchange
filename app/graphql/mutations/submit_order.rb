class Mutations::SubmitOrder < Mutations::BaseMutation
  null true

  argument :id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:)
    order = Order.find(id)
    authorize_buyer_request!(order)
    { order_or_error: { order: OrderService.submit!(order, current_user_id) } }
  rescue Errors::PaymentRequiresActionError => e
    Raven.capture_exception(e)
    { order_or_error: { action_data: e.action_data } }
  end
end
