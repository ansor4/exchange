class Types::BuyerOfferActionEnum < Types::BaseEnum
  value 'PAYMENT_FAILED', "Buyer's payment failed", value: 'PAYMENT_FAILED'
  value 'RECEIVED_OFFER_CONFIRM_NEEDED', 'Buyer received a counter offer needs to confirm tax and shipping', value: 'RECEIVED_OFFER_CONFIRM_NEEDED'
  value 'OFFER_ACCEPTED_CONFIRM_NEEDED', "Buyer's offer accepted needs to confirm tax and shipping", value: 'OFFER_ACCEPTED_CONFIRM_NEEDED'
  value 'RECEIVED_OFFER', 'Buyer received a counter offer', value: 'RECEIVED_OFFER'
  value 'OFFER_ACCEPTED', "Buyer's offer is accepted and final", value: 'OFFER_ACCEPTED'
  value 'PROVISIONAL_OFFER_ACCEPTED', 'Provisional offer is accepted and tax/shipping confirmed', value: 'PROVISIONAL_OFFER_ACCEPTED'
end
