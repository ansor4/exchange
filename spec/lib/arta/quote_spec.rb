require 'rails_helper'

describe ARTA::Quote do
  describe '.formatted_post_params' do
    let(:order) { Fabricate(:order, shipping_address_line1: '332 Prospect St', shipping_address_line2: '2nd floor', shipping_city: 'Niagara Falls', shipping_region: 'NY', shipping_country: 'US', shipping_postal_code: '14303', buyer_phone_number: '4517777777') }
    let(:line_item) { Fabricate(:line_item, order: order) }
    # rubocop:disable Naming/VariableNumber
    let(:artwork) do
      {
        title: 'dog in the fog',
        category: 'Painting',
        framed: false,
        height_cm: 30,
        diameter_cm: 40,
        width_cm: 25,
        depth_cm: 2,
        price_currency: 'EUR',
        shipping_weight: 2,
        shipping_weight_metric: 'KG',
        location: {
          address: 'dog street 1',
          address_2: '1st floor',
          city: 'Berlin',
          state: 'BE',
          country: 'DE',
          postal_code: '13409'
        },
        partner: {
          name: 'Partner Name'
        }
      }
    end
    # rubocop:enable Naming/VariableNumber
    let(:buyer) { { name: 'Pinky Pie', email: 'pinky@pie.com' } }
    let(:service) { described_class.new(artwork, line_item) }
    # rubocop:disable Naming/VariableNumber
    let(:expected_params) do
      { request:
        {
          destination:
          {
            address_line_1: '332 Prospect St',
            address_line_2: '2nd floor',
            city: 'Niagara Falls',
            contacts: [{ email_address: 'pinky@pie.com', name: 'Pinky Pie', phone_number: '4517777777' }],
            country: 'US',
            postal_code: '14303',
            region: 'NY',
            title: 'Pinky Pie'
          },
          objects: [{ depth: 2, height: 30, subtype: 'painting_unframed', unit_of_measurement: 'cm', value: 100.0, value_currency: 'EUR', weight: 2, weight_unit: 'KG', width: 25 }],
          origin:
          {
            address_line_1: 'dog street 1',
            address_line_2: '1st floor',
            city: 'Berlin',
            contacts: [{ email_address: 'partner@test.com', name: 'Artsy Partner', phone_number: '6313667777' }],
            country: 'DE',
            postal_code: '13409',
            region: 'BE',
            title: 'Partner Name'
          }
        } }
    end
    # rubocop:enable Naming/VariableNumber
    before do
      allow(Gravity).to receive(:get_artwork).and_return(artwork)
      allow(Gravity).to receive(:get_user).and_return(buyer)
      allow(ARTA::Client).to receive(:post).and_return(true)
    end

    after { Timecop.return }

    it 'posts to arta' do
      expect(service.post).to be true
      expect(service.send(:formatted_post_params)).to eq(expected_params)
    end

    context 'when preparing artwork metadata' do
      context 'when artwork data present' do
        before do
          line_item.list_price_cents = 30000
          artwork[:width_cm] = 10.7
          artwork[:height_cm] = 11.0
          artwork[:category] = 'Photography'
        end

        context 'when artwork is framed' do
          before do
            artwork[:framed] = true
            artwork[:framed_width] = 12
            artwork[:framed_height] = 13
            artwork[:framed_depth] = 2
          end

          it 'returns properly formatted object parameter' do
            resolved_post_params = service.send(:formatted_post_params)[:request][:objects].first
            expect(resolved_post_params[:height]).to eq(13.0)
            expect(resolved_post_params[:depth]).to eq(2)
            expect(resolved_post_params[:subtype]).to eq('photograph_framed')
            expect(resolved_post_params[:unit_of_measurement]).to eq('cm')
            expect(resolved_post_params[:width]).to eq(12.0)
            expect(resolved_post_params[:value]).to eq(300)
          end
        end
      end

      context 'when artwork is not framed' do
        before do
          artwork[:framed] = false
        end

        it 'returns proper subtype' do
          resolved_post_params = service.send(:formatted_post_params)[:request][:objects].first
          expect(resolved_post_params[:subtype]).to eq('painting_unframed')
        end
      end

      context 'when some artwork data is nil' do
        before do
          artwork[:width_cm] = nil
          artwork[:diameter_cm] = nil
        end

        it 'returns properly formatted parameters' do
          resolved_post_params = service.send(:formatted_post_params)[:request][:objects].first
          expect(resolved_post_params).not_to include(:width)
        end
      end
    end
  end
end
