require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe Api::GraphqlController, type: :request do
  include_context 'include stripe helper'
  include_context 'GraphQL Client Helpers'
  describe 'make offer happy path' do
    let(:seller_id) { 'gravity-partner-id' }
    let(:buyer_id) { 'user-id1' }
    let(:buyer_shipping_address) do
      {
        name: 'Fname Lname',
        country: 'GB',
        city: 'Manchester',
        region: '',
        postalCode: 'EF3 4GH',
        phoneNumber: '+44 12 3456 7890',
        addressLine1: '1 Test Rd.'
      }
    end
    let(:buyer_credit_card) { { id: 'cc-1', user: { _id: buyer_id }, external_id: 'cc_1', customer_account: { external_id: 'ca_1' } } }
    let(:gravity_artwork) do
      gravity_v1_artwork(_id: 'a-1', price_currency: 'GBP', price_listed: 1000.00, edition_sets: [], domestic_shipping_fee_cents: 200_00, international_shipping_fee_cents: 300_00, location: { country: 'GB',
                                                                                                                                                                                                city: 'London',
                                                                                                                                                                                                address: '1 Fake St.',
                                                                                                                                                                                                postal_code: 'AB1 2CD' })
    end
    let(:gravity_partner) { { id: seller_id, artsy_collects_sales_tax: true, billing_location_id: '123abc', effective_commission_rate: 0.1 } }
    let(:seller_addresses) { [Address.new(city: 'London', country: 'GB', postal_code: 'SW3 4RY')] }
    let(:seller_merchant_account) { { external_id: 'ma-1' } }
    let(:buyer_client) { graphql_client(user_id: buyer_id, partner_ids: [], roles: 'user') }
    let(:seller_client) { graphql_client(user_id: 'partner_admin_id', partner_ids: [seller_id], roles: 'user') }
    let(:exemption) { { currency_code: 'GBP', amount_minor: 0 } }

    before do
      stub_tax_for_order(tax_amount: 100)
      allow(Gravity).to receive_messages(
        get_artwork: gravity_artwork,
        fetch_partner_locations: seller_addresses,
        fetch_partner: gravity_partner,
        get_credit_card: buyer_credit_card,
        deduct_inventory: nil,
        get_merchant_account: seller_merchant_account,
        debit_commission_exemption: exemption
      )
      prepare_payment_intent_create_success(amount: 900_00)
      prepare_setup_intent_create(status: 'succeeded')
    end

    it 'succeeds in the process of buyer offers -> seller counters -> buyer accepts' do
      # The first few actions here (up through a buyer submitting an initial offer)
      # are covered by the assertions in the make_offer_happy_path_spec and aren't repeated here.

      # Buyer creates the offer order
      buyer_client.execute(OfferQueryHelper::CREATE_OFFER_ORDER, input: { artworkId: gravity_artwork[:_id], quantity: 1 })

      order = Order.last

      # adds initial offer to order
      buyer_client.execute(OfferQueryHelper::ADD_OFFER_TO_ORDER, input: { orderId: order.id, amountCents: 500_00 })

      offer = Offer.last

      # Buyer sets shipping info
      buyer_client.execute(QueryHelper::SET_SHIPPING, input: { id: order.id.to_s, fulfillmentType: 'SHIP', shipping: buyer_shipping_address })

      # Buyer sets credit card
      buyer_client.execute(QueryHelper::SET_CREDIT_CARD, input: { id: order.id.to_s, creditCardId: buyer_credit_card[:id] })

      # Buyer submits offer order
      buyer_client.execute(OfferQueryHelper::SUBMIT_ORDER_WITH_OFFER, input: { offerId: offer.id.to_s })

      # Here we start making new assertions, as this is new behavior not tested by any
      # of our other integration tests.

      # Seller submits counteroffer
      expect do
        seller_client.execute(OfferQueryHelper::SELLER_COUNTER_OFFER, input: { offerId: offer.id.to_s, amountCents: 700_00 })
      end.to change(order.transactions, :count).by(0).and change(order.offers, :count).by(1)
      expect(order.reload).to have_attributes(
        state: Order::SUBMITTED,
        items_total_cents: 700_00,
        shipping_total_cents: 200_00,
        buyer_total_cents: 900_00,
        tax_total_cents: 0,
        commission_fee_cents: 70_00,
        transaction_fee_cents: 0,
        seller_total_cents: 830_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'GB',
        currency_code: 'GBP',
        credit_card_id: 'cc-1'
      )

      seller_counter = order.offers.order(created_at: :desc).first
      expect(seller_counter).to have_attributes(
        amount_cents: 700_00,
        shipping_total_cents: 200_00,
        tax_total_cents: 0,
        buyer_total_cents: 900_00
      )
      expect(seller_counter.submitted_at).to_not be_nil

      # Buyer accepts offer
      expect do
        buyer_client.execute(OfferQueryHelper::BUYER_ACCEPT_OFFER, input: { offerId: seller_counter.id.to_s })
      end.to change(order.transactions, :count).by(1)
      expect(order.reload).to have_attributes(
        state: Order::APPROVED,
        items_total_cents: 700_00,
        shipping_total_cents: 200_00,
        buyer_total_cents: 900_00,
        tax_total_cents: 0,
        commission_fee_cents: 70_00,
        transaction_fee_cents: 0,
        seller_total_cents: 830_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'GB',
        currency_code: 'GBP',
        credit_card_id: 'cc-1'
      )
      expect(order.transactions.order(created_at: :desc).first).to have_attributes(
        transaction_type: Transaction::CAPTURE,
        amount_cents: 900_00,
        status: Transaction::SUCCESS,
        source_id: 'cc_1'
      )

      # seller fulfills order
      expect do
        seller_client.execute(QueryHelper::FULFILL_ORDER, input:
          {
            id: order.id.to_s,
            fulfillment: {
              courier: 'fedex',
              trackingId: 'fedex-123',
              estimatedDelivery: '2018-12-15'
            }
          })
      end.to change(order.line_items.first.fulfillments, :count).by(1)
      expect(order.reload).to have_attributes(state: Order::FULFILLED)
      expect(order.line_items.first.fulfillments.first).to have_attributes(courier: 'fedex', tracking_id: 'fedex-123', estimated_delivery: Date.strptime('2018-12-15', '%Y-%m-%d'))
    end
  end
end
