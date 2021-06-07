class OrderEvent < Events::BaseEvent
  TOPIC = 'commerce'.freeze
  PROPERTIES_ATTRS = %i[
    id
    buyer_id
    buyer_phone_number
    buyer_total_cents
    buyer_type
    code
    commission_fee_cents
    created_at
    currency_code
    external_charge_id
    fulfilled_by_admin_id
    fulfillment_type
    impulse_conversation_id
    items_total_cents
    mode
    seller_id
    seller_total_cents
    seller_type
    shipping_address_line1
    shipping_address_line2
    shipping_city
    shipping_country
    shipping_name
    shipping_postal_code
    shipping_region
    shipping_total_cents
    state
    state_expires_at
    state_reason
    tax_total_cents
    total_list_price_cents
    transaction_fee_cents
    updated_at
  ].freeze

  def self.post(order, action, user_id)
    event = new(user: user_id, action: action, model: order)
    Artsy::EventService.post_event(topic: TOPIC, event: event)
  end

  def self.delay_post(order, user_id = nil)
    event = new(user: user_id, action: order.state, model: order)
    PostEventJob.perform_later(TOPIC, event.to_json, event.routing_key)
  end

  def subject
    {
      id: @subject
    }
  end

  def properties
    PROPERTIES_ATTRS.index_with { |att| @object.send(att) }.merge(line_items: line_items_details, last_offer: last_offer)
  end

  private

  def line_items_details
    @object.line_items.map { |li| line_item_detail(li) }
  end

  def last_offer
    return unless @object.last_offer

    last_offer = @object.last_offer
    in_response_to = if last_offer.responds_to
      {
        id: last_offer.responds_to.id,
        amount_cents: last_offer.responds_to.amount_cents,
        created_at: last_offer.responds_to.created_at,
        from_participant: last_offer.responds_to.from_participant
      }
    end
    {
      id: last_offer.id,
      amount_cents: last_offer.amount_cents,
      shipping_total_cents: last_offer.shipping_total_cents,
      tax_total_cents: last_offer.tax_total_cents,
      from_participant: last_offer.from_participant,
      creator_id: last_offer.creator_id,
      in_response_to: in_response_to,
      note: last_offer.note
    }
  end

  def line_item_detail(line_item)
    {
      price_cents: line_item.list_price_cents,
      list_price_cents: line_item.list_price_cents,
      artwork_id: line_item.artwork_id,
      edition_set_id: line_item.edition_set_id,
      quantity: line_item.quantity,
      commission_fee_cents: line_item.commission_fee_cents
    }
  end
end
