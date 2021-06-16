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
  let!(:line_item1) { Fabricate(:line_item, order: order, quantity: 1, list_price_cents: 1000_00, artwork_id: 'a-1', artwork_version_id: '1', sales_tax_cents: 0, shipping_total_cents: 0) }
  let(:line_item2) { Fabricate(:line_item, order: order, artwork_id: 'a2', quantity: 2) }
  let(:stub_line_item_1_gravity_deduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }) }
  let(:stub_line_item_1_gravity_undeduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { undeduct: 1 }) }
  let(:stub_line_item_2_gravity_deduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a2/inventory").with(body: { deduct: 2 }) }
  let(:stub_line_item_2_gravity_undeduct) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a2/inventory").with(body: { undeduct: 2 }) }

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
          transaction_fee_cents: 0,
          commission_rate: 0.8,
          commission_fee_cents: 800_00,
          seller_total_cents: 200_00
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
          transaction_fee_cents: 0,
          commission_rate: 0.8,
          commission_fee_cents: 800_00,
          seller_total_cents: 500_00
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
        transaction_fee_cents: 0,
        commission_rate: 0.8,
        commission_fee_cents: 800_00,
        seller_total_cents: 500_00
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
    let(:revert_reason) { 'revert reason' }
    it 'logs a warning' do
      expect(Rails.logger).to receive(:warn).with("Order #{order.id}/#{order.code} reverted. Reason: #{revert_reason}")
      order_processor.revert! revert_reason
    end
    it 'undeducts inventory if there are deducted inventories' do
      inventory_service = InventoryService.new(order)
      inventory_service.instance_variable_set(:@deducted_items, [line_item1, line_item2])
      order_processor.instance_variable_set(:@inventory_service, inventory_service)
      stub_line_item_1_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      order_processor.revert!
      expect(stub_line_item_1_gravity_undeduct).to have_been_requested
      expect(stub_line_item_2_gravity_undeduct).to have_been_requested
    end
    it 'resets totals if totals were set on the orders' do
      order.update!(
        transaction_fee_cents: 0,
        commission_rate: 0.8,
        commission_fee_cents: 800_00,
        seller_total_cents: 500_00
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
      order.submit!
      order.approve!
      order_processor.instance_variable_set(:@exempted_commission, true)

      expect(Gravity).to receive(:refund_commission_exemption).with(partner_id: order.seller_id, reference_id: order.id, notes: 'insufficient_inventory')
      order_processor.revert!('insufficient_inventory')
      expect(order_processor.instance_variable_get(:@exempted_commission)).to eq false
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

  describe 'deduct_inventory!' do
    before do
      line_item2
    end

    it 'does not raise an exception when fully deducted inventory' do
      stub_line_item_1_gravity_deduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_deduct.to_return(status: 200, body: {}.to_json)
      expect do
        order_processor.deduct_inventory!
      end.to_not raise_error
      expect(stub_line_item_1_gravity_deduct).to have_been_requested
      expect(stub_line_item_2_gravity_deduct).to have_been_requested
    end

    it 'raises an exception on insufficient inventory' do
      stub_line_item_1_gravity_deduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_deduct.to_return(status: 400, body: {}.to_json)
      expect do
        order_processor.deduct_inventory!
      end.to raise_error(Errors::InsufficientInventoryError)
      expect(stub_line_item_1_gravity_deduct).to have_been_requested
      expect(stub_line_item_2_gravity_deduct).to have_been_requested
    end

    it 'skips for inquiry orders' do
      order.impulse_conversation_id = '401'
      order_processor.deduct_inventory!
      expect(stub_line_item_1_gravity_deduct).to_not have_been_made
      expect(stub_line_item_2_gravity_deduct).to_not have_been_made
    end
  end

  describe 'undedudct_inventory!' do
    before do
      inventory_service = InventoryService.new(order)
      inventory_service.instance_variable_set(:@deducted_items, [line_item1, line_item2])
      order_processor.instance_variable_set(:@inventory_service, inventory_service)
    end

    it 'calls undeduct for line items' do
      stub_line_item_1_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      stub_line_item_2_gravity_undeduct.to_return(status: 200, body: {}.to_json)
      order_processor.undeduct_inventory!
      expect(stub_line_item_1_gravity_undeduct).to have_been_requested
      expect(stub_line_item_2_gravity_undeduct).to have_been_requested
    end

    it 'skips for inquiry orders' do
      order.impulse_conversation_id = '401'
      order_processor.undeduct_inventory!
      expect(stub_line_item_1_gravity_undeduct).to_not have_been_made
      expect(stub_line_item_2_gravity_undeduct).to_not have_been_made
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
    context 'with 0 commission exemption' do
      it 'returns nil' do
        expect(order_processor.apply_commission_exemption(0)).to be nil
      end
    end

    context 'with > 0 commission exemption' do
      let(:order_total) { Struct.new(:seller_total_cents, :commission_fee_cents) }
      before do
        allow(BuyOrderTotals).to receive(:new).and_return(order_total.new(5, 10))
        allow(OfferOrderTotals).to receive(:new).and_return(order_total.new(20, 30))
      end
      context 'with an order' do
        it 'initializes buy order totals and updates the order' do
          expect(order).to receive(:update!).with(seller_total_cents: 5, commission_fee_cents: 10)
          order_processor.apply_commission_exemption(10)
        end
      end

      context 'with an offer' do
        let(:order_mode) { Order::OFFER }
        let(:offer) { Fabricate(:offer, order: order, amount_cents: 1000_00, shipping_total_cents: 200_00, tax_total_cents: 100_00) }
        it 'initializes offer order totals and updates the order' do
          expect(order).to receive(:update!).with(seller_total_cents: 20, commission_fee_cents: 30)
          order_processor.apply_commission_exemption(10)
        end

        it 'does not set totals on line items' do
          order_processor.apply_commission_exemption(10)
          expect(line_item1.reload.commission_fee_cents).to be_nil
        end
      end
    end
  end

  describe 'debit_commission_exemption' do
    before do
      stub_gravity_partner
      stub_artwork_request
      order_processor.set_totals!
    end
    context 'on success' do
      it 'calls apply_commission_exemption if result has amount_minor' do
        allow(Gravity).to receive(:debit_commission_exemption).and_return(currency_code: 'USD', amount_minor: 10_00)
        expect(order_processor).to receive(:apply_commission_exemption).with(10_00)
        order_processor.debit_commission_exemption
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be true
      end

      it 'does not call apply_commission_exemption if result is missing amount_minor' do
        allow(Gravity).to receive(:debit_commission_exemption).and_return(foo: 'bar')
        expect(order_processor).not_to receive(:apply_commission_exemption)
        order_processor.debit_commission_exemption
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
      end
    end

    context 'failure' do
      it 'does not call apply_commission when error is raised' do
        allow(Gravity).to receive(:debit_commission_exemption).and_raise(GravityGraphql::GraphQLError)
        expect(Rails.logger).to receive(:error).with("Could not execute Gravity GraphQL query for order #{order.id}")
        order_processor.debit_commission_exemption
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
        expect(order.commission_fee_cents).to eq 800_00
      end

      it 'does not call apply_commission_exemption when response is nil' do
        allow(Gravity).to receive(:debit_commission_exemption).and_return(nil)
        expect(order_processor).not_to receive(:apply_commission_exemption)
        order_processor.debit_commission_exemption
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
      end

      it 'does not call apply_commission_exemption when response amount is 0' do
        allow(Gravity).to receive(:debit_commission_exemption).and_return(currency_code: 'USD', amount_minor: 0)
        expect(order_processor).not_to receive(:apply_commission_exemption)
        order_processor.debit_commission_exemption
        expect(order_processor.instance_variable_get(:@exempted_commission)).to be false
      end
    end
  end
end
