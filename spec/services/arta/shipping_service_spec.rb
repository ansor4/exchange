require 'rails_helper'

describe ARTA::ShippingService do
  describe '.generate_shipping_quotes' do
    let(:response) do
      JSON.parse(File.read('spec/support/fixtures/arta/quote_request_success_response.json'), { symbolize_names: true })
    end

    before do
      allow(Gravity).to receive(:get_user).and_return({})
      allow(Gravity).to receive(:get_artwork).and_return({})
      allow_any_instance_of(ARTA::Quote).to receive(:post).and_return(response)
    end

    context 'success' do
      let(:line_item) { Fabricate(:line_item) }

      it 'persists the correct records' do
        expect { described_class.new(line_item).generate_shipping_quotes }.to change { ShippingQuote.count }.by(5)
        expect { described_class.new(line_item).generate_shipping_quotes }.to change { ShippingQuoteRequest.count }.by(1)
      end
    end
  end

  describe '.book_shipment' do
    let(:response) do
      JSON.parse(File.read('spec/support/fixtures/shipment_create_request_success_response.json'), { symbolize_names: true })
    end

    before do
      allow(ARTA::Shipment).to receive(:create).and_return(response)
    end

    context 'success' do
      let(:shipping_quote) { Fabricate(:shipping_quote) }
      let(:line_item) { Fabricate(:line_item, selected_shipping_quote_id: shipping_quote.id) }

      it 'persists the correct records' do
        expect { described_class.new(line_item).book_shipment }.to change { Shipment.count }.by(1)
      end

      it 'writes the correct status' do
        shipment = described_class.new(line_item).book_shipment
        expect(shipment.status).to eq response[:status]
      end
    end
  end
end
