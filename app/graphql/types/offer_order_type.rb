class Types::OfferOrderType < Types::BaseObject
  implements Types::OrderInterface

  field :offers, Types::OfferType.connection_type, null: true do
    argument :from_id, String, required: false
    argument :from_type, String, required: false
  end
  field :last_offer, Types::OfferType, null: true, description: 'Last submitted offer'
  field :my_last_offer, Types::OfferType, null: true
  field :awaiting_response_from, Types::OrderParticipantEnum, null: true
  field :impulse_conversation_id, String, null: true
  field :buyer_action, Types::BuyerOfferActionEnum, null: true, description: 'Type of action buyer needs to perform in response to the offer'

  def offers(**args)
    offers = object.offers.submitted
    offers = offers.where(args.slice(:from_id, :from_type)) if args.keys.any? { |ar| %i[from_id from_type].include? ar }
    offers.order(created_at: :desc)
  end

  def my_last_offer
    return unless context[:current_user][:id]

    object.offers.where(creator_id: context[:current_user][:id]).order(created_at: :desc).first
  end

  def buyer_action
    return if object.mode == Order::BUY

    object&.last_offer&.buyer_offer_action_type
  end
end
