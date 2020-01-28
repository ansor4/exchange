require 'rails_helper'
require 'support/gravity_helper'

describe PaymentService, type: :services do
  include_context 'include stripe helper'
  let(:order) do
    Fabricate(
      :order,
      buyer_total_cents: 20_00,
      seller_total_cents: 10_00,
      currency_code: 'usd',
      external_charge_id: 'pi_1',
      shipping_address_line1: '123 nowhere st',
      shipping_address_line2: 'apt 321',
      shipping_postal_code: '312',
      shipping_city: 'ny',
      shipping_country: 'US',
      shipping_region: 'NY',
      shipping_name: 'Homer',
      fulfillment_type: Order::SHIP
    )
  end
  let!(:line_items) { [Fabricate(:line_item, order: order, artwork_id: 'artwork-1')] }
  let(:credit_card) { { external_id: 'cc_1', customer_account: { external_id: 'ca_1' } } }
  let(:merchant_account) { { external_id: 'ma-1' } }

  let(:service) { PaymentService.new(order) }

  let(:stripe_call_params) do
    {
      amount: 20_00,
      currency: 'USD',
      description: 'INVOICING-DE via Artsy',
      payment_method_types: ['card'],
      payment_method: 'cc_1',
      customer: 'ca_1',
      on_behalf_of: 'ma-1',
      transfer_data: {
        destination: 'ma-1',
        amount: 10_00
      },
      transfer_group: order.id,
      off_session: false,
      metadata: {
        artist_ids: 'artist-id',
        artist_names: 'BNMOsy',
        buyer_id: order.buyer_id,
        buyer_type: 'user',
        exchange_order_id: order.id,
        mode: order.mode,
        seller_id: order.seller_id,
        seller_type: 'gallery',
        type: 'bn-mo'
      },
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
    }
  end

  before do
    allow(Gravity).to receive_messages(
      fetch_partner: gravity_v1_partner,
      get_merchant_account: merchant_account,
      get_credit_card: credit_card,
      get_artwork: gravity_v1_artwork
    )
  end

  describe '#hold' do
    it 'calls stripe with expected values' do
      expect(Stripe::PaymentIntent).to receive(:create).with(stripe_call_params).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      service.hold
    end

    it "authorizes a charge on the user's credit card" do
      prepare_payment_intent_create_success(amount: 20_00)
      transaction = service.hold
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
      transaction = service.hold
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
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
      transaction = service.hold
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
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

  describe '#immediate_capture' do
    it 'calls stripe with expected values' do
      expect(Stripe::PaymentIntent).to receive(:create).with(stripe_call_params.merge(capture_method: 'automatic')).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      service.immediate_capture(off_session: false)
    end

    it 'overrides off_session when passed in' do
      expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(off_session: true)).and_return(double(id: 'pi_1', payment_method: 'cc_1', amount: 123, status: 'requires_capture', to_h: {}))
      service.immediate_capture(off_session: true)
    end

    it 'returns correct transaction' do
      prepare_payment_intent_create_success(amount: 20_00)
      transaction = service.immediate_capture(off_session: false)
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
      transaction = service.immediate_capture(off_session: false)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
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
      transaction = service.immediate_capture(off_session: false)
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
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

    it 'returns failed transaction if payment_intent cannot be created (restricted partner account)' do
      prepare_payment_intent_create_failure(status: 'testmode_charges_only', capture: true, charge_error: { code: 'testmode_charges_only', decline_code: 'testmode_charges_only', message: 'Connected account is not setup.' })
      transaction = service.immediate_capture(off_session: false)
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        transaction_type: Transaction::CAPTURE,
        status: Transaction::FAILURE,
        failure_code: 'testmode_charges_only'
      )
    end
  end

  describe '#confirm_payment_intent' do
    it 'returns failed transaction if payment_intent is not in expected state' do
      mock_retrieve_payment_intent(status: 'requires_action')
      transaction = service.confirm_payment_intent
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        transaction_type: Transaction::CONFIRM,
        status: Transaction::REQUIRES_ACTION,
        failure_code: 'cannot_confirm'
      )
    end

    it 'confirms the payment intent and stores transaction' do
      prepare_payment_intent_confirm_success
      transaction = service.confirm_payment_intent
      expect(transaction).to have_attributes(
        external_id: 'pi_1',
        external_type: Transaction::PAYMENT_INTENT,
        transaction_type: Transaction::CONFIRM,
        status: Transaction::SUCCESS
      )
    end

    it 'confirms the payment intent and stores failed transaction' do
      prepare_payment_intent_confirm_failure(charge_error: { code: 'capture_charge', decline_code: 'do_not_honor', message: 'The card was declined' })
      transaction = service.confirm_payment_intent
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

  describe '#capture_hold' do
    it 'captures a payment_intent' do
      prepare_payment_intent_capture_success(amount: 20_00)
      transaction = service.capture_hold
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
      transaction = service.capture_hold
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

    it 'alters transfer amount on capture with transfer data param' do
      prepare_payment_intent_capture_update_transfer_data_success(amount: 20_00, transfer_amount: 15_00)
      transaction = service.capture_hold
      expect(transaction).to have_attributes(
        external_type: Transaction::PAYMENT_INTENT,
        amount_cents: 20_00,
        transaction_type: Transaction::CAPTURE,
        source_id: 'cc_1',
        status: Transaction::SUCCESS,
        payload: { 'client_secret' => 'pi_test1', 'id' => 'pi_1', 'transfer_data' => { 'amount' => 1500 } }
      )
    end
  end

  describe '#refund_payment' do
    before do
      Fabricate(:transaction, order: order, external_id: order.external_charge_id, external_type: Transaction::PAYMENT_INTENT)
    end
    it 'refunds a charge for the full amount' do
      prepare_payment_intent_refund_success
      transaction = service.refund
      expect(transaction).to have_attributes(external_id: 're_1', transaction_type: Transaction::REFUND, status: Transaction::SUCCESS, payload: { 'id' => 're_1' })
    end
    it 'catches Stripe errors and returns a failed transaction' do
      prepare_payment_intent_refund_failure(code: 'processing_error', message: 'The card was declined', decline_code: 'failed_refund')
      transaction = service.refund
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

  describe '#metadata' do
    it 'includes all expected metadata' do
      metadata = service.send(:metadata)
      expect(metadata).to match(
        exchange_order_id: order.id,
        buyer_id: order.buyer_id,
        buyer_type: 'user',
        seller_id: order.seller_id,
        seller_type: 'gallery',
        type: 'bn-mo',
        mode: 'buy',
        artist_ids: 'artist-id',
        artist_names: 'BNMOsy'
      )
    end
  end
end
