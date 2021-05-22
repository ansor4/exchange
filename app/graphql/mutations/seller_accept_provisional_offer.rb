class Mutations::SellerAcceptProvisionalOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:)
    offer = Offer.find(offer_id)
    validate_request!(offer)
    order = offer.order

    previous_offer_amount = offer.amount_cents

    pending_offer = OfferService.create_pending_counter_offer(offer, amount_cents: previous_offer_amount, note: nil, from_type: order.seller_type, from_id: order.seller_id, creator_id: current_user_id)

    OfferService.submit_pending_offer(pending_offer)
    { order_or_error: { order: order } }
  end

  private

  def validate_request!(offer)
    authorize_seller_request!(offer)
    raise Errors::ValidationError, :invalid_state unless offer.order.state == Order::SUBMITTED
    raise Errors::ValidationError, :cannot_counter unless offer.awaiting_response_from == Order::SELLER
    # TODO: validate if artwork metadata is present on the artwork(s)
  end
end
