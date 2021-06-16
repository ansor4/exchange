class Types::MutationType < Types::BaseObject
  # Buyer
  field :create_order_with_artwork, mutation: Mutations::CreateOrderWithArtwork
  field :create_offer_order_with_artwork, mutation: Mutations::CreateOfferOrderWithArtwork
  field :create_inquiry_offer_order_with_artwork, mutation: Mutations::CreateInquiryOfferOrderWithArtwork
  field :set_shipping, mutation: Mutations::SetShipping
  field :select_shipping_option, mutation: Mutations::SelectShippingOption
  field :set_payment, mutation: Mutations::SetPayment
  field :submit_order, mutation: Mutations::SubmitOrder
  field :buyer_accept_offer, mutation: Mutations::BuyerAcceptOffer
  field :buyer_reject_offer, mutation: Mutations::BuyerRejectOffer
  field :add_initial_offer_to_order, mutation: Mutations::AddInitialOfferToOrder
  field :submit_order_with_offer, mutation: Mutations::SubmitOrderWithOffer
  field :buyer_counter_offer, mutation: Mutations::BuyerCounterOffer
  field :submit_pending_offer, mutation: Mutations::SubmitPendingOffer
  field :fix_failed_payment, mutation: Mutations::FixFailedPayment

  # Seller
  field :approve_order, mutation: Mutations::ApproveOrder
  field :seller_accept_offer, mutation: Mutations::SellerAcceptOffer
  field :seller_reject_offer, mutation: Mutations::SellerRejectOffer
  field :seller_counter_offer, mutation: Mutations::SellerCounterOffer
  field :seller_accept_provisional_offer, mutation: Mutations::SellerAcceptProvisionalOffer
  field :reject_order, mutation: Mutations::RejectOrder
  field :fulfill_at_once, mutation: Mutations::FulfillAtOnce
  field :confirm_pickup, mutation: Mutations::ConfirmPickup
  field :confirm_fulfillment, mutation: Mutations::ConfirmFulfillment
end
