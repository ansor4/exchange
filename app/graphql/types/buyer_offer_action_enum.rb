class Types::BuyerOfferActionEnum < Types::BaseEnum
  value 'PAYMENT_FAILED', "Buyer's payment failed", value: Offer::PAYMENT_FAILED
  value 'OFFER_RECEIVED_CONFIRM_NEEDED', 'Buyer received a counter, offer needs to confirm tax and shipping', value: Offer::OFFER_RECEIVED_CONFIRM_NEEDED
  value 'OFFER_ACCEPTED_CONFIRM_NEEDED', "Buyer's offer accepted, needs to confirm tax and shipping", value: Offer::OFFER_ACCEPTED_CONFIRM_NEEDED
  value 'OFFER_RECEIVED', 'Buyer received a counter offer', value: Offer::OFFER_RECEIVED
  value 'OFFER_ACCEPTED', "Buyer's offer is accepted and final", value: Offer::OFFER_ACCEPTED
  value 'PROVISIONAL_OFFER_ACCEPTED', 'Provisional offer is accepted and tax/shipping confirmed', value: Offer::PROVISIONAL_OFFER_ACCEPTED
end
