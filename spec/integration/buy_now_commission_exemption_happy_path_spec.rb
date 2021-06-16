require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe Api::GraphqlController, type: :request do
  include_context 'include stripe helper'
  include_context 'GraphQL Client Helpers'
  describe 'buy now happy path' do
    let(:seller_id) { 'gravity-partner-id' }
    let(:buyer_id) { 'user-id1' }
    let(:buyer_shipping_address) do
      {
        name: 'Fname Lname',
        country: 'US',
        city: 'New York',
        region: 'NY',
        postalCode: '10012',
        phoneNumber: '617-718-7818',
        addressLine1: '401 Broadway',
        addressLine2: 'Suite 80'
      }
    end
    let(:buyer_credit_card) { { id: 'cc-1', user: { _id: buyer_id }, external_id: 'cc_1', customer_account: { external_id: 'ca_1' } } }
    let(:gravity_artwork) { gravity_v1_artwork(_id: 'a-1', price_listed: 1000.00, edition_sets: [], domestic_shipping_fee_cents: 200_00, international_shipping_fee_cents: 300_00) }
    let(:gravity_partner) { { id: seller_id, artsy_collects_sales_tax: true, billing_location_id: '123abc', effective_commission_rate: 0.1 } }
    let(:seller_addresses) { [Address.new(state: 'NY', country: 'US', postal_code: '10001'), Address.new(state: 'MA', country: 'US', postal_code: '02139')] }
    let(:seller_merchant_account) { { external_id: 'ma-1' } }
    let(:buyer_client) { graphql_client(user_id: buyer_id, partner_ids: [], roles: 'user') }
    let(:seller_client) { graphql_client(user_id: 'partner_admin_id', partner_ids: [seller_id], roles: 'user') }
    let(:exemption) { { currency_code: 'USD', amount_minor: 100_00 } }

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
      prepare_payment_intent_create_success(amount: 1300_00)
      prepare_payment_intent_capture_success(amount: 1300_00)
    end

    it 'succeeds the process of buyer create -> set shipping -> set payment -> submit -> seller accept' do
      # Buyer creates the order
      expect do
        buyer_client.execute(QueryHelper::CREATE_ORDER, input: { artworkId: gravity_artwork[:_id], quantity: 1 })
      end.to change(Order, :count).by(1)
      order = Order.last
      expect(order).to have_attributes(state: Order::PENDING, items_total_cents: 1000_00, shipping_total_cents: nil, buyer_total_cents: nil, tax_total_cents: nil)

      # Buyer sets shipping info
      buyer_client.execute(QueryHelper::SET_SHIPPING, input: { id: order.id.to_s, fulfillmentType: 'SHIP', shipping: buyer_shipping_address })
      expect(order.reload).to have_attributes(
        state: Order::PENDING,
        items_total_cents: 1000_00,
        shipping_total_cents: 200_00,
        tax_total_cents: 100_00,
        buyer_total_cents: 1300_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'US'
      )

      # Buyer sets credit card
      buyer_client.execute(QueryHelper::SET_CREDIT_CARD, input: { id: order.id.to_s, creditCardId: buyer_credit_card[:id] })
      expect(order.reload).to have_attributes(
        state: Order::PENDING,
        items_total_cents: 1000_00,
        shipping_total_cents: 200_00,
        tax_total_cents: 100_00,
        buyer_total_cents: 1300_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'US',
        credit_card_id: 'cc-1'
      )

      # Buyer submits order
      expect do
        buyer_client.execute(QueryHelper::SUBMIT_ORDER, input: { id: order.id.to_s })
      end.to change(order.transactions, :count).by(1)
      expect(order.reload).to have_attributes(
        state: Order::SUBMITTED,
        items_total_cents: 1000_00,
        shipping_total_cents: 200_00,
        tax_total_cents: 100_00,
        buyer_total_cents: 1300_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'US',
        credit_card_id: 'cc-1',
        commission_fee_cents: 100_00
      )
      expect(order.transactions.last).to have_attributes(
        transaction_type: Transaction::HOLD,
        amount_cents: 1300_00,
        status: Transaction::SUCCESS,
        source_id: 'cc_1'
      )

      # seller accepts order
      expect do
        seller_client.execute(QueryHelper::APPROVE_ORDER, input: { id: order.id.to_s })
      end.to change(order.transactions, :count).by(1)
      expect(order.reload).to have_attributes(
        state: Order::APPROVED,
        items_total_cents: 1000_00,
        shipping_total_cents: 200_00,
        buyer_total_cents: 1300_00,
        tax_total_cents: 100_00,
        commission_fee_cents: 90_00,
        transaction_fee_cents: 0,
        seller_total_cents: 1210_00,
        fulfillment_type: Order::SHIP,
        shipping_country: 'US',
        credit_card_id: 'cc-1'
      )
      expect(order.transactions.order(created_at: :desc).first).to have_attributes(
        transaction_type: Transaction::CAPTURE,
        amount_cents: 1300_00,
        status: Transaction::SUCCESS
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
