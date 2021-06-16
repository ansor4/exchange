class Shipment < ApplicationRecord
  STATUSES = %w[
    pending
    confirmed
    collected
    in_transit
    completed
    cancelled
  ].freeze
  belongs_to :line_item
  validates :status, inclusion: STATUSES
end
