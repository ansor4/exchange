class Mutations::BuyerCounterOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :amount_cents, Integer, required: true
  argument :note, String, required: false

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:, amount_cents:, note: nil)
    offer = Offer.find(offer_id)

    validate_request!(offer)

    pending_offer = OfferService.create_pending_counter_offer(offer, amount_cents: amount_cents, note: note, from_id: offer.order.buyer_id, from_type: offer.order.buyer_type, creator_id: current_user_id)

    { order_or_error: { order: pending_offer.order } }
  end

  private

  def validate_request!(offer)
    authorize_buyer_request!(offer)
    raise Errors::ValidationError, :cannot_counter unless offer.awaiting_response_from == Order::BUYER
  end
end
