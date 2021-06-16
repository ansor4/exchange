class Mutations::SelectShippingOption < Mutations::BaseMutation
  null true

  argument :id, ID, required: true
  argument :selected_shipping_quote_id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(id:, selected_shipping_quote_id:)
    order = Order.find(id)
    authorize_buyer_request!(order)

    OrderService.select_arta_shipment_option!(order, selected_shipping_quote_id: selected_shipping_quote_id)

    {
      order_or_error: { order: order }
    }
  rescue Errors::ApplicationError => e
    { order_or_error: { error: Types::ApplicationErrorType.from_application(e) } }
  end
end
