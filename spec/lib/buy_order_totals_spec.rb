require 'rails_helper'
require 'support/gravity_helper'

describe BuyOrderTotals do
  let(:fulfillment_type) { Order::PICKUP }
  let(:gravity_artwork) { gravity_v1_artwork(_id: 'a-1', price_listed: 1000.00, edition_sets: [], domestic_shipping_fee_cents: 200_00, international_shipping_fee_cents: 300_00) }
  let(:order) { Fabricate(:order, seller_id: 'partner-1', seller_type: 'gallery', buyer_id: 'buyer1', buyer_type: Order::USER, fulfillment_type: fulfillment_type, commission_rate: 0.8) }
  let!(:line_item1) { Fabricate(:line_item, order: order, quantity: 1, list_price_cents: 1000_00, artwork_id: 'a-1', artwork_version_id: '1', sales_tax_cents: 0, shipping_total_cents: 1000, commission_fee_cents: 800_00) }
  let(:line_item2) { Fabricate(:line_item, order: order, quantity: 1, list_price_cents: 2000_00, artwork_id: 'a-3', artwork_version_id: '1', sales_tax_cents: 0, shipping_total_cents: 0, commission_fee_cents: 1600_00) }

  before do
    allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(gravity_artwork)
    allow(Adapters::GravityV1).to receive(:get).with('/partner/partner-1/all').and_return(gravity_v1_partner)
  end

  describe 'seller_total_cents' do
    context 'when shipping with arta' do
      let(:fulfillment_type) { Order::SHIP_ARTA }

      context 'when shipping_total_cents is 1000' do
        it 'subtracts shipping_total_cents from seller_total_cents' do
          buy_order_totals = BuyOrderTotals.new(order)
          expect(buy_order_totals.seller_total_cents).to eq(20_000)
        end
      end
    end

    context 'when using flat rate shipping' do
      let(:fulfillment_type) { Order::SHIP }

      context 'when shipping_total_cents is 1000' do
        it 'includes shipping_total_cents in seller_total_cents' do
          buy_order_totals = BuyOrderTotals.new(order)
          expect(buy_order_totals.seller_total_cents).to eq(21_000)
        end
      end
    end
  end

  describe 'commission_fee_cents' do
    context 'with single line item' do
      context 'no exemption' do
        it 'returns commission from order' do
          buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: nil)
          # Commission rate: 80%, price: 1000, commission: .8 x 1000 = 800
          expect(buy_order_totals.commission_fee_cents).to eq 800_00
        end
      end

      context 'exemption is 0' do
        it 'returns commission from order' do
          buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 0)
          # Commission rate: 80%, price: 1000, commission: .8 x 1000 = 800
          expect(buy_order_totals.commission_fee_cents).to eq 800_00
        end
      end

      context 'exemption is > 0' do
        context 'exemption is < line item price' do
          it 'returns commission with partial exemption' do
            buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 100_00)
            # Commission rate: 80%, price: 1000, exemption: 100, commission: .8 x (1000 - 100) = 720
            expect(buy_order_totals.commission_fee_cents).to eq 720_00
          end
        end

        context 'exemption is > line item price' do
          it 'returns 0 commission' do
            buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 2000_00)
            # Commission rate: 80%, price: 1000, exemption: 1000, commission: .8 x (1000 - 1000) = 0
            expect(buy_order_totals.commission_fee_cents).to eq 0
          end
        end
      end
    end

    context 'with multiple line items' do
      before do
        line_item2
      end
      context 'no exemption' do
        it 'returns commission from order' do
          buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: nil)
          # Commission rate: 80%, price: 3000, commission: .8 x 3000 = 2400
          expect(buy_order_totals.commission_fee_cents).to eq 2400_00
        end
      end

      context 'exemption is 0' do
        it 'returns commission from order' do
          buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 0)
          # Commission rate: 80%, price: 3000, commission: .8 x 3000 = 2400
          expect(buy_order_totals.commission_fee_cents).to eq 2400_00
        end
      end

      context 'exemption is > 0' do
        context 'with commission exemption larger than any individual line item' do
          it 'updates commission on order totals' do
            buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 1500_00)
            # Commission rate: 80%, price: 3000, exemption: 1500, commission: .8 x (3000 - 1500) = 1200
            expect(buy_order_totals.commission_fee_cents).to eq 1200_00
          end
        end
        context 'with commission exmeption smaller than any individual line item' do
          it 'updates commission on order totals' do
            buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 100_00)
            # Commission rate: 80%, price: 3000, exemption: 100, commission: .8 x (3000 - 100) = 2320
            expect(buy_order_totals.commission_fee_cents).to eq 2320_00
          end
        end
        context 'with commission exemption equal to the total of all line items' do
          it 'updates commission on order totals' do
            buy_order_totals = BuyOrderTotals.new(order, commission_exemption_amount_cents: 3000_00)
            # Commission rate: 80%, price: 3000, exemption: 3000, commission: .8 x (3000 - 3000) = 0
            expect(buy_order_totals.commission_fee_cents).to eq 0
          end
        end
      end
    end
  end
end
