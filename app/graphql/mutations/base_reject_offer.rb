class Mutations::BaseRejectOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :reject_reason, Types::CancelReasonTypeEnum, required: false

  field :order_or_error, Mutations::OrderOrFailureUnionType, 'A union of success/failure', null: false

  def resolve(offer_id:, reject_reason: nil)
    offer = Offer.find(offer_id)
    order = offer.order

    authorize!(order)

    # should check whether or not it's an offer-mode order
    raise Errors::ValidationError, :not_last_offer unless offer.last_offer?
    raise Errors::ValidationError, :cannot_reject_offer unless waiting_for_response?(offer)

    OrderService.reject!(offer.order, current_user_id, sanitize_reject_reason(reject_reason))

    { order_or_error: { order: order } }
  end

  def authorize!(_order)
    raise NotImplementedError
  end

  def waiting_for_response?(_offer)
    raise NotImplementedError
  end

  def sanitize_reject_reason(_reject_reason)
    raise NotImplementedError
  end
end
