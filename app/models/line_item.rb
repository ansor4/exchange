class LineItem < ApplicationRecord
  include LineItemHelper

  has_paper_trail versions: { class_name: 'PaperTrail::LineItemVersion' }

  belongs_to :order
  has_many :line_item_fulfillments, dependent: :destroy
  has_many :fulfillments, through: :line_item_fulfillments

  has_many :shipping_quote_requests, dependent: :destroy
  has_many :shipping_quotes, through: :shipping_quote_requests
  has_one :shipment, dependent: :destroy

  belongs_to :selected_shipping_quote, class_name: :ShippingQuote, optional: true

  validate :offer_order_lacks_line_items, on: :create

  validates :artwork_version_id, presence: true
  validates :artwork_id, presence: true

  def total_list_price_cents
    list_price_cents * quantity
  end

  private

  def offer_order_lacks_line_items
    errors.add(:order, 'offer order can only have one line item') if order.mode == Order::OFFER && order.line_items.any?
  end
end
