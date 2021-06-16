class OrderShipping
  def initialize(order)
    @order = order
  end

  def pickup!(buyer_phone_number)
    @order.with_lock do
      @order.update!(
        fulfillment_type: Order::PICKUP,
        buyer_phone_number: buyer_phone_number,
        shipping_name: nil,
        shipping_address_line1: nil,
        shipping_address_line2: nil,
        shipping_city: nil,
        shipping_region: nil,
        shipping_country: nil,
        shipping_postal_code: nil
      )
      update_totals!
    end
  end

  def ship!(shipping_info, buyer_phone_number)
    @shipping_address = Address.new(shipping_info)
    raise Errors::ValidationError, :missing_country if @shipping_address&.country.blank?

    @order.with_lock do
      @order.update!(
        fulfillment_type: Order::SHIP,
        buyer_phone_number: buyer_phone_number,
        shipping_name: shipping_info[:name],
        shipping_address_line1: @shipping_address&.street_line1,
        shipping_address_line2: @shipping_address&.street_line2,
        shipping_city: @shipping_address&.city,
        shipping_region: @shipping_address&.region,
        shipping_country: @shipping_address&.country,
        shipping_postal_code: @shipping_address&.postal_code
      )
      update_totals!
    end
  end

  def ship_with_arta!(shipping_info, buyer_phone_number)
    @shipping_address = Address.new(shipping_info)
    raise Errors::ValidationError, :missing_country if @shipping_address&.country.blank?

    @order.update!(
      fulfillment_type: Order::SHIP_ARTA,
      buyer_phone_number: buyer_phone_number,
      shipping_name: shipping_info[:name],
      shipping_address_line1: @shipping_address&.street_line1,
      shipping_address_line2: @shipping_address&.street_line2,
      shipping_city: @shipping_address&.city,
      shipping_region: @shipping_address&.region,
      shipping_country: @shipping_address&.country,
      shipping_postal_code: @shipping_address&.postal_code
    )

    @order.line_items.each do |line_item|
      ARTA::ShippingService.new(line_item).generate_shipping_quotes
    end
  end

  def select_arta_shipment_option!(selected_shipping_quote_id)
    raise Errors::ValidationError, :missing_selected_shipping_quote_id if selected_shipping_quote_id.blank?
    raise Errors::ValidationError, :selected_shipping_quote_id_not_found unless @order.line_items.last.shipping_quotes.where(id: selected_shipping_quote_id).exists?

    @order.with_lock do
      @order.line_items.last.update(selected_shipping_quote_id: selected_shipping_quote_id)

      update_totals!
    end
  end

  private

  def update_totals!
    @order.mode == Order::OFFER ? set_offer_totals! : set_order_totals!
  end

  def set_offer_totals!
    return unless pending_offer?

    offer_totals = OfferTotals.new(@order, pending_offer.amount_cents)
    pending_offer.update!(
      shipping_total_cents: offer_totals.shipping_total_cents,
      tax_total_cents: offer_totals.tax_total_cents,
      should_remit_sales_tax: offer_totals.should_remit_sales_tax
    )
  end

  def set_order_totals!
    @order.line_items.map do |li|
      line_item_totals = LineItemTotals.new(
        li,
        fulfillment_type: @order.fulfillment_type,
        shipping_address: @order.shipping_address,
        nexus_addresses: @order.nexus_addresses,
        artsy_collects_sales_tax: @order.artsy_collects_sales_tax?
      )
      li.update!(
        shipping_total_cents: line_item_totals.shipping_total_cents,
        sales_tax_cents: line_item_totals.tax_total_cents,
        should_remit_sales_tax: line_item_totals.should_remit_sales_tax
      )
    end
    buy_order_totals = BuyOrderTotals.new(@order)
    @order.update!(
      shipping_total_cents: buy_order_totals.shipping_total_cents,
      tax_total_cents: buy_order_totals.tax_total_cents,
      buyer_total_cents: buy_order_totals.buyer_total_cents
    )
  end

  def pending_offer?
    @order.offers.pending.exists?
  end

  def pending_offer
    @pending_offer ||= @order.offers.pending.order(created_at: :desc).first
  end
end
