class OrderCancelationProcessor
  def initialize(order, user_id = nil)
    @order = order
    @user_id = user_id
    @payment_service = PaymentService.new(@order)
  end

  def queue_undeduct_inventory_jobs
    @order.line_items.each { |li| UndeductLineItemInventoryJob.perform_later(li.id) }
  end

  def notify
    OrderEvent.delay_post(@order, @user_id)
  end

  def refund_payment
    raise Errors::ValidationError.new(:unsupported_payment_method, @order.payment_method) unless @order.payment_method == Order::CREDIT_CARD

    transaction = @payment_service.refund
    @order.transactions << transaction
    raise Errors::ProcessingError.new(:refund_failed, transaction.failure_data) if transaction.failed?

    # Only credit commission exemption for refunds, cancelations never deducted from commission exemption total
    Gravity.credit_commission_exemption(@order.seller_id, @order.items_total_cents, @order.currency_code, @order.id, 'refund')
  end

  def cancel_payment
    raise Errors::ValidationError.new(:unsupported_payment_method, @order.payment_method) unless @order.payment_method == Order::CREDIT_CARD

    transaction = @payment_service.cancel_payment_intent
    @order.transactions << transaction
    raise Errors::ProcessingError.new(:cancel_payment_failed, transaction.failure_data) if transaction.failed?
  end
end
