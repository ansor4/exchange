# frozen_string_literal: true

module ARTA
  class Quote
    FRAMED_CATEGORY_MAP = {
      "Photography": 'photograph_framed',
      "Painting": 'painting_framed',
      "Print": 'work_on_paper_framed',
      "Drawing, Collage or other Work on Paper": 'work_on_paper_framed',
      "Mixed Media": 'mixed_media_framed'
    }.freeze

    UNFRAMED_CATEGORY_MAP = {
      "Photography": 'photograph_unframed',
      "Painting": 'painting_unframed',
      "Print": 'work_on_paper_unframed',
      "Drawing, Collage or other Work on Paper": 'work_on_paper_unframed',
      "Mixed Media": 'mixed_media_unframed',
      "Sculpture": 'scuplture'
    }.freeze

    attr_reader :order, :line_item, :artwork, :list_price_cents, :buyer

    def initialize(artwork, line_item)
      @artwork = artwork
      @order = line_item.order
      @line_item = line_item
      @list_price_cents = line_item.list_price_cents
      @buyer = Gravity.get_user(@order.buyer_id)
    end

    def post
      ARTA::Client.post(url: '/requests', params: formatted_post_params)
    end

    private

    def formatted_post_params
      {
        request: {
          destination: buyer_info,
          objects: [
            artwork_details
          ],
          origin: artwork_origin_location_and_contact_info
        }
      }
    end

    def artwork_details
      {
        subtype: format_artwork_type(artwork[:category], artwork[:framed]),
        unit_of_measurement: artwork[:framed] && artwork[:framed_metric].present? ? artwork[:framed_metric] : 'cm',
        height: artwork[:framed_height] || artwork[:framed_diameter] || artwork[:height_cm] || artwork[:diameter_cm],
        width: artwork[:framed_width] || artwork[:framed_diameter] || artwork[:width_cm] || artwork[:diameter_cm],
        depth: artwork[:framed_depth] || artwork[:depth_cm],
        value: convert_to_dollars,
        value_currency: artwork[:price_currency]
      }.merge(shipping_weight_and_metric).compact
    end

    def shipping_weight_and_metric
      return {} unless artwork[:shipping_weight]

      {
        weight: artwork[:shipping_weight],
        weight_unit: artwork[:shipping_weight_metric]
      }
    end

    def format_artwork_type(artwork_category, framed)
      return FRAMED_CATEGORY_MAP[artwork_category.to_sym] if framed

      UNFRAMED_CATEGORY_MAP[artwork_category.to_sym]
    end

    # TODO: Will need to change when supporting non USD currencies
    def convert_to_dollars
      return unless list_price_cents

      Float(list_price_cents) / 100
    end

    def buyer_info
      {
        title: buyer[:name],
        address_line_1: order.shipping_address_line1,
        address_line_2: order.shipping_address_line2,
        city: order.shipping_city,
        region: order.shipping_region,
        country: order.shipping_country,
        postal_code: order.shipping_postal_code,
        contacts: [
          {
            name: buyer[:name],
            email_address: buyer[:email],
            phone_number: order.buyer_phone_number
          }
        ]
      }
    end

    def artwork_origin_location_and_contact_info
      {
        title: artwork[:partner][:name],
        address_line_1: artwork[:location][:address],
        address_line_2: artwork[:location][:address_2],
        city: artwork[:location][:city],
        region: artwork[:location][:state],
        country: artwork[:location][:country],
        postal_code: artwork[:location][:postal_code],
        contacts: [
          {
            name: 'Artsy Partner',
            email_address: 'partner@test.com',
            phone_number: '6313667777'
          }
        ]
      }
    end
  end
end
