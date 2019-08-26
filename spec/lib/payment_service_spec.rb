require 'rails_helper'
require 'support/gravity_helper'

describe PaymentService, type: :services do
  include_context 'include stripe helper'

  let(:currency_code) { 'usd' }
  let(:buyer_amount) { 20_00 }
  let(:seller_amount) { 10_00 }
  let(:credit_card) { { external_id: 'cc_1', customer_account: { external_id: 'ca_1' } } }
  let(:merchant_account) { { external_id: 'ma-1' } }
  let(:params) do
    {
      buyer_amount: buyer_amount,
      credit_card: credit_card,
      currency_code: currency_code,
      description: 'Gallery via Artsy',
      merchant_account: merchant_account,
      metadata: { this: 'is', a: 'test' },
      seller_amount: seller_amount
    }
  end

  let(:params_with_shipping) do
    params.merge(
      shipping_address: Address.new(address_line1: '123 nowhere st', address_line2: 'apt 321', postal_code: '312', city: 'ny', country: 'US', region: 'NY'),
      shipping_name: 'Homer'
    )
  end

  describe '#hold_payment' do
    it 'calls stripe with expected values' do
      expect(Stripe::PaymentIntent).to receive(:create).with(
        amount: buyer_amount,
        currency: currency_code,
        description: 'Gallery via Artsy',
        payment_method_types: ['card'],
        payment_method: 'cc_1',
        customer: 'ca_1',
        on_behalf_of: 'ma-1',
        transfer_data: {
          destination: 'ma-1',
          amount: seller_amount
        },
        off_session: false,
        metadata: { this: 'is', a: 'test' },
        capture_method: 'manual',
        confirm: true,
        setup_future_usage: 'off_session',
        confirmation_method: 'manual',
        shipping: {
          address: {
            line1: '123 nowhere st',
            line2: 'apt 321',
            city: 'ny',
            state: 'NY',
            postal_code: '312',
            country: 'US'
          },
          name: 'Homer'
        }
      ).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      PaymentService.hold_payment(params_with_shipping)
    end

    it "authorizes a charge on the user's credit card" do
      prepare_payment_intent_create_success(amount: 20_00)
      transaction = PaymentService.hold_payment(params)
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
        source_id: 'cc_1',
        status: Transaction::SUCCESS,
        transaction_type: Transaction::HOLD,
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        payload: { 'client_secret' => 'pi_test1', 'id' => 'pi_1' }
      )
    end
    it 'returns transaction for requires_action' do
      prepare_payment_intent_create_failure(status: 'requires_action')
      transaction = PaymentService.hold_payment(params)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: buyer_amount,
        source_id: 'cc_1',
        destination_id: 'ma-1',
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        transaction_type: Transaction::HOLD,
        status: Transaction::REQUIRES_ACTION
      )
      expect(transaction.payload).to match('client_secret' => 'pi_test1', 'id' => 'pi_1')
    end

    it 'returns failed attempt transaction' do
      prepare_payment_intent_create_failure(status: 'requires_payment_method', capture: false, charge_error: { code: 'card_declined', decline_code: 'do_not_honor', message: 'The card was declined' })
      transaction = PaymentService.hold_payment(params)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: buyer_amount,
        source_id: 'cc_1',
        destination_id: 'ma_1',
        failure_code: 'card_declined',
        failure_message: 'Your card was declined.',
        decline_code: 'do_not_honor',
        transaction_type: Transaction::HOLD,
        status: Transaction::FAILURE
      )
      expect(transaction.payload).not_to be_nil
    end
  end

  describe '#capture_without_hold' do
    it 'calls stripe with expected values' do
      expect(Stripe::PaymentIntent).to receive(:create).with(
        amount: buyer_amount,
        currency: currency_code,
        description: 'Gallery via Artsy',
        payment_method_types: ['card'],
        payment_method: 'cc_1',
        customer: 'ca_1',
        on_behalf_of: 'ma-1',
        transfer_data: {
          destination: 'ma-1',
          amount: seller_amount
        },
        off_session: false,
        metadata: { this: 'is', a: 'test' },
        capture_method: 'automatic',
        confirm: true,
        setup_future_usage: 'off_session',
        confirmation_method: 'manual',
        shipping: {
          address: {
            line1: '123 nowhere st',
            line2: 'apt 321',
            city: 'ny',
            state: 'NY',
            postal_code: '312',
            country: 'US'
          },
          name: 'Homer'
        }
      ).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      PaymentService.capture_without_hold(params_with_shipping)
    end

    it 'overrides off_session when passed in' do
      expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(off_session: true)).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      PaymentService.capture_without_hold(params_with_shipping.merge(off_session: true))
    end

    it "authorizes a charge on the user's credit card" do
      prepare_payment_intent_create_success(amount: 20_00)
      transaction = PaymentService.capture_without_hold(params)
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
        source_id: 'cc_1',
        status: Transaction::SUCCESS,
        transaction_type: Transaction::CAPTURE,
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        payload: { 'client_secret' => 'pi_test1', 'id' => 'pi_1' }
      )
    end
    it 'returns transaction for requires_action' do
      prepare_payment_intent_create_failure(status: 'requires_action')
      transaction = PaymentService.capture_without_hold(params)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: buyer_amount,
        source_id: 'cc_1',
        destination_id: 'ma-1',
        failure_code: nil,
        failure_message: nil,
        decline_code: nil,
        transaction_type: Transaction::CAPTURE,
        status: Transaction::REQUIRES_ACTION
      )
      expect(transaction.payload).to match('client_secret' => 'pi_test1', 'id' => 'pi_1')
    end

    it 'returns failed attempt transaction' do
      prepare_payment_intent_create_failure(status: 'requires_payment_method', capture: false, charge_error: { code: 'card_declined', decline_code: 'do_not_honor', message: 'The card was declined' })
      transaction = PaymentService.capture_without_hold(params)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: buyer_amount,
        source_id: 'cc_1',
        destination_id: 'ma_1',
        failure_code: 'card_declined',
        failure_message: 'Your card was declined.',
        decline_code: 'do_not_honor',
        transaction_type: Transaction::CAPTURE,
        status: Transaction::FAILURE
      )
      expect(transaction.payload).not_to be_nil
    end
  end

  describe '#confirm_payment_intent' do
    it 'raises error if payment_intent not in expected state' do
      mock_retrieve_payment_intent(status: 'requires_action')
      expect { PaymentService.confirm_payment_intent('pi_1') }.to raise_error(Errors::ProcessingError)
    end
    it 'confirms the payment intent and stores transaction' do
      prepare_payment_intent_confirm_success
      transaction = PaymentService.confirm_payment_intent('pi_1')
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        transaction_type: Transaction::CONFIRM,
        status: Transaction::SUCCESS
      )
    end
    it 'confirms the payment intent and stores failed transaction' do
      prepare_payment_intent_confirm_failure(charge_error: { code: 'capture_charge', decline_code: 'do_not_honor', message: 'The card was declined' })
      transaction = PaymentService.confirm_payment_intent('pi_1')
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        failure_code: 'capture_charge',
        failure_message: 'Your card was declined.',
        decline_code: 'do_not_honor',
        status: Transaction::FAILURE
      )
    end
  end

  describe '#capture_authorized_hold' do
    it 'captures a payment_intent' do
      prepare_payment_intent_capture_success(amount: 20_00)
      transaction = PaymentService.capture_authorized_hold('pi_1')
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
        transaction_type: Transaction::CAPTURE,
        source_id: 'cc_1',
        status: Transaction::SUCCESS,
        payload: { 'client_secret' => 'pi_test1', 'id' => 'pi_1' }
      )
    end

    it 'stores failures on transaction' do
      prepare_payment_intent_capture_failure(charge_error: { code: 'capture_charge', decline_code: 'do_not_honor', message: 'The card was declined' })
      transaction = PaymentService.capture_authorized_hold('pi_1')
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        failure_code: 'capture_charge',
        failure_message: 'Your card was declined.',
        decline_code: 'do_not_honor',
        transaction_type: Transaction::CAPTURE,
        status: Transaction::FAILURE
      )
      expect(transaction.payload).not_to be_nil
    end
  end

  describe '#refund_payment' do
    it 'refunds a charge for the full amount' do
      prepare_payment_intent_refund_success
      transaction = PaymentService.refund_payment('pi_1')
      expect(transaction).to have_attributes(external_id: 're_1', transaction_type: Transaction::REFUND, status: Transaction::SUCCESS, payload: { 'id' => 're_1' })
    end
    it 'catches Stripe errors and returns a failed transaction' do
      prepare_payment_intent_refund_failure(code: 'processing_error', message: 'The card was declined', decline_code: 'failed_refund')
      transaction = PaymentService.refund_payment('pi_1')
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        failure_code: 'processing_error',
        failure_message: 'The card was declined',
        decline_code: 'failed_refund',
        transaction_type: Transaction::REFUND,
        status: Transaction::FAILURE
      )
      expect(transaction.payload).not_to be_nil
    end
  end
end
