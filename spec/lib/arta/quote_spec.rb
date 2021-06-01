require 'rails_helper'

describe ARTA::Quote do
  describe '.formatted_post_params' do
    let(:line_item) { Fabricate(:line_item) }
    let(:artwork) do
      {
        title: 'dog in the fog',
        category: 'Painting',
        framed: true,
        height_cm: 30,
        diameter_cm: 40,
        width_cm: 25,
        depth_cm: 2,
        price_currency: 'EUR',
        shipping_weight: 2,
        shipping_weight_metric: 'KG',
        location: {
          address: 'dog street 1',
          city: 'Berlin',
          state: 'BE',
          country: 'DE',
          postal_code: '13409'
        }
      }
    end
    let(:buyer) { {name: 'Pinky Pie', email: 'pinky@pie.com'} }
    let(:service) { described_class.new(artwork, line_item) }
    # rubocop:disable Naming/VariableNumber
    let(:expected_params) do
      { request:
        {
          destination:
          {
            address_line_1: '332 Prospect St',
            city: 'Niagara Falls',
            contacts: [{ email_address: 'test@email.com', name: 'Collector Molly', phone_number: '4517777777' }],
            country: 'US',
            postal_code: '14303',
            region: 'NY',
            title: 'Collector Molly'
          },
          objects: [{ depth: 2, height: 30, subtype: 'painting_framed', unit_of_measurement: 'cm', value: 100.0, value_currency: 'EUR', weight: 2, weight_unit: 'KG', width: 25 }],
          origin:
          {
            address_line_1: '401 Broadway',
            city: 'New York',
            contacts: [{ email_address: 'partner@test.com', name: 'Artsy Partner', phone_number: '6313667777' }],
            country: 'US',
            postal_code: '10013',
            region: 'NY',
            title: 'Hello Gallery'
          }
        } }
    end
    # rubocop:enable Naming/VariableNumber
    before do
      allow(Gravity).to receive(:get_artwork).and_return(artwork)
      allow(Gravity).to receive(:get_user).and_return(buyer)
      allow(ARTA::Client).to receive(:post).and_return(true)
    end

    it 'posts to arta' do
      expect(service.post).to be true
      expect(service.send(:formatted_post_params)).to eq(expected_params)
    end

    #   context 'when preparing artwork metadata' do
    #     let(:expected_formatted_params) do
    #       described_class.formatted_post_params(artwork_hash, list_price_cents)[:request]
    #     end

    #     context 'when artwork data present' do
    #       let(:list_price_cents) { 30000 }

    #       context 'when artwork is framed' do
    #         let(:artwork_hash) do
    #           {
    #             category: 'Photography',
    #             framed: true,
    #             width_cm: 10.7,
    #             height_cm: 11.0
    #           }
    #         end

    #         it 'returns properly formatted object parameter' do
    #           expect(expected_formatted_params).to include({
    #                                                          objects: [
    #                                                            {
    #                                                              height: 11.0,
    #                                                              subtype: 'photograph_framed',
    #                                                              unit_of_measurement: 'cm',
    #                                                              width: 10.7,
    #                                                              value: 300
    #                                                            }
    #                                                          ]
    #                                                        })
    #         end
    #       end

    #       context 'when artwork is not framed' do
    #         let(:artwork_hash) do
    #           {
    #             category: 'Photography',
    #             framed: false,
    #             width_cm: 10.7,
    #             height_cm: 11.0
    #           }
    #         end

    #         it 'returns properly formatted object parameter' do
    #           expect(expected_formatted_params).to include({
    #                                                          objects: [
    #                                                            {
    #                                                              height: 11.0,
    #                                                              subtype: 'photograph_unframed',
    #                                                              unit_of_measurement: 'cm',
    #                                                              width: 10.7,
    #                                                              value: 300
    #                                                            }
    #                                                          ]
    #                                                        })
    #         end
    #       end
    #     end

    #     context 'when some artwork data is nil' do
    #       let(:list_price_cents) { 30000 }
    #       let(:artwork_hash) do
    #         {
    #           category: 'Photography',
    #           framed: true,
    #           width_cm: nil,
    #           height_cm: 11.0
    #         }
    #       end

    #       it 'returns properly formatted parameters' do
    #         expect(expected_formatted_params).to include({
    #                                                        objects: [
    #                                                          {
    #                                                            height: 11.0,
    #                                                            subtype: 'photograph_framed',
    #                                                            unit_of_measurement: 'cm',
    #                                                            value: 300
    #                                                          }
    #                                                        ]
    #                                                      })
    #       end
    #     end
    #   end
  end
end
