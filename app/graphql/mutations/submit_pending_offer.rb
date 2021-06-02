class Mutations::SubmitPendingOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:)
    offer = Offer.find(offer_id)
    authorize_offer_owner_request!(offer)
    raise Errors::ValidationError, :invalid_state unless offer.order.state == Order::SUBMITTED

    submitted_offer = OfferService.submit_pending_offer(offer)

    { order_or_error: { order: submitted_offer.order } }
  end
end
