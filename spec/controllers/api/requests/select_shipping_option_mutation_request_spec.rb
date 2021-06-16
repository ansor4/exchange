require 'rails_helper'
require 'support/gravity_helper'
require 'support/taxjar_helper'

describe Api::GraphqlController, type: :request do
  describe 'set_shipping mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:order) do
      Fabricate(:order, shipping_name: 'Collector Molly', shipping_address_line1: '332 Prospect St',
                        shipping_city: 'Niagara Falls', shipping_country: 'US', shipping_region: 'NY', shipping_postal_code: '14127', buyer_phone_number: '6313555555', seller_id: seller_id,
                        buyer_id: user_id, mode: Order::BUY, fulfillment_type: Order::SHIP_ARTA)
    end
    let!(:line_item) { Fabricate(:line_item, order: order, artwork_id: 'a-1') }
    let(:artwork1) { gravity_v1_artwork(_id: 'a-1', domestic_shipping_fee_cents: 200_00, international_shipping_fee_cents: 300_00) }
    let(:partner) { { id: seller_id, artsy_collects_sales_tax: true, billing_location_id: '123abc' } }
    let(:seller_addresses) { [Address.new(state: 'NY', country: 'US', postal_code: '10001'), Address.new(state: 'MA', country: 'US', postal_code: '02139')] }

    let(:select_shipping_option_input) do
      {
        input: {
          id: order.id.to_s,
          selectedShippingQuoteId: selected_shipping_quote_id
        }.compact
      }
    end

    before do
      stub_tax_for_order
    end

    context 'when invalid selectedShippingQuoteId is input' do
      let(:selected_shipping_quote_id) { 'invalid-id' }

      it 'returns a validation error' do
        response = client.execute(QueryHelper::SELECT_ARTA_SHIPPING_OPTION, select_shipping_option_input)

        expect(response.data.select_shipping_option.order_or_error.error.type).to eq 'validation'
        expect(response.data.select_shipping_option.order_or_error.error.code).to eq 'selected_shipping_quote_id_not_found'
      end
    end

    context 'when valid selectedShippingQuoteId is input' do
      let!(:parcel_shipping_quote) { Fabricate(:shipping_quote, tier: 'parcel', shipping_quote_request: shipping_quote_request, price_cents: 500) }
      let!(:select_shipping_quote) { Fabricate(:shipping_quote, tier: 'select', shipping_quote_request: shipping_quote_request, price_cents: 1000) }
      let(:shipping_quote_request) { Fabricate(:shipping_quote_request, line_item: line_item) }
      let(:selected_shipping_quote_id) { select_shipping_quote.id }

      before do
        allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(artwork1)
        allow(Gravity).to receive_messages(
          fetch_partner_locations: seller_addresses,
          fetch_partner: partner
        )
      end

      it 'updates the selected_shipping_quote_id on line item' do
        client.execute(QueryHelper::SELECT_ARTA_SHIPPING_OPTION, select_shipping_option_input)
        expect(line_item.reload.selected_shipping_quote_id).to eq(select_shipping_quote.id)
      end

      it 'returns the correct response' do
        response = client.execute(QueryHelper::SELECT_ARTA_SHIPPING_OPTION, select_shipping_option_input)
        expected_data = response.data.select_shipping_option.order_or_error.order

        expect(expected_data.shipping_total_cents).to eq(select_shipping_quote.price_cents)
        expect(expected_data.line_items.edges[0].node.shipping_quote_options.edges.map { |e| e.node.is_selected }).to match_array([true, false])
      end

      context 'when requesting user is not the order buyer' do
        let(:user_id) { 'random-user-id-on-another-order' }

        it 'returns an authentication error' do
          response = client.execute(QueryHelper::SELECT_ARTA_SHIPPING_OPTION, select_shipping_option_input)

          expect(response.data.select_shipping_option.order_or_error.error.type).to eq 'validation'
          expect(response.data.select_shipping_option.order_or_error.error.code).to eq 'not_found'
        end
      end
    end
  end
end
