class Mutations::FulfillAtOnce < Mutations::BaseMutation
  null true
  description 'Fulfill an order with one Fulfillment, it sets this fulfillment to each line item in order'

  argument :id, ID, required: true
  argument :fulfillment, Inputs::FulfillmentAttributes, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:, fulfillment:)
    order = Order.find(id)
    authorize_seller_request!(order)
    {
      order_or_error: { order: OrderService.fulfill_at_once!(order, fulfillment.to_h, context[:current_user][:id]) }
    }
  end
end
