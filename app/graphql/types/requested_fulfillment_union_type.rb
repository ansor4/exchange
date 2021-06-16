class Types::Ship < Types::BaseObject
  field :phone_number, String, null: true
  def phone_number
    object.buyer_phone_number
  end
  # generate methods for shipping fields to field name on the model (add shipping_)
  %w[name address_line1 address_line2 city region country postal_code].each do |field_name|
    field field_name.to_sym, String, null: true
    define_method field_name do
      object.send("shipping_#{field_name}".to_sym)
    end
  end
end

class Types::ShipArta < Types::Ship; end

class Types::Pickup < Types::BaseObject
  field :fulfillment_type, String, null: false
  field :phone_number, String, null: true

  def phone_number
    object.buyer_phone_number
  end

  def fulfillment_type
    Order::PICKUP
  end
end

class Types::RequestedFulfillmentUnionType < Types::BaseUnion
  description 'Represents either a shipping information or pickup'
  possible_types Types::Ship, Types::Pickup, Types::ShipArta
  def self.resolve_type(object, _context)
    case object.fulfillment_type
    when Order::SHIP
      Types::Ship
    when Order::SHIP_ARTA
      Types::ShipArta
    when Order::PICKUP
      Types::Pickup
    else
      raise "Unexpected Return value: #{object.inspect}"
    end
  end
end
