require 'rails_helper'

RSpec.describe Offer, type: :model do
  it_behaves_like 'a papertrail versioned model', :offer

  describe 'last_offer?' do
    it "returns true if the offer is the order's last offer" do
      order = Fabricate(:order)
      offer = Fabricate(:offer, order: order)
      order.update!(last_offer: offer)

      expect(offer.last_offer?).to eq(true)
    end

    it "return false if the offer is not the order's last offer" do
      order = Fabricate(:order)
      first_offer = Fabricate(:offer, order: order)
      second_offer = Fabricate(:offer, order: order)

      order.update!(last_offer: second_offer)

      expect(first_offer.last_offer?).to eq(false)
    end
  end

  describe 'buyer_total_cents' do
    let(:shipping_total_cents) { 20 }
    let(:amount_cents) { 100 }
    let(:tax_total_cents) { 5 }
    let(:order) { Fabricate(:order) }
    let(:offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents) }

    context 'offer with all required amounts' do
      it 'sums up amount, tax and shipping' do
        expect(offer.buyer_total_cents).to be 125
      end
    end

    context 'offer without tax' do
      let(:tax_total_cents) { nil }

      it 'returns nil as buyer total' do
        expect(offer.buyer_total_cents).to be nil
      end
    end

    context 'offer without shipping' do
      let(:shipping_total_cents) { nil }

      it 'returns nil as buyer total' do
        expect(offer.buyer_total_cents).to be nil
      end
    end
  end

  describe '#definite_total?' do
    let(:shipping_total_cents) { 20 }
    let(:amount_cents) { 100 }
    let(:tax_total_cents) { 5 }
    let(:order) { Fabricate(:order) }
    let(:offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents) }
    context 'amount_cents, shipping_total_cents, and  tax_total_cents present' do
      it 'returns true' do
        expect(offer.definite_total?).to be true
      end
    end
    context 'offer without tax' do
      let(:tax_total_cents) { nil }

      it 'returns false' do
        expect(offer.definite_total?).to be false
      end
    end

    context 'offer without shipping' do
      let(:shipping_total_cents) { nil }

      it 'returns false' do
        expect(offer.definite_total?).to be false
      end
    end

    context 'offer without amount' do
      let(:amount_cents) { nil }

      it 'returns false' do
        expect(offer.definite_total?).to be false
      end
    end
  end

  describe '#offer_amount_changed?' do
    let(:order) { Fabricate(:order) }
    let(:amount_cents) { 100 }
    let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents) }
    let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: amount_cents) }

    context 'when not responding to a previous offer' do
      let(:previous_offer) { nil }
      it 'returns false' do
        expect(offer.offer_amount_changed?).to be(false)
      end
    end
    context 'when amounts are the same' do
      it 'returns false' do
        expect(offer.offer_amount_changed?).to be(false)
      end
    end

    context 'when previous offer has a different amount' do
      let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: 200) }
      it 'returns false' do
        expect(offer.offer_amount_changed?).to be(true)
      end
    end
  end

  describe '#defines_total?' do
    let(:order) { Fabricate(:order) }
    let(:shipping_total_cents) { 20 }
    let(:amount_cents) { 100 }
    let(:tax_total_cents) { 5 }
    let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents) }
    let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents) }

    context 'when not responding to a previous offer' do
      let(:previous_offer) { nil }
      it 'returns false' do
        expect(offer.defines_total?).to be(false)
      end
    end

    context 'when previous offer has definite total' do
      let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents) }
      it 'returns false' do
        expect(offer.defines_total?).to be(false)
      end
    end

    context 'when new offer does not have definite total' do
      let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: amount_cents, shipping_total_cents: nil, tax_total_cents: nil) }
      it 'returns false' do
        expect(offer.defines_total?).to be(false)
      end
    end

    context 'when previous offer does not have definite total and this one has' do
      it 'returns true' do
        expect(offer.defines_total?).to be(true)
      end
    end
  end

  describe '#buyer_offer_action_type' do
    let(:state) { Order::SUBMITTED }
    let(:order) { Fabricate(:order, state: state, buyer_id: 'buyer1', buyer_type: 'user', seller_id: 'seller1', seller_type: 'gallery') }
    let!(:offer_from_seller) { { from_id: 'seller1', from_type: 'gallery' } }
    let!(:offer_from_buyer) { { from_id: 'buyer1', from_type: 'user' } }
    let(:shipping_total_cents) { 20 }
    let(:amount_cents) { 100 }
    let(:tax_total_cents) { 5 }
    let(:offer_from) { offer_from_seller }
    let(:previous_offer_from) { offer_from_buyer }
    let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, **previous_offer_from) }
    let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **offer_from) }

    shared_examples 'no action needed' do
      it 'returns nil' do
        expect(offer.buyer_offer_action_type).to be(nil)
      end
    end

    context 'when not responding to a previous offer' do
      let(:previous_offer) { nil }
      it_behaves_like 'no action needed'
    end
    context 'order state is submitted' do
      context 'last offer is from seller' do
        context 'offer defines total' do
          context 'without changing the amount' do
            it 'returns order accepted confirm needed' do
              expect(offer.buyer_offer_action_type).to eq(Offer::OFFER_ACCEPTED_CONFIRM_NEEDED)
            end
          end
          context 'changing the amount' do
            let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: 200, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **offer_from_seller) }
            it 'returns order received confirm needed' do
              expect(offer.buyer_offer_action_type).to eq(Offer::OFFER_RECEIVED_CONFIRM_NEEDED)
            end
          end
        end
        context 'does not define total' do
          let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **previous_offer_from) }
          context 'without changing the amount' do
            # impossible
            it_behaves_like 'no action needed'
          end
          context 'changing the amount' do
            let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: 200, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **offer_from_seller) }
            it 'returns offer received' do
              expect(offer.buyer_offer_action_type).to eq(Offer::OFFER_RECEIVED)
            end
          end
        end
      end
      context 'last offer is from buyer' do
        # buyer has just placed and offer so no action is needed.
        let(:offer_from) { offer_from_buyer }
        let(:previous_offer_from) { offer_from_seller }
        context 'offer defines total' do
          context 'without changing the amount' do
            it_behaves_like 'no action needed'
          end
          context 'changing the amount' do
            let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: 200, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **offer_from) }
            it_behaves_like 'no action needed'
          end
        end
        context 'does not define total' do
          let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **previous_offer_from) }
          context 'without changing the amount' do
            it_behaves_like 'no action needed'
          end
          context 'changing the amount' do
            let(:offer) { Fabricate(:offer, order: order, responds_to: previous_offer, amount_cents: 200, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **offer_from) }
            it_behaves_like 'no action needed'
          end
        end
      end
    end

    context 'order state is approved' do
      let(:state) { Order::APPROVED }
      context 'last offer is from the buyer' do
        let(:offer_from) { offer_from_buyer }
        let(:previous_offer_from) { offer_from_seller }
        it 'returns offer accepted' do
          expect(offer.buyer_offer_action_type).to eq(Offer::OFFER_ACCEPTED)
        end
      end
      context 'last offer is from the seller' do
        context 'offer defines total' do
          it 'returns provisional offer accepted' do
            expect(offer.buyer_offer_action_type).to eq(Offer::PROVISIONAL_OFFER_ACCEPTED)
          end
        end
        context 'does not define total' do
          let(:previous_offer) { Fabricate(:offer, order: order, amount_cents: amount_cents, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents, **previous_offer_from) }
          it 'returns offer accepted' do
            expect(offer.buyer_offer_action_type).to eq(Offer::OFFER_ACCEPTED)
          end
        end
      end
    end
  end

  describe '#scopes' do
    describe 'submitted' do
      let!(:offer1) { Fabricate(:offer, submitted_at: Time.zone.now) }
      let!(:offer2) { Fabricate(:offer, submitted_at: nil) }
      let!(:offer3) { Fabricate(:offer, submitted_at: nil) }
      it 'returns submitted offers' do
        expect(Offer.submitted).to match_array [offer1]
      end
    end
  end

  describe '#from_participant' do
    let(:order) { Fabricate(:order, buyer_id: 'buyer1', buyer_type: 'user', seller_id: 'seller1', seller_type: 'gallery') }
    let(:seller_offer) { Fabricate(:offer, order: order, from_id: 'seller1', from_type: 'gallery') }
    let(:buyer_offer) { Fabricate(:offer, order: order, from_id: 'buyer1', from_type: 'user') }
    let(:ufo_offer) { Fabricate(:offer, order: order, from_id: 'marse', from_type: 'ufo') }
    it 'returns buyer for buyer_offer' do
      expect(buyer_offer.from_participant).to eq Order::BUYER
    end
    it 'returns seller for seller_offer' do
      expect(seller_offer.from_participant).to eq Order::SELLER
    end
    it 'raises error for offer that is not from a buyer or seller' do
      expect { ufo_offer.from_participant }.to raise_error do |error|
        expect(error.type).to eq :validation
        expect(error.code).to eq :unknown_participant_type
      end
    end
  end

  describe '#to_participant' do
    let(:order) { Fabricate(:order, buyer_id: 'buyer1', buyer_type: 'user', seller_id: 'seller1', seller_type: 'gallery') }
    let(:seller_offer) { Fabricate(:offer, order: order, from_id: 'seller1', from_type: 'gallery') }
    let(:buyer_offer) { Fabricate(:offer, order: order, from_id: 'buyer1', from_type: 'user') }
    let(:ufo_offer) { Fabricate(:offer, order: order, from_id: 'marse', from_type: 'ufo') }
    it 'returns seller for buyer_offer' do
      expect(buyer_offer.to_participant).to eq Order::SELLER
    end
    it 'returns buyer for seller_offer' do
      expect(seller_offer.to_participant).to eq Order::BUYER
    end
    it 'raises error for offer that is not from a buyer or seller' do
      expect { ufo_offer.from_participant }.to raise_error do |error|
        expect(error.type).to eq :validation
        expect(error.code).to eq :unknown_participant_type
      end
    end
  end
end
