require 'rails_helper'
require 'support/gravity_helper'

describe OrderProcessor, type: :services do
  include_context 'include stripe helper'
  let(:buyer_id) { 'buyer1' }
  let(:seller_id) { 'seller1' }
  let(:order_mode) { Order::BUY }
  let(:order) do
    Fabricate(
      :order,
      mode: order_mode,
      buyer_id: buyer_id,
      fulfillment_type: Order::SHIP,
      credit_card_id: 'cc1',
      seller_id: seller_id,
      shipping_name: 'Fname Lname',
      shipping_address_line1: '12 Vanak St',
      shipping_address_line2: 'P 80',
      shipping_city: 'Tehran',
      shipping_postal_code: '02198',
      buyer_phone_number: '00123456',
      shipping_country: 'IR',
      items_total_cents: 1000_00
    )
  end
  let(:artwork) { gravity_v1_artwork(_id: 'a-1', current_version_id: '1') }
  let(:stub_artwork_request) { stub_request(:get, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1").to_return(status: 200, body: artwork.to_json) }
  let!(:line_item1) { Fabricate(:line_item, order: order, quantity: 1, list_price_cents: 1000_00, artwork_id: 'a-1', artwork_version_id: '1') }
  let(:line_item2) { Fabricate(:line_item, order: order, artwork_id: 'a2', quantity: 2) }
  let(:stub_line_item_1_gravity_deduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }) }
  let(:stub_line_item_1_gravity_undeduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { undeduct: 1 }) }
  let(:stub_line_item_2_gravity_deduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a2/inventory").with(body: { deduct: 2 }) }
  let(:stub_line_item_2_gravity_undeduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a2/inventory").with(body: { undeduct: 2 }) }

  # TODO: Add currency to graphql_response
  let(:debit_commission_exemption_gravity_response) { { "data" => { "debitCommissionExemption" => { "amountOfExemptGmvOrError" => { "amountMinor" => 1000 } } } } }
  let(:stub_debit_commission_exemption_gravity) { stub_request(:put, "#{Rails.application.config_for(:gravity)['graphql_api_root']}").with(body: debit_commission_exemption_gravity_response ) }
  # something like
  allow(Gravity).to receive(:debit_commission_exemption).and_return(1000)
  
  # stubbed requests
  let(:gravity_partner) { gravity_v1_partner(_id: seller_id) }
  let(:stub_gravity_partner) { stub_request(:get, "#{Rails.application.config_for(:gravity)['api_v1_root']}/partner/seller1/all").to_return(body: gravity_partner.to_json) }
  let(:gravity_merchant_accounts) { [{ external_id: 'ma-1' }] }
  let(:stub_gravity_merchant_account_request) { stub_request(:get, "#{Rails.application.config_for(:gravity)['api_v1_root']}/merchant_accounts?partner_id=seller1").to_return(body: gravity_merchant_accounts.to_json) }
  let(:gravity_credit_card) { { external_id: 'cc_1', customer_account: { external_id: 'ca_1' } } }
  let(:stub_gravity_card_request) { stub_request(:get, "#{Rails.application.config_for(:gravity)['api_v1_root']}/credit_card/cc1").to_return(body: gravity_credit_card.to_json) }
  let(:offer) { nil }
  let(:order_processor) { OrderProcessor.new(order, buyer_id, offer) }

  describe 'set_totals!' do
    before do
      stub_gravity_partner
      stub_artwork_request
      order_processor.set_totals!
    end
    context 'buy order' do
      it 'sets correct totals on order' do
        expect(order.reload).to have_attributes(
          transaction_fee_cents: 29_30,
          commission_rate: 0.8,
          commission_fee_cents: 800_00,
          seller_total_cents: 170_70
        )
      end
      it 'sets correct totals on line items' do
        expect(line_item1.reload.commission_fee_cents).to eq 800_00
      end
      it 'sets totals_set' do
        expect(order_processor.instance_variable_get(:@totals_set)).to be true
      end
    end
    context 'offer order' do
      let(:order_mode) { Order::OFFER }
      let(:offer) { Fabricate(:offer, order: order, amount_cents: 1000_00, shipping_total_cents: 200_00, tax_total_cents: 100_00) }
      it 'sets correct totals on order' do
        expect(order.reload).to have_attributes(
          transaction_fee_cents: 38_00,
          commission_rate: 0.8,
          commission_fee_cents: 800_00,
          seller_total_cents: 462_00
        )
      end
      it 'does not set totals on line items' do
        expect(line_item1.reload.commission_fee_cents).to be_nil
      end
      it 'sets totals_set' do
        expect(order_processor.instance_variable_get(:@totals_set)).to be true
      end
    end
  end

  describe 'reset_totals!' do
    it 'resets totals on an order' do
      order.update!(
        transaction_fee_cents: 38_00,
        commission_rate: 0.8,
        commission_fee_cents: 800_00,
        seller_total_cents: 462_00
      )
      order_processor.reset_totals!
      expect(order.reload).to have_attributes(
        transaction_fee_cents: nil,
        commission_rate: nil,
        commission_fee_cents: nil,
        seller_total_cents: nil
      )
    end
    it 'sets totals_set' do
      expect(order_processor.instance_variable_get(:@totals_set)).to be false
    end
  end

  describe 'revert!' do
    it 'undeducts inventory if there are deducted inventories' do
      order_processor.instance_variable_set(:@deducted_inventory, [line_item1, line_item2])
      stub_line_item_1_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      order_processor.revert!
      expect(stub_line_item_1_gravity_undeduct).to have_been_requested
      expect(stub_line_item_2_gravity_undeduct).to have_been_requested
    end
    it 'resets totals if totals were set on the orders' do
      order.update!(
        transaction_fee_cents: 38_00,
        commission_rate: 0.8,
        commission_fee_cents: 800_00,
        seller_total_cents: 462_00
      )
      order_processor.instance_variable_set(:@totals_set, true)
      order_processor.revert!
      expect(order.reload).to have_attributes(
        transaction_fee_cents: nil,
        commission_rate: nil,
        commission_fee_cents: nil,
        seller_total_cents: nil
      )
    end
    it 'it reverts submitted order to pending' do
      order_processor.instance_variable_set(:@deducted_inventory, [])
      order.submit!
      original_state_expires_at = order.reload.state_expires_at
      order_processor.instance_variable_set(:@state_changed, true)
      order_processor.instance_variable_set(:@original_state_expires_at, original_state_expires_at)
      order_processor.revert!
      expect(order.reload).to have_attributes(state: Order::PENDING, state_expires_at: original_state_expires_at)
      expect(order_processor.instance_variable_get(:@state_changed)).to eq false
    end
    it 'it reverts approved order to pending' do
      order.submit!
      order.approve!
      original_state_expires_at = order.reload.state_expires_at
      order_processor.instance_variable_set(:@state_changed, true)
      order_processor.instance_variable_set(:@original_state_expires_at, original_state_expires_at)
      order_processor.revert!
      expect(order.reload).to have_attributes(state: Order::SUBMITTED, state_expires_at: original_state_expires_at)
      expect(order_processor.instance_variable_get(:@state_changed)).to eq false
    end
    it 'it reverts debit commission exemption' do
      # TODO: Add currency to graphql_response
      graphql_response =  { "totalRemainingGmvOrError" => { "amountMinor" => 1000 } } 
      allow (Gravity).to receive(credit_commission_exemption).and_return(graphql_response) 
      # TODO: add reversion test here, maybe expect Gravity.credit_commission_exemption to be called with the amount debited
    end
  end

  describe 'failed_payment?' do
    it 'returns true when transaction is failed' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, status: Transaction::FAILURE))
      expect(order_processor.failed_payment?).to be true
    end
    it 'returns false when transaction was successful' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, status: Transaction::SUCCESS))
      expect(order_processor.failed_payment?).to be false
    end
  end

  describe 'requires_action?' do
    it 'returns true when transaction requires action' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, status: Transaction::REQUIRES_ACTION))
      expect(order_processor.requires_action?).to be true
    end
    it 'returns false when transaction was successful' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, status: Transaction::SUCCESS))
      expect(order_processor.requires_action?).to be false
    end
  end

  describe 'action_data' do
    it 'returns true when transaction requires action' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, status: Transaction::REQUIRES_ACTION, payload: { 'client_secret' => 'super_secret' }))
      expect(order_processor.action_data).to eq(client_secret: 'super_secret')
    end
  end

  describe 'valid?' do
    it 'returns false and sets error missing shipping info' do
      order.update!(fulfillment_type: nil)
      expect(order_processor.valid?).to eq false
      expect(order_processor.validation_error).to eq :missing_required_info
    end

    it 'returns false and sets error when missing payment info' do
      order.update!(credit_card_id: nil)
      expect(order_processor.valid?).to eq false
      expect(order_processor.validation_error).to eq :missing_required_info
    end

    it 'returns false and sets error if you try to process an order that was paid for by wire transfer' do
      order.update!(payment_method: Order::WIRE_TRANSFER)
      expect(order_processor.valid?).to eq false
      expect(order_processor.validation_error).to eq :unsupported_payment_method
    end

    context 'missing credit card info' do
      let(:gravity_credit_card) { { external_id: nil } }
      before do
        stub_gravity_card_request
      end

      it 'returns false and sets error' do
        expect(order_processor.valid?).to eq false
        expect(order_processor.validation_error).to eq :credit_card_missing_external_id
        expect(stub_gravity_card_request).to have_been_requested
      end
    end
  end

  describe 'deduct_inventory' do
    before do
      line_item2
    end
    it 'returns true when fully deducted inventory' do
      stub_line_item_1_gravity_deduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_deduct.to_return(status: 200, body: {}.to_json)
      expect(order_processor.deduct_inventory).to be true
      expect(stub_line_item_1_gravity_deduct).to have_been_requested
      expect(stub_line_item_2_gravity_deduct).to have_been_requested
    end
    it 'returns false on insufficient inventory' do
      stub_line_item_1_gravity_deduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_deduct.to_return(status: 400, body: {}.to_json)
      expect(order_processor.deduct_inventory).to be false
      expect(stub_line_item_1_gravity_deduct).to have_been_requested
      expect(stub_line_item_2_gravity_deduct).to have_been_requested
    end
  end

  describe 'undedudct_inventory!' do
    before do
      order_processor.instance_variable_set(:@deducted_inventory, [line_item1, line_item2])
    end
    it 'calls undeduct for line items' do
      stub_line_item_1_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      order_processor.undeduct_inventory!
      expect(stub_line_item_1_gravity_undeduct).to have_been_requested
      expect(stub_line_item_2_gravity_undeduct).to have_been_requested
    end
  end

  describe 'store_transaction' do
    it 'stores transaction on the order' do
      transaction = Transaction.new(status: Transaction::SUCCESS, transaction_type: Transaction::HOLD)
      order_processor.instance_variable_set(:@transaction, transaction)
      expect { order_processor.store_transaction }.to change(order.transactions, :count).by(1)
    end
    it 'stores external_id on the order when transaction was successful' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, order: order, external_id: 'pi_1', status: Transaction::SUCCESS))
      order_processor.store_transaction
      expect(order.reload.external_charge_id).to eq 'pi_1'
    end
    it 'stores external_id on the order when transaction requires action' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, order: order, external_id: 'pi_1', status: Transaction::REQUIRES_ACTION))
      order_processor.store_transaction
      expect(order.reload.external_charge_id).to eq 'pi_1'
    end
    it 'does not store external_id on the order when transaction failed' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, order: order, external_id: 'pi_1', status: Transaction::FAILURE))
      order_processor.store_transaction
      expect(order.reload.external_charge_id).to be_nil
    end
    it 'does not store external_id on the order when off_session transaction requires action' do
      order_processor.instance_variable_set(:@transaction, Fabricate(:transaction, order: order, external_id: 'pi_1', status: Transaction::REQUIRES_ACTION))
      order_processor.store_transaction(true)
      expect(order.reload.external_charge_id).to be_nil
    end
  end

  describe 'on success' do
  end

  describe '#hold' do
    before do
      stub_artwork_request
      stub_gravity_card_request
      stub_gravity_merchant_account_request
      stub_gravity_partner
    end
    context 'failed hold' do
      before do
        prepare_payment_intent_create_failure(status: 'requires_payment_method', charge_error: { code: 'card_declined', decline_code: 'do_not_honor', message: 'The card was declined' })
        order_processor.hold
      end

      it 'sets processor transaction' do
        expect(order_processor.transaction.failure_code).to eq 'card_declined'
      end
    end

    context 'hold requires action' do
      before do
        prepare_payment_intent_create_failure(status: 'requires_action')
        order_processor.hold
      end

      it 'sets processor transaction' do
        expect(order_processor.transaction.requires_action?).to be true
      end

      it 'returns true for requires_action?' do
        expect(order_processor.requires_action?).to be true
      end

      it 'returns action_data' do
        expect(order_processor.action_data).to match(client_secret: 'pi_test1')
      end
    end

    context 'successful hold' do
      before do
        prepare_payment_intent_create_success(amount: 20_00)
        order_processor.hold
      end

      it 'sets order_processor.transaction' do
        expect(order_processor.transaction).to have_attributes(status: Transaction::SUCCESS, transaction_type: Transaction::HOLD)
      end
    end
  end

  describe '#charge' do
    before do
      stub_artwork_request
      stub_gravity_card_request
      stub_gravity_merchant_account_request
      stub_gravity_partner
    end
    context 'failed charge' do
      before do
        prepare_payment_intent_create_failure(status: 'requires_payment_method', charge_error: { code: 'card_declined', decline_code: 'do_not_honor', message: 'The card was declined' })
        order_processor.charge
      end
      it 'sets order_processor.transaction' do
        expect(order_processor.transaction).to have_attributes(failure_code: 'card_declined', decline_code: 'do_not_honor')
      end
    end

    context 'successful charge' do
      before do
        prepare_payment_intent_create_success(amount: 20_00)
        order_processor.charge
      end

      it 'sets order_processor.transaction' do
        expect(order_processor.transaction).to have_attributes(status: Transaction::SUCCESS)
      end
    end
    it 'sets off_session to false by default' do
      expect_any_instance_of(PaymentService).to receive(:immediate_capture).with(hash_including(off_session: false))
      order_processor.charge
    end
    it 'overrides off_session when passed to method' do
      expect_any_instance_of(PaymentService).to receive(:immediate_capture).with(hash_including(off_session: true))
      order_processor.charge(true)
    end
  end

  describe 'apply_commission_exemption' do
    before do
      stub_gravity_partner
      stub_artwork_request
      order_processor.set_totals!
    end
    context 'on success' do
      it 'updates order with new commission amount' do
        exemption = order_processor.apply_commission_exemption(100_00)
        # Quick maths: we've gone from a 1000_00 order (the full amount) with 80% commission to a 900_00 order (because 100_00 is exempt) with 80% commission, so 900 x .8 = 720
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be true
        expect(order.commission_fee_cents).to eq 720_00
        expect(order.seller_total_cents).to eq 250_70
      end
    end

    it 'doesn\'t change commission when exemption is 0' do
      exemption = order_processor.apply_commission_exemption(0)
      expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
      expect(order.commission_fee_cents).to eq 800_00
      expect(order.seller_total_cents).to eq 170_70
    end

  end

  describe 'debit_commission_exemption' do
    before do
      stub_gravity_partner
      stub_artwork_request
      order_processor.set_totals!
    end
    context 'on success' do
      it 'calls apply_commission_exemption' do
        stub_debit_commission_exemption_gravity
        expect(order_processor).to receive(:apply_commission_exemption).with(10_00)
        order_processor.debit_commission_exemption("test debit")
      end
    end

    context 'on failure' do
      it 'does not alter commission' do
        exemption = order_processor.debit_commission_exemption("test debit")
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
        expect(order.commission_fee_cents).to eq 800_00
      end
    end
  end
end
