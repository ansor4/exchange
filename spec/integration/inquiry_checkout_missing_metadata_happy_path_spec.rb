require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe 'Inquiry Checkout happy path with missing artwork metadata', type: :request do
  include_context 'GraphQL Client Helpers'
  include_context 'include stripe helper'

  let(:buyer_id) { 'gravity-user-id' }
  let(:buyer_client) { graphql_client(user_id: buyer_id, partner_ids: [], roles: 'user') }
  let(:seller_id) { 'gravity-partner-id' }
  let(:seller_user_id) { 'partner_user_id' }
  let(:seller_client) { graphql_client(user_id: seller_user_id, partner_ids: [seller_id], roles: 'user') }
  let(:seller_merchant_account) { { external_id: 'ma-1' } }
  let(:seller_addresses) { [Address.new(state: 'NY', country: 'US', postal_code: '10001'), Address.new(state: 'MA', country: 'US', postal_code: '02139')] }
  let(:buyer_client) { graphql_client(user_id: buyer_id, partner_ids: [], roles: 'user') }
  let(:seller_client) { graphql_client(user_id: seller_user_id, partner_ids: [seller_id], roles: 'user') }
  let(:gravity_partner) { { id: seller_id, artsy_collects_sales_tax: true, billing_location_id: '123abc', effective_commission_rate: 0.1 } }
  let(:exemption) { { currency_code: 'USD', amount_minor: 0 } }

  let(:buyer_offer_cents) { 500_00 }

  let(:impulse_conversation_id) { '401' }
  let(:artwork_id) { 'artwork_1' }
  let(:artwork_location) { { country: 'US' } }
  let(:artwork_without_metadata) do
    gravity_v1_artwork(
      _id: artwork_id,
      price_listed: 1000.00,
      edition_sets: [],
      domestic_shipping_fee_cents: nil,
      international_shipping_fee_cents: nil,
      inventory: nil,
      location: nil
    )
  end
  let(:artwork_with_metadata) do
    gravity_v1_artwork(
      _id: artwork_id,
      price_listed: 1000.00,
      edition_sets: [],
      domestic_shipping_fee_cents: 3000,
      international_shipping_fee_cents: 5000,
      inventory: nil,
      location: artwork_location
    )
  end
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
  let(:buyer_credit_card) do
    {
      id: 'credit_card_1',
      user: { _id: buyer_id },
      external_id: 'card_1',
      customer_account: { external_id: 'cust_1' }
    }
  end

  before do
    allow(Gravity).to receive_messages(
      get_artwork: artwork_without_metadata,
      fetch_partner_locations: seller_addresses,
      fetch_partner: gravity_partner,
      get_credit_card: buyer_credit_card,
      deduct_inventory: nil,
      get_merchant_account: seller_merchant_account,
      debit_commission_exemption: exemption
    )
    prepare_setup_intent_create(status: 'succeeded')
    prepare_payment_intent_create_success(amount: 800_00)
    prepare_setup_intent_create(status: 'succeeded')
  end

  it 'supports buyer submitting an offer, seller adding missing metadata, and buyer accepting it' do
    buyer_creates_pending_offer_order
    buyer_adds_initial_offer_to_oder
    buyer_sets_shipping
    buyer_sets_credit_card
    buyer_submits_offer_order
    seller_provides_missing_metadata_and_accepts
    buyer_accepts_offer
  end

  def buyer_creates_pending_offer_order
    create_inquiry_offer_order_input = { artworkId: artwork_id, quantity: 1, impulseConversationId: impulse_conversation_id }
    expect do
      buyer_client.execute(OfferQueryHelper::CREATE_INQUIRY_OFFER_ORDER, input: create_inquiry_offer_order_input)
    end.to change(Order, :count).by(1)

    order = Order.last
    expect(order).to have_attributes(
      state: Order::PENDING,
      mode: Order::OFFER,
      impulse_conversation_id: '401',
      items_total_cents: nil,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      seller_total_cents: nil
    )
  end

  def buyer_adds_initial_offer_to_oder
    order = Order.last

    add_offer_to_order_input = { orderId: order.id, amountCents: buyer_offer_cents }
    expect do
      buyer_client.execute(OfferQueryHelper::ADD_OFFER_TO_ORDER, input: add_offer_to_order_input)
    end.to change(Offer, :count).by(1)

    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      mode: Order::OFFER,
      impulse_conversation_id: '401',
      items_total_cents: nil,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      seller_total_cents: nil
    )
    offer = Offer.last
    expect(offer).to have_attributes(
      amount_cents: 500_00,
      order_id: order.id,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil
    )
  end

  def buyer_sets_shipping
    order = Order.last

    set_shipping_input = { id: order.id.to_s, fulfillmentType: 'SHIP', shipping: buyer_shipping_address }
    expect do
      buyer_client.execute(QueryHelper::SET_SHIPPING, input: set_shipping_input)
    end.to_not change(Offer, :count)

    # tax and shipping info is nil
    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      mode: Order::OFFER,
      impulse_conversation_id: '401',
      fulfillment_type: Order::SHIP,
      items_total_cents: nil,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      shipping_country: 'US',
      shipping_city: 'New York',
      shipping_address_line1: '401 Broadway',
      shipping_address_line2: 'Suite 80',
      shipping_postal_code: '10012'
    )

    offer = Offer.last
    expect(offer).to have_attributes(
      amount_cents: 500_00,
      shipping_total_cents: nil,
      tax_total_cents: nil,
      buyer_total_cents: nil,
      definite_total?: false
    )
  end

  def buyer_sets_credit_card
    order = Order.last

    set_credit_card_input = { id: order.id.to_s, creditCardId: buyer_credit_card[:id] }
    buyer_client.execute(QueryHelper::SET_CREDIT_CARD, input: set_credit_card_input)

    expect(order.reload).to have_attributes(
      state: Order::PENDING,
      fulfillment_type: Order::SHIP,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1'
    )
  end

  def buyer_submits_offer_order
    order = Order.last

    offer = Offer.last

    result = nil

    expect do
      result = buyer_client.execute(OfferQueryHelper::SUBMIT_ORDER_WITH_OFFER, input: { offerId: offer.id.to_s })
    end.to change(order.transactions, :count).by(1)

    # offer doesn't have definite_total because tax/shipping data is not available
    expect(result.data.submit_order_with_offer.order_or_error.order.last_offer.has_definite_total).to be false

    expect(order.transactions.min_by(&:created_at)).to have_attributes(external_type: Transaction::SETUP_INTENT, status: Transaction::SUCCESS, transaction_type: Transaction::CONFIRM)

    # after submission totals are calculated but shipping and tax are nil because artwork location and shipping is not provided yet
    expect(order.reload).to have_attributes(
      state: Order::SUBMITTED,
      fulfillment_type: Order::SHIP,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1',
      # below are calculated without shipping/tax
      shipping_total_cents: nil,
      tax_total_cents: nil,
      items_total_cents: 50000,
      buyer_total_cents: nil,
      seller_total_cents: nil,
      transaction_fee_cents: 0,
      commission_fee_cents: 5000
    )
  end

  def seller_provides_missing_metadata_and_accepts
    allow(Gravity).to receive_messages(get_artwork: artwork_with_metadata)

    stub_request(:post, "#{Taxjar::API::Request::DEFAULT_API_URL}/v2/taxes")
      .with(body: hash_including({ amount: 500 }))
      .to_return(body: sales_tax_fixture(tax_amount: 25).to_json, headers: { content_type: 'application/json; charset=utf-8' })

    order = Order.last
    offer = Offer.last

    result = nil

    expect do
      result = seller_client.execute(OfferQueryHelper::SELLER_ACCEPT_PROVISIONAL_OFFER, input: { offerId: offer.id.to_s })
    end.not_to change(order.transactions, :count)

    # offer now has definite total
    expect(result.data.seller_accept_provisional_offer.order_or_error.order.last_offer.has_definite_total).to be true

    order.reload

    expect(order.transactions.count).to be 1

    # after submission totals are calculated with shipping and tax
    expect(order).to have_attributes(
      state: Order::SUBMITTED,
      fulfillment_type: Order::SHIP,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1',
      # calculated with shipping/tax
      shipping_total_cents: 30_00,
      tax_total_cents: 25_00,
      items_total_cents: 500_00,
      buyer_total_cents: 555_00,
      seller_total_cents: 505_00,
      transaction_fee_cents: 0,
      commission_fee_cents: 50_00
    )
    expect(order.last_offer).to have_attributes(
      # amount cents stays the same
      amount_cents: 50000,
      shipping_total_cents: 30_00,
      tax_total_cents: 25_00,
      # amount change is false and fees added is true
      offer_amount_changed?: false,
      defines_total?: true
    )

    # TODO: check pulse events
  end

  def buyer_accepts_offer
    order = Order.last

    seller_counter_offer = order.offers.order(created_at: :desc).first
    buyer_accept_offer_input = { offerId: seller_counter_offer.id.to_s }
    buyer_client.execute(OfferQueryHelper::BUYER_ACCEPT_OFFER, input: buyer_accept_offer_input)

    expect(order.reload).to have_attributes(
      state: Order::APPROVED,
      fulfillment_type: Order::SHIP,
      items_total_cents: 500_00,
      shipping_total_cents: 30_00,
      tax_total_cents: 25_00,
      buyer_total_cents: 555_00,
      commission_fee_cents: 50_00,
      transaction_fee_cents: 0,
      seller_total_cents: 505_00,
      shipping_country: 'US',
      credit_card_id: 'credit_card_1'
    )

    deduct_inventory_request = stub_request(:put, "#{gravity_v1_api_root}/artwork/#{artwork_id}/inventory")
    expect(deduct_inventory_request).to_not have_been_made

    expect(order.transactions.count).to be 2
    expect(order.transactions.max_by(&:created_at)).to have_attributes(external_type: Transaction::PAYMENT_INTENT, status: Transaction::SUCCESS, transaction_type: Transaction::CAPTURE)
  end
end
