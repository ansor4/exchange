class PaymentService
  attr_reader :order

  def initialize(order)
    @order = order
    @payment_intent_id = order.external_charge_id
  end

  def hold
    create_payment_intent(capture: false)
  end

  def immediate_capture(off_session:)
    create_payment_intent(capture: true, off_session: off_session)
  end

  def capture_hold
    raise Errors::ProcessingError, :cannot_capture unless payment_intent.status == 'requires_capture'

    payment_intent.capture(transfer_data: { amount: order.seller_total_cents })
    new_transaction = Transaction.new(
      external_id: payment_intent.id,
      external_type: Transaction::PAYMENT_INTENT,
      source_id: payment_intent.payment_method,
      destination_id: payment_intent.transfer_data&.destination,
      amount_cents: payment_intent.amount,
      transaction_type: Transaction::CAPTURE,
      payload: payment_intent.to_h
    )
    update_transaction_with_payment_intent(new_transaction, payment_intent)
    new_transaction
  rescue Stripe::StripeError => e
    transaction_from_payment_intent_failure(e, transaction_type: Transaction::CAPTURE)
  end

  def refund
    payment_transaction = @order.transactions.where(external_id: @order.external_charge_id).first
    payment_transaction.external_type == Transaction::PAYMENT_INTENT ? refund_payment(payment_transaction.external_id) : refund_charge(payment_transaction.external_id)
  end

  def cancel_payment_intent
    payment_intent.cancel
    Transaction.new(external_id: @payment_intent_id, external_type: Transaction::PAYMENT_INTENT, transaction_type: Transaction::CANCEL, status: Transaction::SUCCESS, payload: payment_intent.to_h)
  rescue Stripe::StripeError => e
    generate_transaction_from_exception(e, Transaction::CANCEL, external_id: @payment_intent_id, external_type: Transaction::PAYMENT_INTENT)
  end

  def confirm_payment_intent
    return payment_intent_confirmation_failure(payment_intent) if payment_intent.status != 'requires_confirmation'

    payment_intent.confirm
    Transaction.new(
      external_id: payment_intent.id,
      external_type: Transaction::PAYMENT_INTENT,
      transaction_type: Transaction::CONFIRM,
      status: Transaction::SUCCESS,
      amount_cents: payment_intent.amount,
      source_id: payment_intent.payment_method,
      payload: payment_intent.to_h
    )
  rescue Stripe::StripeError => e
    transaction_from_payment_intent_failure(e)
  end

  private

  def payment_intent
    @payment_intent ||= Stripe::PaymentIntent.retrieve(@payment_intent_id)
  end

  def refund_charge(charge_id)
    refund = Stripe::Refund.create(charge: charge_id, reverse_transfer: true)
    Transaction.new(external_id: refund.id, external_type: Transaction::REFUND, transaction_type: Transaction::REFUND, status: Transaction::SUCCESS, payload: refund.charge)
  rescue Stripe::StripeError => e
    generate_transaction_from_exception(e, Transaction::REFUND, external_id: charge_id, external_type: Transaction::CHARGE)
  end

  def refund_payment(external_id)
    payment_intent = Stripe::PaymentIntent.retrieve(external_id)
    refund = Stripe::Refund.create(charge: payment_intent.charges.first.id, reverse_transfer: true)
    Transaction.new(external_id: refund.id, external_type: Transaction::REFUND, transaction_type: Transaction::REFUND, status: Transaction::SUCCESS, payload: refund.to_h)
  rescue Stripe::StripeError => e
    generate_transaction_from_exception(e, Transaction::REFUND, external_id: external_id, external_type: Transaction::PAYMENT_INTENT)
  end

  def create_payment_intent(capture:, off_session: false)
    payment_intent_params = create_payment_intent_params(capture: capture, off_session: off_session)
    payment_intent_params.merge!(setup_future_usage: 'off_session') unless off_session

    payment_intent = Stripe::PaymentIntent.create(payment_intent_params)

    new_transaction = Transaction.new(
      external_id: payment_intent.id,
      external_type: Transaction::PAYMENT_INTENT,
      source_id: payment_intent.payment_method,
      destination_id: order.merchant_account[:external_id],
      amount_cents: payment_intent.amount,
      transaction_type: capture ? Transaction::CAPTURE : Transaction::HOLD,
      payload: payment_intent.to_h
    )
    update_transaction_with_payment_intent(new_transaction, payment_intent)
    new_transaction
  rescue Stripe::StripeError => e
    transaction_from_payment_intent_failure(e, transaction_type: capture ? Transaction::CAPTURE : Transaction::HOLD)
  end

  def create_payment_intent_params(capture:, off_session:)
    {
      amount: order.buyer_total_cents,
      currency: order.currency_code,
      description: description,
      payment_method_types: ['card'],
      payment_method: order.credit_card[:external_id],
      customer: order.credit_card[:customer_account][:external_id],
      on_behalf_of: order.merchant_account[:external_id],
      transfer_data: {
        destination: order.merchant_account[:external_id],
        amount: order.seller_total_cents
      },
      transfer_group: order.id,
      off_session: off_session,
      metadata: metadata,
      capture_method: capture ? 'automatic' : 'manual',
      confirm: true, # it creates payment intent and tries to confirm at the same time
      confirmation_method: 'manual', # if requires action, we will confirm manually after
      shipping: {
        address: {
          line1: order.shipping_address&.street_line1,
          line2: order.shipping_address&.street_line2,
          city: order.shipping_address&.city,
          state: order.shipping_address&.region,
          postal_code: order.shipping_address&.postal_code,
          country: order.shipping_address&.country
        },
        name: order.shipping_name
      }
    }
  end

  def metadata
    {
      exchange_order_id: @order.id,
      buyer_id: @order.buyer_id,
      buyer_type: @order.buyer_type,
      seller_id: @order.seller_id,
      seller_type: @order.seller_type,
      type: @order.auction_seller? ? 'auction-bn' : 'bn-mo',
      mode: @order.mode,
      artist_ids: @order.artists.map { |a| a[:_id] }.join(','),
      artist_names: @order.artists.map { |a| a[:name] }.join(',')
    }
  end

  def description
    partner_name = (@order.partner[:name] || '').parameterize[0...12].upcase
    "#{partner_name} via Artsy"
  end

  def update_transaction_with_payment_intent(transaction, payment_intent)
    case payment_intent.status # https://stripe.com/docs/payments/intents#intent-statuses
    when 'requires_capture'
      transaction.status = Transaction::REQUIRES_CAPTURE
    when 'requires_action'
      transaction.status = Transaction::REQUIRES_ACTION
    when 'succeeded'
      transaction.status = Transaction::SUCCESS
    else
      # unknown status raise error
      raise "Unsupported payment_intent status: #{payment_intent.status}"
    end
  end

  def generate_transaction_from_exception(exc, type, external_id: nil, external_type:)
    body = exc.json_body[:error]
    Transaction.new(
      external_id: external_id || body[:charge],
      external_type: external_type,
      failure_code: body[:code],
      failure_message: body[:message],
      decline_code: body[:decline_code],
      transaction_type: type,
      status: Transaction::FAILURE,
      payload: exc.json_body
    )
  end

  def transaction_from_payment_intent_failure(exc, transaction_type: nil)
    body = exc.json_body
    pi = body[:error][:payment_intent]
    # attempting confirm failed
    Transaction.new(
      status: Transaction::FAILURE,
      external_id: pi[:id],
      external_type: Transaction::PAYMENT_INTENT,
      source_id: pi[:last_payment_error][:payment_method][:id],
      destination_id: pi[:transfer_data][:destination],
      amount_cents: pi[:amount],
      transaction_type: transaction_type,
      failure_code: pi[:last_payment_error][:code],
      failure_message: pi[:last_payment_error][:message],
      decline_code: pi[:last_payment_error][:decline_code],
      payload: exc.json_body
    )
  end

  def payment_intent_confirmation_failure(payment_intent)
    Transaction.new(
      external_id: payment_intent.id,
      external_type: Transaction::PAYMENT_INTENT,
      transaction_type: Transaction::CONFIRM,
      failure_code: 'cannot_confirm',
      failure_message: "Payment intent is not in a confirmable state: #{payment_intent.status}",
      status: payment_intent.status == 'requires_action' ? Transaction::REQUIRES_ACTION : Transaction::FAILURE,
      payload: payment_intent.to_h
    )
  end
end
