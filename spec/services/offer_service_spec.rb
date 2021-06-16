require 'rails_helper'
require 'support/gravity_helper'

describe OfferService, type: :services do
  describe '#create_pending_offer!' do
    let(:user_id) { 'user-id' }
    let(:amount_cents) { 200 }
    let(:note) { nil }
    let(:order_mode) { Order::OFFER }
    let(:state) { Order::PENDING }
    let(:state_reason) { nil }
    let(:order) { Fabricate(:order, seller_id: user_id, seller_type: Order::USER, state: state, state_reason: state_reason, mode: order_mode) }
    let!(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 500) }
    let(:call_service) { OfferService.create_pending_offer(order, amount_cents: amount_cents, note: note, from_id: user_id, from_type: Order::USER, creator_id: user_id) }

    context 'Buy Order' do
      let(:order_mode) { Order::BUY }
      it 'raises error' do
        expect { call_service }.to raise_error do |e|
          expect(e.type).to eq :validation
          expect(e.code).to eq :cannot_offer
        end
      end
    end

    context 'Offer Order' do
      it 'creates offer' do
        expect { call_service }.to change(order.offers, :count).by(1)
        offer = order.offers.first
        expect(offer.amount_cents).to eq 2_00
        expect(offer.from_id).to eq user_id
        expect(offer.from_type).to eq Order::USER
        expect(offer.creator_id).to eq user_id
        expect(offer.note).to eq nil
      end

      it 'does not update order totals and state' do
        call_service
        expect(order.reload.state).to eq state
        expect(order.last_offer).to be_nil
        expect(order.items_total_cents).to eq nil
      end
    end
  end

  describe '#submit_order_with_offer' do
    include_context 'include stripe helper'
    let(:buyer_id) { 'user-id' }
    let(:seller_id) { 'partner-1' }
    let(:order_mode) { Order::OFFER }
    let(:order_state) { Order::PENDING }
    let(:offer_submitted_at) { nil }
    let(:shipping_info) do
      {
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'Tehran',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_country: 'IR',
        fulfillment_type: Order::SHIP
      }
    end

    let(:artwork) { gravity_v1_artwork(_id: 'a-1', current_version_id: '1') }
    let(:line_item_artwork_version) { artwork[:current_version_id] }
    let(:credit_card_id) { 'grav_c_id1' }
    let(:credit_card) { { external_id: 'cc-1', customer_account: { external_id: 'cus-1' }, deactivated_at: nil } }
    let(:seller_merchant_account) { { external_id: 'ma-1' } }
    let(:order) { Fabricate(:order, buyer_id: buyer_id, seller_id: seller_id, mode: order_mode, state: order_state, credit_card_id: credit_card_id, **shipping_info) }
    let!(:offer) { Fabricate(:offer, order: order, submitted_at: offer_submitted_at, amount_cents: 1000_00, tax_total_cents: 20_00, shipping_total_cents: 30_00, creator_id: buyer_id, from_id: buyer_id) }
    let!(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: artwork[:_id], artwork_version_id: line_item_artwork_version, quantity: 2) }
    let(:call_service) { OfferService.submit_order_with_offer(offer, user_id: buyer_id) }

    describe 'failed process' do
      before do
        order.update!(last_offer: offer)
        expect(OfferEvent).not_to receive(:delay_post)
        expect(OrderFollowUpJob).not_to receive(:perform_later)
        expect(OfferRespondReminderJob).not_to receive(:perform_later)
      end

      context 'without shipping info' do
        let(:shipping_info) { {} }
        it 'raises missing_required_info error' do
          expect { call_service }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :missing_required_info
          end
        end
      end

      context 'without payment info' do
        let(:credit_card_id) { nil }
        it 'raises missing_required_info error' do
          expect { call_service }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :missing_required_info
          end
        end
      end

      context 'artwork version mismatch' do
        let(:line_item_artwork_version) { 'some-other-version' }
        it 'raises artwork_version_mismatch error' do
          expect(Gravity).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
          dd_statsd = stub_ddstatsd_instance
          expect(dd_statsd).to receive(:increment).with('submit.artwork_version_mismatch')
          expect { call_service }.to raise_error do |e|
            expect(e.type).to eq :processing
            expect(e.code).to eq :artwork_version_mismatch
          end
        end
      end

      context 'Buy order' do
        let(:order_mode) { Order::BUY }
        it 'raises cant_submit error' do
          expect { call_service }.to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :cant_submit
          end
        end
      end

      Order::STATES.reject { |s| [Order::CANCELED, Order::PENDING].include? s }.each do |state|
        context "#{state} order" do
          let(:order_state) { state }
          before do
            allow(Gravity).to receive_messages(
              get_artwork: artwork,
              fetch_partner: gravity_v1_partner,
              get_credit_card: credit_card,
              get_merchant_account: seller_merchant_account
            )
            prepare_setup_intent_create
          end
          it 'raises invalid_state error' do
            expect { call_service }.to raise_error do |e|
              expect(e.type).to eq :validation
              expect(e.code).to eq :invalid_state
            end
          end
        end
      end

      describe '#assert_credit_card!' do
        before do
          allow(Gravity).to receive(:get_artwork).with(artwork[:_id]).and_return(artwork)
        end
        it 'raises an error if the credit card does not have an external id' do
          allow(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: nil)
          expect { call_service }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_external_id
          end
        end

        it 'raises an error if the credit card does not have a customer account' do
          allow(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1')
          expect { call_service }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_customer
          end
        end

        it 'raises an error if the credit card does not have a customer account external id' do
          allow(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { some_prop: 'some_val' }, deactivated_at: nil)
          expect { call_service }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_missing_customer
          end
        end

        it 'raises an error if the card is deactivated' do
          allow(Gravity).to receive(:get_credit_card).with(credit_card_id).and_return(id: 'cc-1', external_id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: 2.days.ago)
          expect { call_service }.to raise_error do |error|
            expect(error).to be_a(Errors::ValidationError)
            expect(error.code).to eq :credit_card_deactivated
          end
        end
      end
    end

    describe 'successful process' do
      before do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.submitted')
        allow(dd_statsd).to receive(:increment).with('offer.submit')
        allow(Gravity).to receive_messages(
          get_artwork: artwork,
          fetch_partner: gravity_v1_partner,
          get_credit_card: credit_card,
          get_merchant_account: seller_merchant_account
        )
        expect(OrderEvent).to receive(:delay_post).once.with(order, buyer_id)
        expect(OfferEvent).to receive(:delay_post).once.with(offer, OfferEvent::SUBMITTED)
        prepare_setup_intent_create
      end

      it 'submits offer and order' do
        expect do
          call_service
          expect(order.reload.state).to eq(Order::SUBMITTED)
          expect(offer.reload.submitted_at).not_to be_nil
        end.to change(order.state_histories, :count).by(1).and change(order.transactions, :count).by(1)
      end

      it 'queues related jobs' do
        call_service
        expect(OrderFollowUpJob).to have_been_enqueued
        expect(OfferRespondReminderJob).to have_been_enqueued.with(order.id, order.last_offer.id)
      end

      it 'updates orders last_offer' do
        call_service
        expect(order.reload.last_offer).to eq offer
      end

      it 'updates order totals' do
        call_service
        expect(order.commission_fee_cents).to eq offer.amount_cents * 0.8 # comes from gravity_v1_partner
        expect(order.shipping_total_cents).to eq 30_00
        expect(order.tax_total_cents).to eq 20_00
        expect(order.buyer_total_cents).to eq 1000_00 + 30_00 + 20_00
        expect(order.transaction_fee_cents).to eq(0)
      end
    end

    describe 'resubmitting with confirmed_setup_intent' do
      context 'succeeded setup_intent' do
        before do
          dd_statsd = stub_ddstatsd_instance
          allow(dd_statsd).to receive(:increment).with('order.submitted')
          allow(dd_statsd).to receive(:increment).with('offer.submit')
          allow(Gravity).to receive_messages(
            get_artwork: artwork,
            fetch_partner: gravity_v1_partner,
            get_credit_card: credit_card,
            get_merchant_account: seller_merchant_account
          )
          expect(OrderEvent).to receive(:delay_post).once.with(order, buyer_id)
          expect(OfferEvent).to receive(:delay_post).once.with(offer, OfferEvent::SUBMITTED)
          prepare_setup_intent_retrieve(status: 'succeeded')
        end
        it 'submits the order and offer' do
          expect do
            OfferService.submit_order_with_offer(offer, user_id: buyer_id, confirmed_setup_intent_id: 'si_1')
            expect(order.reload.state).to eq(Order::SUBMITTED)
            expect(offer.reload.submitted_at).not_to be_nil
          end.to change(order.state_histories, :count).by(1).and change(order.transactions, :count).by(1)
        end
      end
      context 'requires_action setup_intent' do
        before do
          allow(Gravity).to receive_messages(
            get_artwork: artwork,
            fetch_partner: gravity_v1_partner,
            get_credit_card: credit_card,
            get_merchant_account: seller_merchant_account
          )
          prepare_setup_intent_retrieve(status: 'requires_action')
        end
        it 'stores transaction and raises error' do
          expect do
            OfferService.submit_order_with_offer(offer, user_id: buyer_id, confirmed_setup_intent_id: 'si_1')
            expect(order.reload.state).to eq(Order::PENDING)
            expect(offer.reload.submitted_at).to be_nil
          end.to raise_error(Errors::PaymentRequiresActionError).and change(order.state_histories, :count).by(0).and change(order.transactions, :count).by(1)
          expect(order.transactions.first).to have_attributes(external_id: 'si_1', external_type: Transaction::SETUP_INTENT, transaction_type: Transaction::CONFIRM, status: Transaction::REQUIRES_ACTION)
        end
      end
    end
  end

  describe '#create_pending_counter_offer' do
    let(:offer_creator_id) { 'user-id' }
    let(:offer_from_id) { 'partner-id' }
    let(:offer_from_type) { Order::PARTNER }
    let(:order_mode) { Order::OFFER }
    let(:order) { Fabricate(:order, state: Order::SUBMITTED, mode: order_mode) }
    let(:line_item) { Fabricate(:line_item, order: order, list_price_cents: 2000_00, artwork_id: 'artwork-1', quantity: 2) }
    let(:current_offer) { Fabricate(:offer, order: order, amount_cents: 10000, submitted_at: 1.day.ago) }
    let(:note) { 'I want this art for free.' }

    before do
      order.line_items << line_item
    end

    context 'counter on last_offer' do
      before do
        order.update!(last_offer: current_offer)
      end
      it 'adds a new offer to order and does not updates last offer' do
        expect_any_instance_of(OfferTotals).to receive_messages(shipping_total_cents: 100, tax_total_cents: 200, should_remit_sales_tax: false)
        OfferService.create_pending_counter_offer(current_offer, amount_cents: 20000, note: note, from_id: offer_from_id, creator_id: offer_creator_id, from_type: offer_from_type)
        expect(order.offers.count).to eq(2)
        new_offer = order.offers.reject { |offer| offer.id == order.last_offer.id }.first
        expect(new_offer.amount_cents).to eq(20000)
        expect(new_offer.responds_to).to eq(current_offer)
        expect(new_offer.from_id).to eq(offer_from_id)
        expect(new_offer.creator_id).to eq(offer_creator_id)
        expect(new_offer.from_type).to eq(offer_from_type)
        expect(new_offer.submitted_at).to be_nil
        expect(new_offer.note).to eq(note)
      end

      it 'raises error for 0 offer amount' do
        expect { OfferService.create_pending_counter_offer(current_offer, amount_cents: 0, note: note, from_id: offer_from_id, creator_id: offer_creator_id, from_type: offer_from_type) }
          .to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :invalid_amount_cents
          end
      end

      it 'raises error for negative offer amount' do
        expect { OfferService.create_pending_counter_offer(current_offer, amount_cents: -10, note: note, from_id: offer_from_id, creator_id: offer_creator_id, from_type: offer_from_type) }
          .to raise_error do |e|
            expect(e.type).to eq :validation
            expect(e.code).to eq :invalid_amount_cents
          end
      end
    end

    context 'attempting to counter not the last offer' do
      let!(:another_offer) { Fabricate(:offer, order: order) }

      before do
        order.update!(last_offer: another_offer)
      end

      it 'raises a validation error' do
        expect {  OfferService.create_pending_counter_offer(current_offer, amount_cents: 20000, note: note, from_id: offer_from_id, creator_id: offer_creator_id, from_type: offer_from_type) }
          .to raise_error(Errors::ValidationError)
      end

      it 'does not change order and offers' do
        expect {  OfferService.create_pending_counter_offer(current_offer, amount_cents: 20000, note: note, from_id: offer_from_id, creator_id: offer_creator_id, from_type: offer_from_type) }.to raise_error(Errors::ValidationError)

        expect(order.reload.state).to eq(Order::SUBMITTED)
        expect(order.reload.offers.count).to eq(2)
      end
    end
  end

  describe '#submit_pending_offer' do
    let(:artwork) { gravity_v1_artwork }
    let(:buyer_id) { 'user-id' }
    let(:order_seller_id) { 'partner-1' }
    let(:order) { Fabricate(:order, mode: Order::OFFER, state: Order::SUBMITTED, seller_id: order_seller_id, seller_type: 'gallery', buyer_id: buyer_id, buyer_type: Order::USER) }
    let(:line_item) { Fabricate(:line_item, order: order, artwork_id: artwork[:_id]) }
    let(:current_offer) { Fabricate(:offer, order: order, from_id: order.seller_id, from_type: order.seller_type, amount_cents: 10000, submitted_at: 1.day.ago) }
    let(:new_offer) { Fabricate(:offer, order: order, from_id: order.buyer_id, from_type: order.buyer_type, amount_cents: 200_00, shipping_total_cents: 100_00, tax_total_cents: 50_00, responds_to: current_offer) }
    let(:call_service) { OfferService.submit_pending_offer(new_offer) }

    before do
      order.update!(last_offer: current_offer)
      order.line_items << line_item
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{order_seller_id}/all").and_return(gravity_v1_partner)
      allow(Adapters::GravityV1).to receive(:get).with("/artwork/#{line_item.artwork_id}").and_return(artwork)
    end

    context 'with counter on a submitted offer' do
      it 'submits the pending offer and updates last offer' do
        call_service
        expect(new_offer.submitted_at).not_to be_nil
      end

      it 'updates order last offer' do
        call_service
        expect(order.offers.count).to eq(2)
        expect(order.last_offer).to eq(new_offer)
        expect(order.last_offer.amount_cents).to eq(200_00)
        expect(order.last_offer.responds_to).to eq(current_offer)
      end

      it 'updates orders totals' do
        call_service
        expect(order.items_total_cents).to eq 200_00
        expect(order.shipping_total_cents).to eq 100_00
        expect(order.tax_total_cents).to eq 50_00
        expect(order.commission_fee_cents).to eq 200_00 * 0.8
        expect(order.buyer_total_cents).to eq 350_00
        expect(order.transaction_fee_cents).to eq(0)
        expect(order.seller_total_cents).to eq 350_00 - order.commission_fee_cents - order.transaction_fee_cents
      end

      it 'updates orders totals' do
        call_service
        expect(order.items_total_cents).to eq 200_00
        expect(order.shipping_total_cents).to eq 100_00
        expect(order.tax_total_cents).to eq 50_00
        expect(order.commission_fee_cents).to eq 200_00 * 0.8
        expect(order.buyer_total_cents).to eq 350_00
        expect(order.transaction_fee_cents).to eq(0)
        expect(order.seller_total_cents).to eq 350_00 - order.commission_fee_cents - order.transaction_fee_cents
      end

      it 'updates order state expiration' do
        Timecop.freeze(Date.new(2018, 12, 17)) do
          call_service
          expect(order.reload.state_expires_at).to eq Offer::EXPIRATION.from_now
        end
      end

      it 'instruments a counter offer' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('offer.submit')

        call_service

        expect(dd_statsd).to have_received(:increment).with('offer.submit')
      end

      it 'queues job for posting notification' do
        call_service
        expect(PostEventJob).to have_been_enqueued
      end
      it 'queues job for order follow up' do
        call_service
        expect(OrderFollowUpJob).to have_been_enqueued
      end
      context 'reminders' do
        it 'queues pending offer reminder' do
          call_service
          expect(OfferRespondReminderJob).to have_been_enqueued.with(order.id, order.last_offer.id)
        end
      end
    end

    context 'attempting to submit already submitted offer' do
      let(:new_offer) { Fabricate(:offer, order: order, amount_cents: 20000, responds_to: current_offer, submitted_at: 1.minute.ago, from_id: buyer_id, from_type: Order::USER) }
      it 'raises a validation error' do
        expect {  call_service }.to raise_error(Errors::ValidationError)
      end

      it 'does not instrument' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.create_pending_counter_offer')

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end
    end

    context 'attempting to submit someone elses offer' do
      let(:new_offer) { Fabricate(:offer, order: order, amount_cents: 20000, responds_to: current_offer, submitted_at: 1.minute.ago, from_id: 'al-pachino') }
      it 'raises a validation error' do
        expect {  call_service }
          .to raise_error(Errors::ValidationError)
      end

      it 'does not instrument' do
        dd_statsd = stub_ddstatsd_instance
        allow(dd_statsd).to receive(:increment).with('order.create_pending_counter_offer')

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end
    end

    context 'without enough inventory' do
      let(:artwork) { gravity_v1_artwork(inventory: { count: 0, unlimited: false }) }
      it 'raises a processing error' do
        expect { call_service }.to raise_error do |e|
          expect(e.type).to eq :processing
          expect(e.code).to eq :insufficient_inventory
        end
      end
    end

    context 'with unlimited inventory' do
      let(:artwork) { gravity_v1_artwork(inventory: { count: 0, unlimited: true }) }
      it 'submits the offer' do
        call_service
        expect(new_offer.submitted_at).not_to be_nil
      end
    end

    context 'with order on edition set' do
      before do
        line_item.update!(edition_set_id: 'edition-set-id')
      end
      it 'submits the offer' do
        call_service
        expect(new_offer.submitted_at).not_to be_nil
      end
    end

    context 'with order on wrong edition set' do
      before do
        line_item.update!(edition_set_id: 'random-edition-set')
      end
      it 'submits the offer' do
        expect { call_service }.to raise_error do |e|
          expect(e.type).to eq :validation
          expect(e.code).to eq :unknown_edition_set
        end
      end
    end
  end

  describe '#accept_offer' do
    let(:order) { Fabricate(:order, buyer_id: 'user_1', buyer_type: 'user', seller_id: 'gal_1', seller_type: 'gallery') }
    let(:seller_offer) { Fabricate(:offer, order: order, from_id: 'gal_1', from_type: 'gallery') }
    let(:buyer_offer) { Fabricate(:offer, order: order, from_id: 'user_1', from_type: 'user') }
    it 'calls charge with off_session true when the seller accepts an offer from the buyer' do
      order.update!(last_offer: buyer_offer)
      allow_any_instance_of(OrderProcessor).to receive_messages(
        valid?: true,
        advance_state: nil,
        deduct_inventory!: nil,
        set_totals!: nil,
        failed_payment?: false,
        store_transaction: nil,
        on_success: nil,
        charge: Fabricate(:transaction),
        debit_commission_exemption: nil
      )
      expect_any_instance_of(OrderProcessor).to receive(:charge).with(true)
      expect_any_instance_of(OrderProcessor).to receive(:store_transaction).with(true)
      OfferService.accept_offer(buyer_offer, 'gal_1')
    end
    it 'calls charge with off_session false when the buyer accepts an offer from the seller' do
      order.update!(last_offer: seller_offer)
      allow_any_instance_of(OrderProcessor).to receive_messages(
        valid?: true,
        advance_state: nil,
        deduct_inventory!: nil,
        set_totals!: nil,
        failed_payment?: false,
        store_transaction: nil,
        on_success: nil,
        debit_commission_exemption: nil
      )
      expect_any_instance_of(OrderProcessor).to receive(:charge).with(false)
      OfferService.accept_offer(seller_offer, 'user_1')
    end
    it 'calls charge with off_session false when the buyer accepts their own offer (new payment flow)' do
      order.update!(last_offer: buyer_offer)
      allow_any_instance_of(OrderProcessor).to receive_messages(
        valid?: true,
        advance_state: nil,
        deduct_inventory!: nil,
        set_totals!: nil,
        failed_payment?: false,
        store_transaction: nil,
        on_success: nil,
        debit_commission_exemption: nil
      )
      expect_any_instance_of(OrderProcessor).to receive(:charge).with(false)
      OfferService.accept_offer(buyer_offer, 'user_1')
    end

    context 'commission exemption' do
      it 'calls debit_commission_exemption' do
        order.update!(last_offer: seller_offer)
        allow_any_instance_of(OrderProcessor).to receive_messages(
          valid?: true,
          advance_state: nil,
          deduct_inventory!: nil,
          set_totals!: nil,
          failed_payment?: false,
          store_transaction: nil,
          on_success: nil
        )
        expect(Gravity).to receive(:debit_commission_exemption).with(partner_id: order.seller_id, amount_minor: order.items_total_cents, currency_code: order.currency_code, reference_id: order.id, notes: '')
        expect_any_instance_of(OrderProcessor).to receive(:charge).with(false)
        OfferService.accept_offer(seller_offer, 'user_1')
      end
    end
  end

  def stub_ddstatsd_instance
    dd_statsd = double(Datadog::Statsd)
    allow(Exchange).to receive(:dogstatsd).and_return(dd_statsd)

    dd_statsd
  end
end
