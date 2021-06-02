class Mutations::SetShipping < Mutations::BaseMutation
  null true

  argument :id, ID, required: true
  argument :fulfillment_type, Types::OrderFulfillmentTypeEnum, required: true
  argument :shipping, Inputs::ShippingAttributes, required: false
  argument :phone_number, String, required: false

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:, fulfillment_type:, shipping: nil, phone_number: nil)
    order = Order.find(id)
    authorize_buyer_request!(order)

    OrderService.set_shipping!(order, fulfillment_type: fulfillment_type, shipping: shipping, phone_number: phone_number || shipping&.phone_number)
    {
      order_or_error: { order: order }
    }
  end
end
