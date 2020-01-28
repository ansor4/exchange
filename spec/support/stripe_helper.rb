RSpec.shared_context 'include stripe helper' do
  before { StripeMock.start }
  after { StripeMock.stop }

  def prepare_payment_intent_create_failure(id: 'pi_1', status: 'requires_payment_method', charge_error: nil, capture: false, payment_method: 'cc_1', amount: 20_00, client_secret: 'pi_test1')
    case status
    when 'requires_action'
      payment_intent = double(id: id, payment_method: payment_method, capture_method: capture ? 'automatic' : 'manual', amount: amount, status: status, client_secret: client_secret)
      mock_payment_intent_call(:create, payment_intent)
    when 'requires_payment_method'
      error = Stripe::CardError.new(charge_error[:message], decline_code: charge_error[:decline_code], code: charge_error[:code])
      allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: status, capture: capture, amount: amount, code: charge_error[:code], decline_code: charge_error[:decline_code]) })
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(error)
    when 'testmode_charges_only'
      error = Stripe::StripeError.new
      allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: status, capture: capture, amount: amount, code: charge_error[:code], decline_code: charge_error[:decline_code]) })
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(error)
    end
  end

  def prepare_payment_intent_create_success(capture: false, payment_method: 'cc_1', amount: 20_00, id: 'pi_1')
    payment_intent = double(id: id, payment_method: payment_method, amount: amount, capture_method: capture ? 'automatic' : 'manual', status: 'succeeded')
    mock_payment_intent_call(:create, payment_intent)
  end

  def prepare_payment_intent_confirm_failure(id: 'pi_1', charge_error:, payment_method: 'cc_1', amount: 20_00, status: 'requires_confirmation')
    payment_intent = double(id: id, payment_method: payment_method, amount: amount, capture_method: 'manual', status: status, transfer_data: double(destination: 'ma_1'), last_payment_error: double(charge_error))
    error = Stripe::CardError.new(charge_error[:message], decline_code: charge_error[:decline_code], code: charge_error[:code])
    allow(payment_intent).to receive(:confirm).and_raise(error)
    allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: 'requires_payment_method', capture: true, amount: amount, code: charge_error[:code], decline_code: charge_error[:decline_code]) })
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_confirm_raise_invalid(payment_method: 'cc_1', amount: 20_00, message: 'You cannot confirm this PaymentIntent because it’s missing a payment method.', code: 'payment_intent_unexpected_state')
    payment_intent = double(
      id: 'pi_1',
      payment_method: payment_method,
      amount: amount,
      capture_method: 'manual',
      status: 'requires_confirmation',
      transfer_data: double(destination: 'ma_1'),
      last_payment_error: double(message: message, code: code)
    )
    error = Stripe::InvalidRequestError.new(message, code)
    allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: 'requires_payment_method', capture: true, amount: amount, code: code, decline_code: nil) })
    allow(payment_intent).to receive(:confirm).and_raise(error)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_confirm_success(id: 'pi_1', payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: id, payment_method: payment_method, amount: amount, capture_method: 'manual', transfer_data: double(destination: 'ma_1'))
    allow(payment_intent).to receive(:status).and_return('requires_confirmation', 'requires_capture')
    allow(payment_intent).to receive(:confirm)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_capture_failure(charge_error:, payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, capture_method: 'manual', status: 'requires_capture', transfer_data: double(destination: 'ma_1'), last_payment_error: double(charge_error))
    error = Stripe::CardError.new(charge_error[:message], decline_code: charge_error[:decline_code], code: charge_error[:code])
    allow(payment_intent).to receive(:capture).and_raise(error)
    allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: 'requires_payment_method', capture: true, amount: amount, code: charge_error[:code], decline_code: charge_error[:decline_code]) })
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_capture_success(payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, capture_method: 'manual', transfer_data: double(destination: 'ma_1'))
    allow(payment_intent).to receive(:status).and_return('requires_capture', 'succeeded')
    allow(payment_intent).to receive(:capture)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_capture_update_transfer_data_success(payment_method: 'cc_1', amount: 20_00, transfer_amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, capture_method: 'manual', transfer_data: double(destination: 'ma_1', amount: transfer_amount))
    allow(payment_intent).to receive(:status).and_return('requires_capture', 'succeeded')
    allow(payment_intent).to receive(:capture)
    allow(payment_intent).to receive(:to_h).and_return(id: 'pi_1', client_secret: 'pi_test1', 'transfer_data' => { 'amount' => transfer_amount })
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(payment_intent)
  end

  def prepare_payment_intent_cancel_failure(charge_error:, payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, capture_method: 'manual', status: 'requires_capture', transfer_data: double(destination: 'ma_1'), last_payment_error: double(charge_error))
    error = Stripe::CardError.new(charge_error[:message], decline_code: charge_error[:decline_code], code: charge_error[:code])
    allow(payment_intent).to receive(:cancel).and_raise(error)
    allow(error).to receive(:json_body).and_return(error: { payment_intent: basic_payment_intent(status: 'requires_payment_method', capture: true, amount: amount, code: charge_error[:code], decline_code: charge_error[:decline_code]) })
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_cancel_success(payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, capture_method: 'manual', transfer_data: double(destination: 'ma_1'))
    allow(payment_intent).to receive(:status).and_return('requires_capture', 'canceled')
    allow(payment_intent).to receive(:cancel)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_refund_success(payment_method: 'cc_1', amount: 20_00)
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, transfer_data: double(destination: 'ma_1'), charges: [double(id: 'ch_1')])
    allow(payment_intent).to receive(:status).and_return('requires_capture', 'succeeded')
    refund = double(id: 're_1')
    allow(refund).to receive(:to_h).and_return(id: 're_1')
    allow(Stripe::Refund).to receive(:create).with(charge: 'ch_1', reverse_transfer: true).and_return(refund)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_payment_intent_refund_failure(charge_id: 'ch_1', payment_method: 'cc_1', amount: 20_00, code:, decline_code:, message:)
    refund_error = Stripe::StripeError.new
    allow(refund_error).to receive(:json_body).and_return(error: stripe_exception_json_body(charge_id: charge_id, code: code, decline_code: decline_code, message: message))
    payment_intent = double(id: 'pi_1', payment_method: payment_method, amount: amount, transfer_data: double(destination: 'ma_1'), charges: [double(id: 'ch_1')])
    allow(payment_intent).to receive(:status).and_return('requires_capture', 'succeeded')
    allow(Stripe::Refund).to receive(:create).with(charge: 'ch_1', reverse_transfer: true).and_raise(refund_error)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def prepare_setup_intent_create(payment_method: 'cc_1', status: 'succeeded')
    setup_intent = double(id: 'si_1', payment_method: payment_method, status: status)
    allow(setup_intent).to receive(:to_h).and_return(id: 'si_1', client_secret: 'si_test1')
    allow(Stripe::SetupIntent).to receive(:create).and_return(setup_intent)
  end

  def prepare_setup_intent_create_failure(charge_error:)
    error = Stripe::CardError.new(charge_error[:message], decline_code: charge_error[:decline_code], code: charge_error[:code])
    allow(error).to receive(:json_body).and_return(error: { setup_intent: basic_setup_intent(code: charge_error[:code], decline_code: charge_error[:decline_code]) })
    allow(Stripe::SetupIntent).to receive(:create).and_raise(error)
  end

  def prepare_setup_intent_retrieve(payment_method: 'cc_1', status: 'succeeded', on_behalf_of: 'acc_123')
    setup_intent = double(id: 'si_1', payment_method: payment_method, status: status, on_behalf_of: on_behalf_of)
    allow(setup_intent).to receive(:to_h).and_return(id: 'si_1', client_secret: 'si_test1')
    allow(Stripe::SetupIntent).to receive(:retrieve).and_return(setup_intent)
  end

  def mock_retrieve_payment_intent(status:)
    payment_intent = double(id: 'pi_1', status: status)
    mock_payment_intent_call(:retrieve, payment_intent)
  end

  def mock_payment_intent_call(method, payment_intent)
    allow(payment_intent).to receive(:to_h).and_return(id: 'pi_1', client_secret: 'pi_test1')
    allow(Stripe::PaymentIntent).to receive(method).and_return(payment_intent)
  end

  def stripe_exception_json_body(props)
    {
      charge: 'ch_1',
      code: 'card_declined',
      decline_code: 'do_not_honor',
      message: 'The card was declined'
    }.merge(props)
  end

  # rubocop:disable Metrics/MethodLength
  def basic_payment_intent(status:, capture:, code:, decline_code:, amount: 1000)
    {
      id: 'pi_1',
      object: 'payment_intent',
      amount: amount,
      amount_capturable: 0,
      amount_received: 0,
      application: nil,
      application_fee_amount: nil,
      canceled_at: nil,
      cancellation_reason: nil,
      capture_method: capture ? 'automatic' : 'manual',
      charges: {
        object: 'list',
        data: [{
          id: 'ch_1',
          object: 'charge',
          amount: 1000,
          amount_refunded: 0,
          application: nil,
          application_fee: nil,
          application_fee_amount: nil,
          balance_transaction: nil,
          billing_details: {
            address: {
              city: 'Brooklyn',
              country: 'US',
              line1: '392 Nowhere st',
              line2: 'unit 3d',
              postal_code: '11238',
              state: 'NY'
            },
            email: nil,
            name: 'A Buyer',
            phone: nil
          },
          captured: false,
          created: 1564154992,
          currency: 'eur',
          customer: 'cus_1',
          description: nil,
          destination: nil,
          dispute: nil,
          failure_code: code,
          failure_message: 'Your card was declined.',
          fraud_details: {},
          invoice: nil,
          livemode: false,
          metadata: {},
          on_behalf_of: nil,
          order: nil,
          outcome: {
            network_status: 'declined_by_network',
            reason: 'generic_decline',
            risk_level: 'normal',
            risk_score: 41,
            seller_message: 'The bank did not return any further details with this decline.',
            type: 'issuer_declined'
          },
          paid: false,
          payment_intent: 'pi_1',
          payment_method: 'cc_1',
          payment_method_details: {
            card: {
              brand: 'visa',
              checks: {
                address_line1_check: 'pass',
                address_postal_code_check: 'pass',
                cvc_check: nil
              },
              country: 'US',
              exp_month: 2,
              exp_year: 2022,
              fingerprint: 'fingerprint',
              funding: 'credit',
              last4: '0341',
              three_d_secure: nil,
              wallet: nil
            },
            type: 'card'
          },
          receipt_email: nil,
          receipt_number: nil,
          receipt_url: 'https://pay.stripe.com/receipts/acct_172ojZGK3Gnpfa3O/ch_1/rcpt_FVWPR1qfouqPv2nnbYnzRqY9RyvVu76',
          refunded: false,
          refunds: {
            object: 'list',
            data: [],
            has_more: false,
            total_count: 0,
            url: '/v1/charges/ch_1/refunds'
          },
          review: nil,
          shipping: nil,
          source: nil,
          source_transfer: nil,
          statement_descriptor: nil,
          status: 'failed',
          transfer_data: nil,
          transfer_group: nil
        }],
        has_more: false,
        total_count: 1,
        url: '/v1/charges?payment_intent=pi_1'
      },
      client_secret: 'pi_1_secret_1',
      confirmation_method: 'automatic',
      created: 1564154992,
      currency: 'eur',
      customer: 'cus_1',
      description: nil,
      invoice: nil,
      last_payment_error: {
        charge: 'ch_1',
        code: code,
        decline_code: decline_code,
        doc_url: 'https://stripe.com/docs/error-codes/card-declined',
        message: 'Your card was declined.',
        payment_method: {
          id: 'cc_1',
          object: 'payment_method',
          billing_details: {
            address: {
              city: 'Brooklyn',
              country: 'US',
              line1: '392 Nowhere st',
              line2: 'unit 3d',
              postal_code: '11238',
              state: 'NY'
            },
            email: nil,
            name: 'A Buyer',
            phone: nil
          },
          card: {
            brand: 'visa',
            checks: {
              address_line1_check: 'pass',
              address_postal_code_check: 'pass',
              cvc_check: 'pass'
            },
            country: 'US',
            exp_month: 2,
            exp_year: 2022,
            fingerprint: 'fingerprint',
            funding: 'credit',
            generated_from: nil,
            last4: '0341',
            three_d_secure_usage: { supported: true },
            wallet: nil
          },
          created: 1564153254,
          customer: 'cus_1',
          livemode: false,
          metadata: {},
          type: 'card'
        },
        type: 'card_error'
      },
      livemode: false,
      metadata: {},
      next_action: nil,
      on_behalf_of: nil,
      payment_method: nil,
      payment_method_options: { card: { request_three_d_secure: 'automatic' } },
      payment_method_types: ['card'],
      receipt_email: nil,
      review: nil,
      setup_future_usage: nil,
      shipping: nil,
      source: nil,
      statement_descriptor: nil,
      status: status.to_s,
      transfer_data: {
        destination: 'ma_1'
      },
      transfer_group: nil
    }
  end

  def basic_setup_intent(code: 'card_declined', decline_code: 'do_not_honor')
    {
      id: 'seti_1FJEY2GK3Gnpfa3OloLFhpiV',
      object: 'setup_intent',
      application: nil,
      cancellation_reason: nil,
      client_secret: 'seti_1FJEY2GK3Gnpfa3OloLFhpiV_secret_FosI3jo5pM0sXWNtJcK1YfGlqCuDq7F',
      created: 1568618578,
      customer: 'cus_9DPsU3LXXND065',
      description: nil,
      last_setup_error: {
        code: code,
        decline_code: decline_code,
        doc_url: 'https://stripe.com/docs/error-codes/card-declined',
        message: 'Your card was declined.',
        param: '',
        payment_method: {
          id: 'card_1BfuyGGK3Gnpfa3OrYYQhDNk',
          object: 'payment_method',
          billing_details: {
            address: {
              city: 'Some City',
              country: 'SWE',
              line1: 'first address line',
              line2: nil,
              postal_code: '181 56',
              state: ''
            },
            email: nil,
            name: 'Random guy',
            phone: nil
          },
          card: {
            brand: 'amex',
            checks: {
              address_line1_check: 'pass',
              address_postal_code_check: 'pass',
              cvc_check: nil
            },
            country: 'SE',
            exp_month: 1,
            exp_year: 2020,
            fingerprint: 'fingerprint',
            funding: 'credit',
            generated_from: nil,
            last4: '1234',
            three_d_secure_usage: {
              supported: false
            },
            wallet: nil
          },
          created: 1514919524,
          customer: 'cus_1',
          livemode: true,
          metadata: {
          },
          type: 'card'
        },
        type: 'card_error'
      },
      livemode: true,
      metadata: {
        exchange_order_id: 'exchange_test',
        buyer_id: 'buyer_id',
        buyer_type: 'user',
        seller_id: 'seller_id',
        seller_type: 'gallery',
        type: 'bn-mo',
        mode: 'offer'
      },
      next_action: nil,
      on_behalf_of: 'acct_1234',
      payment_method: nil,
      payment_method_options: {
        card: {
          request_three_d_secure: 'automatic'
        }
      },
      payment_method_types: [
        'card'
      ],
      status: 'requires_payment_method',
      usage: 'off_session'
    }
  end
  # rubocop:enable Metrics/MethodLength
end
