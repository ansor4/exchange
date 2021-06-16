require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe 'Checkout with ARTA Shipment choice for Buy Now flow' do
  include_context 'GraphQL Client Helpers'
  let(:arta_quote_request_response) { JSON.parse(File.read('spec/support/fixtures/arta/quote_request_success_response.json'), { symbolize_names: true }) }

  let(:buyer_id) { 'gravity-user-id' }
  let(:buyer_client) { graphql_client(user_id: buyer_id, partner_ids: [], roles: 'user') }
  let(:seller_id) { 'gravity-partner-id' }
  let(:seller_client) { graphql_client(user_id: 'partner_admin_id', partner_ids: [seller_id], roles: 'user') }
  let(:partner) { gravity_v1_partner }
  let(:merchant_account) { { external_id: 'ma-1' } }

  let(:seller_addresses) do
    [
      Address.new(state: 'NY', country: 'US', postal_code: '10001'),
      Address.new(state: 'MA', country: 'US', postal_code: '02139')
    ]
  end

  let(:artwork) do
    gravity_v1_artwork(
      _id: 'artwork_1',
      price_listed: 1000.00,
      edition_sets: [],
      domestic_shipping_fee_cents: nil,
      international_shipping_fee_cents: nil,
      inventory: nil,
      location: artwork_location_address
    )
  end

  let(:buyer_shipping_address) do
    {
      name: 'Collector Molly',
      addressLine1: '332 Prospect St',
      city: 'Niagara Falls',
      region: 'NY',
      country: 'US',
      postalCode: '14303',
      phoneNumber: '6313444444'
    }
  end

  let(:buyer_credit_card) do
    {
      id: 'credit_card_1',
      user: { _id: buyer_id },
      external_id: 'card_1',
      customer_account: { external_id: 'cust_1' }
    }
  end

  let(:artwork_location_address) do
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

  before do
    allow(Gravity).to receive_messages(
      get_artwork: artwork,
      get_credit_card: buyer_credit_card
    )
  end

  it 'successfully processes and submits a buy now order with arta shipment' do
    buyer_creates_pending_buy_order
    buyer_sets_shipping_with_ship_arta_fulfillment_type
    buyer_selects_arta_shipping_quote_option
    buyer_sets_credit_card
    buyer_submits_order
  end

  def buyer_creates_pending_buy_order
    create_buy_now_pending_order_input = { artworkId: artwork[:_id], quantity: 1 }

    expect do
      buyer_client.execute(QueryHelper::CREATE_ORDER, input: create_buy_now_pending_order_input)
    end.to change(Order, :count).by(1)

    order = Order.last
    expect(order).to have_attributes(
      state: Order::PENDING,
      mode: Order::BUY,
      items_total_cents: 100000,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      seller_total_cents: nil
    )
  end

  def buyer_sets_shipping_with_ship_arta_fulfillment_type
    allow(Gravity).to receive(:get_user).and_return({})
    allow(Gravity).to receive(:get_artwork).and_return(artwork)
    allow_any_instance_of(ARTA::Quote).to receive(:post).and_return(arta_quote_request_response)

    order = Order.last
    set_shipping_input = { id: order.id.to_s, fulfillmentType: 'SHIP_ARTA', shipping: buyer_shipping_address }

    # Triggers api call to arta and saves shipping quotes and metadata response
    expect do
      buyer_client.execute(QueryHelper::SET_SHIPPING, input: set_shipping_input)
    end.to change(ShippingQuoteRequest, :count).by(1)
                                               .and change(ShippingQuote, :count).by(5)

    # Updates order shipping address on order but does not run tax calculation or shipping totals yet
    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      mode: Order::BUY,
      fulfillment_type: Order::SHIP_ARTA,
      items_total_cents: 100000,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      shipping_country: 'US',
      shipping_address_line1: '332 Prospect St',
      shipping_address_line2: nil,
      shipping_city: 'Niagara Falls',
      shipping_postal_code: '14303'
    )
  end

  def buyer_selects_arta_shipping_quote_option
    order = Order.last
    selected_shipping_input = {
      id: order.id.to_s,
      selectedShippingQuoteId: ShippingQuote.find_by(tier: 'premium').id.to_s
    }

    stub_tax_for_order
    allow(Gravity).to receive(:fetch_partner_locations).and_return(seller_addresses)
    allow(Gravity).to receive(:fetch_partner).and_return(partner)
    buyer_client.execute(QueryHelper::SELECT_ARTA_SHIPPING_OPTION, input: selected_shipping_input)

    # Updates buyer_total_cents and shipping_total_cents
    # which includes price of selected arta quote
    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      mode: Order::BUY,
      fulfillment_type: Order::SHIP_ARTA,
      items_total_cents: 100000,
      shipping_total_cents: 200,
      tax_total_cents: 116,
      buyer_total_cents: 100316,
      shipping_country: 'US',
      shipping_address_line1: '332 Prospect St',
      shipping_address_line2: nil,
      shipping_city: 'Niagara Falls',
      shipping_postal_code: '14303'
    )

    # Persists the collectors shipping selection on the line item
    expect(order.reload.line_items.first).to have_attributes(
      selected_shipping_quote_id: ShippingQuote.find_by(tier: 'premium').id.to_s
    )
  end

  def buyer_sets_credit_card
    order = Order.last

    # TODO: refactor: `id` should be `orderId` to be consistent
    set_credit_card_input = { id: order.id.to_s, creditCardId: buyer_credit_card[:id] }
    buyer_client.execute(QueryHelper::SET_CREDIT_CARD, input: set_credit_card_input)

    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      fulfillment_type: Order::SHIP_ARTA,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1'
    )
  end

  def buyer_submits_order
    order = Order.last
    submit_order_input = { id: order.id.to_s }

    # Makes request to Gravity to deduct inventory for sold artwork
    expect(Gravity).to receive(:deduct_inventory)
    allow_any_instance_of(OrderProcessor).to receive_messages(
      hold: nil,
      store_transaction: nil
    )
    allow(Gravity).to receive(:get_merchant_account).and_return(merchant_account)

    buyer_client.execute(QueryHelper::SUBMIT_ORDER, input: submit_order_input)

    # Updates commission, seller_total_cents and changes the order.state
    expect(order.reload).to have_attributes(
      state: Order::SUBMITTED,
      fulfillment_type: Order::SHIP_ARTA,
      items_total_cents: 100000,
      shipping_total_cents: 200,
      tax_total_cents: 116,
      buyer_total_cents: 100316,
      seller_total_cents: 20116,
      transaction_fee_cents: 0,
      commission_fee_cents: 80000,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1'
    )
  end
end
