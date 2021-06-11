require 'rails_helper'

describe ShippingQuote, type: :model do
  describe 'validations' do
    let(:shipping_quote) { Fabricate(:shipping_quote) }

    describe 'validate shipping quote tier' do
      context 'when tier is valid' do
        ShippingQuote::TIERS.each do |tier|
          it 'returns true' do
            shipping_quote.tier = tier
            expect(shipping_quote.valid?).to be true
          end
        end

        context 'when tier is not valid' do
          it 'returns false' do
            shipping_quote.tier = 'party-tier'
            expect(shipping_quote.valid?).to be false
          end

          it 'raises invalid record error' do
            expect do
              shipping_quote.update!(tier: 'party-tier')
            end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Tier is not included in the list')
          end
        end
      end
    end
  end
end
