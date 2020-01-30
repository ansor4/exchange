class OrderProcessor
  attr_accessor :order, :transaction, :validation_error

  def initialize(order, user_id, offer = nil)
    @order = order
    @offer = offer
    @user_id = user_id
    @validation_error = nil
    @transaction = nil
    @deducted_inventory = []
    @validated = false
    @totals_set = false
    @state_changed = false
    @original_state_expires_at = nil
    @payment_service = PaymentService.new(@order)
  end

  def revert!
    undeduct_inventory! if @deducted_inventory.any?
    reset_totals! if @totals_set
    return unless @state_changed

    order.revert!
    order.update!(state_expires_at: @original_state_expires_at)
    @state_changed = false
  end

  def advance_state(action)
    @original_state_expires_at = order.state_expires_at
    order.send(action)
    @state_changed = true
  end

  def set_totals!
    order.line_items.each { |li| li.update!(commission_fee_cents: li.current_commission_fee_cents) } if order.mode == Order::BUY
    totals = order.mode == Order::BUY ? BuyOrderTotals.new(@order) : OfferOrderTotals.new(@offer)
    order.update!(
      transaction_fee_cents: totals.transaction_fee_cents,
      commission_rate: order.current_commission_rate,
      commission_fee_cents: totals.commission_fee_cents,
      seller_total_cents: totals.seller_total_cents
    )

    @totals_set = true
  end

  def reset_totals!
    order.line_items.each { |li| li.update!(commission_fee_cents: nil) } if order.mode == Order::BUY
    order.update!(transaction_fee_cents: nil, commission_rate: nil, commission_fee_cents: nil, seller_total_cents: nil)
    @totals_set = false
  end

  def hold
    @transaction = if @order.external_charge_id
      # we already have a payment intent on this order
      @payment_service.confirm_payment_intent
    else
      @payment_service.hold
    end
  end

  def charge(off_session = false)
    @transaction = if @order.external_charge_id
      @payment_service.confirm_payment_intent
    else
      @payment_service.immediate_capture(off_session: off_session)
    end
  end

  def failed_payment?
    @transaction&.failed?
  end

  def requires_action?
    @transaction&.requires_action?
  end

  def action_data
    @transaction&.action_data
  end

  def valid?
    @validated ||= begin
      @validation_error = :unsupported_payment_method unless @order.payment_method == Order::CREDIT_CARD
      @validation_error ||= :missing_required_info unless @order.can_commit?
      @validation_error ||= @order.assert_credit_card
    end
    @validation_error.nil?
  end

  def undeduct_inventory!
    @deducted_inventory.each { |li| Gravity.undeduct_inventory(li) }
    @deducted_inventory = []
  end

  def deduct_inventory
    # Try holding artwork and deduct inventory
    @order.line_items.each do |li|
      Gravity.deduct_inventory(li)
      @deducted_inventory << li
    end
    true
  rescue Errors::InsufficientInventoryError
    false
  end

  def store_transaction(off_session = false)
    order.transactions << transaction
    order.update!(external_charge_id: transaction.external_id) unless transaction.failed? || (transaction.requires_action? && off_session)
    PostTransactionNotificationJob.perform_later(transaction.id, @user_id)
  end

  def on_success
    OrderEvent.delay_post(order, @user_id)
    OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(order.id, order.state)
    ReminderFollowUpJob.set(wait_until: order.state_expiration_reminder_time).perform_later(order.id, order.state)
    Exchange.dogstatsd.increment "order.#{order.state}"
  end

  def self.debit_exemption
    mutation_args = {
      input: {
        partnerId: '581b45e4cd530e658b000124',
        exemption: { amountMinor: 1, currencyCode: 'USD' },
        referenceId: SecureRandom.uuid,
        notes: "hello world"
      }
    }
    Gravity.authenticated.debit_commission_exemption(mutation_args)
  end

  def revert_debit_exemption; end
end
