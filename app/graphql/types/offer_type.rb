class Types::OfferType < Types::BaseObject
  description 'An Offer'
  graphql_name 'Offer'

  field :id, ID, null: false
  field :internalID, ID, null: false, method: :id, camelize: false
  field :from, Types::OrderPartyUnionType, null: false
  field :amount_cents, Integer, null: false
  field :tax_total_cents, Integer, null: true
  field :shipping_total_cents, Integer, null: true
  field :creator_id, String, null: false
  field :created_at, Types::DateTimeType, null: false
  field :submitted_at, Types::DateTimeType, null: true
  field :order, Types::OrderInterface, null: false
  field :responds_to, Types::OfferType, null: true
  field :from_participant, Types::OrderParticipantEnum, null: true
  field :buyer_total_cents, Integer, null: true
  field :has_definite_total, Boolean, null: false, description: 'True when a all the fees (shipping/tax) were calculated for the offer'
  field :offer_amount_changed, Boolean, null: false, description: 'Only false when previous offer has the same amount.'
  field :defines_total, Boolean, null: false, description: 'True when this offer fills in the missing fees from the previous one'
  field :buyer_offer_action_type, Types::BuyerOfferActionEnum, null: true, description: 'Type of action buyer needs to perform in response to the offer'
  field :note, String, null: true
  field :currency_code, String, null: false

  def from
    OpenStruct.new(
      id: object.from_id,
      type: object.from_type
    )
  end

  def currency_code
    object.order.currency_code
  end

  # rubocop:disable Naming/PredicateName
  def has_definite_total
    object.definite_total?
  end
  # rubocop:enable Naming/PredicateName

  def offer_amount_changed
    object.offer_amount_changed?
  end

  def defines_total
    object.defines_total?
  end
end
