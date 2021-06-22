module OrderService
  def self.create_with_artwork!(buyer_id:, buyer_type:, mode:, quantity:, artwork_id:, user_agent:, user_ip:, impulse_conversation_id: nil, edition_set_id: nil, find_active_or_create: false)
    order_creator = OrderCreator.new(
      buyer_id: buyer_id,
      buyer_type: buyer_type,
      mode: mode,
      quantity: quantity,
      artwork_id: artwork_id,
      edition_set_id: edition_set_id,
      user_agent: user_agent,
      user_ip: user_ip,
      impulse_conversation_id: impulse_conversation_id
    )

    # in case of Offer orders, we want to reuse existing pending/submitted offers
    create_method = find_active_or_create ? :find_or_create! : :create!
    order_creator.send(create_method) do |created_order|
      Exchange.dogstatsd.increment 'order.create'
      OrderFollowUpJob.set(wait_until: created_order.state_expires_at).perform_later(created_order.id, created_order.state)
    end
  end

  def self.set_shipping!(order, fulfillment_type:, shipping:, phone_number:)
    raise Errors::ValidationError, :invalid_state unless order.state == Order::PENDING
    raise Errors::ValidationError, :missing_phone_number if Order.shipping_requested?(fulfillment_type) && phone_number.nil?

    order_shipping = OrderShipping.new(order)
    case fulfillment_type
    when Order::PICKUP then order_shipping.pickup!(phone_number)
    when Order::SHIP then order_shipping.ship!(shipping, phone_number)
    when Order::SHIP_ARTA then order_shipping.ship_with_arta!(shipping, phone_number)
    end
    order
  end

  def self.select_arta_shipment_option!(order, selected_shipping_quote_id:)
    order_shipping = OrderShipping.new(order)
    order_shipping.select_arta_shipment_option!(selected_shipping_quote_id)
  end

  def self.set_payment!(order, credit_card_id)
    credit_card = Gravity.get_credit_card(credit_card_id)
    raise Errors::ValidationError.new(:invalid_credit_card, credit_card_id: credit_card_id) unless credit_card.dig(:user, :_id) == order.buyer_id

    # nilify external_charge_id in case we had in progress payment intent so we create a new one
    order.update!(credit_card_id: credit_card_id, external_charge_id: nil)
    order
  end

  def self.submit!(order, user_id)
    unless order.valid_artwork_version?
      Exchange.dogstatsd.increment 'submit.artwork_version_mismatch'
      raise Errors::ProcessingError, :artwork_version_mismatch
    end

    order_processor = OrderProcessor.new(order, user_id)
    raise Errors::ValidationError, order_processor.validation_error unless order_processor.valid?

    order_processor.advance_state(:submit!)
    order_processor.deduct_inventory!

    order_processor.set_totals!
    order_processor.hold
    order_processor.store_transaction

    raise Errors::FailedTransactionError.new(:charge_authorization_failed, order_processor.transaction) if order_processor.failed_payment?

    if order_processor.requires_action?
      Exchange.dogstatsd.increment 'submit.requires_action'
      raise Errors::PaymentRequiresActionError, order_processor.action_data
    end
    order_processor.on_success
    order
  rescue StandardError => e
    # catch all
    order_processor&.revert!(e.message)
    raise e
  end

  def self.approve!(order, user_id)
    raise Errors::ValidationError.new(:unsupported_payment_method, order.payment_method) unless order.payment_method == Order::CREDIT_CARD

    payment_service = PaymentService.new(order)
    order_processor = OrderProcessor.new(order, user_id)
    transaction = nil
    order.approve! do
      order_processor.debit_commission_exemption
      transaction = payment_service.capture_hold
      raise Errors::ProcessingError.new(:capture_failed, transaction.failure_data) if transaction.failed?
    end

    order.line_items.each do |li|
      RecordSalesTaxJob.perform_later(li.id)
      ARTA::ShippingService.new(li).book_shipment if order.fulfillment_type == Order::SHIP_ARTA
    end
    OrderEvent.delay_post(order, user_id)
    OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(order.id, order.state)
    ReminderFollowUpJob.set(wait_until: order.state_expiration_reminder_time).perform_later(order.id, order.state)
    Exchange.dogstatsd.increment 'order.approve'
    Exchange.dogstatsd.count('order.money_collected', order.buyer_total_cents)
    Exchange.dogstatsd.count('order.commission_collected', order.commission_fee_cents)
  ensure
    order.transactions << transaction if transaction.present?
  end

  def self.fulfill_at_once!(order, fulfillment, user_id)
    order.fulfill! do
      fulfillment = Fulfillment.create!(fulfillment.slice(:courier, :tracking_id, :estimated_delivery))
      order.line_items.each do |li|
        li.line_item_fulfillments.create!(fulfillment_id: fulfillment.id)
      end
    end
    OrderEvent.delay_post(order, user_id)
    order
  end

  def self.confirm_fulfillment!(order, user_id, fulfilled_by_admin: false)
    raise Errors::ValidationError, :wrong_fulfillment_type unless [Order::SHIP, Order::PICKUP].include? order.fulfillment_type

    order.fulfill! do
      order.update!(fulfilled_by_admin_id: user_id) if fulfilled_by_admin
    end
    OrderEvent.delay_post(order, user_id)
    order
  end

  def self.abandon!(order)
    order.abandon!
    Exchange.dogstatsd.increment 'order.abandoned'
  end

  def self.seller_lapse!(order)
    order.seller_lapse!
    order_cancelation_processor = OrderCancelationProcessor.new(order)
    order_cancelation_processor.cancel_payment if order.mode == Order::BUY
    order_cancelation_processor.queue_undeduct_inventory_jobs if order.mode == Order::BUY && order.require_inventory?
    order_cancelation_processor.notify
    Exchange.dogstatsd.increment 'order.seller_lapsed'
  end

  def self.buyer_lapse!(order)
    # this currently only happens in case of offers where we haven't deduct/hold any inventory or charge
    # so all we need to do is to change state
    order.buyer_lapse!
    OrderEvent.delay_post(order)
    Exchange.dogstatsd.increment 'order.buyer_lapsed'
  end

  def self.reject!(order, user_id, reason = nil)
    order.reject!(reason)
    order_cancelation_processor = OrderCancelationProcessor.new(order, user_id)
    order_cancelation_processor.cancel_payment if order.mode == Order::BUY
    order_cancelation_processor.queue_undeduct_inventory_jobs if order.mode == Order::BUY && order.require_inventory?
    order_cancelation_processor.notify
    Exchange.dogstatsd.increment 'order.reject'
  end

  def self.refund!(order)
    order.refund!
    order_cancelation_processor = OrderCancelationProcessor.new(order)
    order_cancelation_processor.refund_payment
    order_cancelation_processor.queue_undeduct_inventory_jobs if order.require_inventory?
    order_cancelation_processor.notify
    Exchange.dogstatsd.increment 'order.refund'
    Exchange.dogstatsd.count("order.money_refunded_#{order.currency_code}", order.buyer_total_cents)
  end
end
