class Offer < ApplicationRecord
  has_paper_trail versions: { class_name: 'PaperTrail::OfferVersion' }

  EXPIRATION = 3.days.freeze

  OFFER_ACTIONS = [
    PAYMENT_FAILED = 'PAYMENT_FAILED'.freeze,
    OFFER_RECEIVED_CONFIRM_NEEDED = 'OFFER_RECEIVED_CONFIRM_NEEDED'.freeze,
    OFFER_ACCEPTED_CONFIRM_NEEDED = 'OFFER_ACCEPTED_CONFIRM_NEEDED'.freeze,
    OFFER_RECEIVED = 'OFFER_RECEIVED'.freeze,
    OFFER_ACCEPTED = 'OFFER_ACCEPTED'.freeze,
    PROVISIONAL_OFFER_ACCEPTED = 'PROVISIONAL_OFFER_ACCEPTED'.freeze
  ].freeze

  belongs_to :order
  belongs_to :responds_to, class_name: 'Offer', optional: true

  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :pending, -> { where(submitted_at: nil) }

  def last_offer?
    order.last_offer == self
  end

  def submitted?
    submitted_at.present?
  end

  def buyer_total_cents
    return unless definite_total?

    amount_cents + shipping_total_cents + tax_total_cents
  end

  def from_participant
    if from_id == order.seller_id && from_type == order.seller_type
      Order::SELLER
    elsif from_id == order.buyer_id && from_type == order.buyer_type
      Order::BUYER
    else
      raise Errors::ValidationError, :unknown_participant_type
    end
  end

  def to_participant
    from_participant == Order::SELLER ? Order::BUYER : Order::SELLER
  end

  def awaiting_response_from
    return unless submitted?

    case from_participant
    when Order::BUYER then Order::SELLER
    when Order::SELLER then Order::BUYER
    end
  end

  def definite_total?
    [amount_cents, shipping_total_cents, tax_total_cents].all?(&:present?)
  end

  def offer_amount_changed?
    return false if responds_to.blank?

    amount_cents != responds_to.amount_cents
  end

  def defines_total?
    return false if responds_to.blank?

    definite_total? && !responds_to.definite_total?
  end

  def buyer_offer_action_type
    return Offer::PAYMENT_FAILED if order.last_transaction_failed?

    if order.state == Order::SUBMITTED && from_participant == Order::SELLER
      if defines_total?
        # provisional inquery checkout offer scenarios where metadata was initially missing
        return Offer::OFFER_RECEIVED_CONFIRM_NEEDED if offer_amount_changed?

        Offer::OFFER_ACCEPTED_CONFIRM_NEEDED
      elsif offer_amount_changed?
        Offer::OFFER_RECEIVED
      end
    # regular counter offer. either a definite offer on artwork with all metadata, or a provisional offer but metadata was provided in previous back and forth
    elsif order.state == Order::APPROVED && from_participant == Order::BUYER
      Offer::OFFER_ACCEPTED
    elsif order.state == Order::APPROVED && from_participant == Order::SELLER
      # Offer accepted. This appears when collector confirms totals on an accepted provisional offer
      return Offer::PROVISIONAL_OFFER_ACCEPTED if defines_total?

      # either the total was defined previously or wasn't provisional
      Offer::OFFER_ACCEPTED
    end
  end
end
