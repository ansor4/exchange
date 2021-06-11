class ShippingQuote < ApplicationRecord
  TIERS = [
    PARCEL = 'parcel'.freeze,
    SELECT = 'select'.freeze,
    PREMUIM = 'premium'.freeze
  ].freeze

  belongs_to :shipping_quote_request
  has_one :line_item, foreign_key: :selected_shipping_quote_id, dependent: :destroy, inverse_of: :shipping_quotes

  validates :tier, presence: true, inclusion: TIERS
end
