require 'rails_helper'
require 'support/gravity_helper'

describe Gravity, type: :services do
  let(:seller_id) { 'partner-1' }
  let(:partner) { { _id: 'partner-1', billing_location_id: 'location-1' } }
  describe '#fetch_partner' do
    it 'calls the /partner endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all")
      Gravity.fetch_partner(seller_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/partner/#{seller_id}/all")
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, %r{partner\/#{seller_id}}).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          Gravity.fetch_partner(seller_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :unknown_partner
        end
      end
    end
  end

  describe '#fetch_partner_locations' do
    let(:valid_locations) { [{ country: 'US', state: 'NY', postal_code: '12345' }, { country: 'US', state: 'FL', postal_code: '67890' }] }
    let(:invalid_location) { [{ country: 'US', state: 'Floridada' }] }
    let(:base_params) { { private: true, page: 1, size: 20 } }
    let(:tax_only_params) { base_params.merge(address_type: ['Business', 'Sales tax nexus']) }

    context 'calls the correct location Gravity endpoint' do
      context 'without tax_only flag' do
        it 'does not filter by address type' do
          expect(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations", params: base_params).and_return(valid_locations)
          Gravity.fetch_partner_locations(seller_id)
        end
      end

      context 'with tax_only flag' do
        it 'filters by address type' do
          expect(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations", params: tax_only_params).and_return(valid_locations)
          Gravity.fetch_partner_locations(seller_id, tax_only: true)
        end
      end
    end

    context 'with at least one partner location' do
      context 'with valid partner locations' do
        it 'returns new addresses for each location' do
          allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations", params: tax_only_params).and_return(valid_locations)
          partner_addresses = Gravity.fetch_partner_locations(seller_id, tax_only: true)
          partner_addresses.each { |ad| expect(ad).to be_a Address }
        end
      end
    end

    context 'with no partner locations' do
      it 'raises error' do
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations", params: base_params).and_return([])
        expect { Gravity.fetch_partner_locations(seller_id) }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :missing_partner_location
          expect(error.data[:partner_id]).to eq seller_id
        end
      end
    end

    context 'with more than 10 partner locations' do
      it 'correctly returns all locations' do
        first_location_group = []
        20.times.each { first_location_group << { country: 'US', state: 'FL', postal_code: '67890' } }

        second_location_group = []
        7.times.each { second_location_group << { country: 'US', state: 'MA', postal_code: '67890' } }

        allow(Adapters::GravityV1).to receive(:get).with(
          "/partner/#{seller_id}/locations",
          params: tax_only_params
        ).and_return(first_location_group)

        allow(Adapters::GravityV1).to receive(:get).with(
          "/partner/#{seller_id}/locations",
          params: tax_only_params.merge(page: 2)
        ).and_return(second_location_group)

        locations = Gravity.fetch_partner_locations(seller_id, tax_only: true)
        expect(locations.length).to eq(27)
      end
    end
  end

  describe '#get_merchant_account' do
    let(:partner_merchant_accounts) { [{ external_id: 'ma-1' }, { external_id: 'some_account' }] }
    context 'with merchant account' do
      before do
        allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: seller_id }).and_return(partner_merchant_accounts)
      end
      it 'calls the /merchant_accounts Gravity endpoint' do
        Gravity.get_merchant_account(seller_id)
        expect(Adapters::GravityV1).to have_received(:get).with('/merchant_accounts', params: { partner_id: seller_id })
      end
      it "returns the first merchant account of the partner's merchant accounts" do
        result = Gravity.get_merchant_account(seller_id)
        expect(result).to be(partner_merchant_accounts.first)
      end
    end

    it 'raises an error if the partner does not have a merchant account' do
      allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: seller_id }).and_return([])
      expect { Gravity.get_merchant_account(seller_id) }.to raise_error do |error|
        expect(error).to be_a(Errors::InternalError)
        expect(error.type).to eq :internal
        expect(error.code).to eq :gravity
      end
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, /merchant_accounts\?partner_id=#{seller_id}/).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          Gravity.get_merchant_account(seller_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :missing_merchant_account
        end
      end
    end
  end

  describe '#get_credit_card' do
    let(:credit_card_id) { 'cc-1' }
    let(:credit_card) { { external_id: 'card-1', customer_account: { external_id: 'cust-1' }, deactivated_at: nil } }
    it 'calls the /credit_card Gravity endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/credit_card/#{credit_card_id}").and_return(credit_card)
      Gravity.get_credit_card(credit_card_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/credit_card/#{credit_card_id}")
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, %r{credit_card\/#{credit_card_id}}).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          Gravity.get_credit_card(credit_card_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :credit_card_not_found
        end
      end
    end
  end

  describe '#get_artwork' do
    let(:artwork_id) { 'some-id' }
    it 'calls the /artwork endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/artwork/#{artwork_id}")
      Gravity.get_artwork(artwork_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/artwork/#{artwork_id}")
    end
    context 'with failed gravity call' do
      it 'returns nil' do
        expect(Adapters::GravityV1).to receive(:get).and_raise(Adapters::GravityError, 'timeout')
        expect(Gravity.get_artwork(artwork_id)).to be_nil
      end
    end
  end

  describe '#get_user' do
    let(:user_id) { 'some-id' }
    it 'calls the /userid endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/user/#{user_id}")
      Gravity.get_user(user_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/user/#{user_id}")
    end
    context 'with failed gravity call' do
      it 'returns nil' do
        expect(Adapters::GravityV1).to receive(:get).and_raise(Adapters::GravityError, 'timeout')
        expect(Gravity.get_user(user_id)).to be_nil
      end
    end
  end

  describe '#fetch_all' do
    it 'paginates until there are no more items' do
      allow(Adapters::GravityV1).to receive(:get).with('/test', params: { page: 1, size: 20 }).and_return([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
      allow(Adapters::GravityV1).to receive(:get).with('/test', params: { page: 2, size: 20 }).and_return([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
      allow(Adapters::GravityV1).to receive(:get).with('/test', params: { page: 3, size: 20 }).and_return([1, 2, 3])

      response = Gravity.fetch_all('/test', {})
      expect(response.length).to eq 43
    end

    it 'only makes one call if there are less than 10 items' do
      allow(Adapters::GravityV1).to receive(:get).with('/test', params: { page: 1, size: 20 }).and_return([1, 2, 3])

      response = Gravity.fetch_all('/test', {})
      expect(response.length).to eq 3
    end

    it 'returns no items' do
      allow(Adapters::GravityV1).to receive(:get).with('/test', params: { page: 1, size: 20 }).and_return([])

      response = Gravity.fetch_all('/test', {})
      expect(response.length).to eq 0
    end
  end

  describe '#debit_commission_exemption' do
    let(:buyer_id) { 'buyer1' }
    let(:seller_id) { 'seller1' }
    let(:order_mode) { Order::BUY }
    let(:order) do
      Fabricate(
        :order,
        mode: order_mode,
        buyer_id: buyer_id,
        fulfillment_type: Order::SHIP,
        credit_card_id: 'cc1',
        seller_id: seller_id,
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'Tehran',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_country: 'IR',
        items_total_cents: 1000_00
      )
    end
    let(:artwork) { gravity_v1_artwork(_id: 'a-1', current_version_id: '1') }
    let(:stub_artwork_request) { stub_request(:get, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1").to_return(status: 200, body: artwork.to_json) }
    let!(:line_item1) { Fabricate(:line_item, order: order, quantity: 1, list_price_cents: 1000_00, artwork_id: 'a-1', artwork_version_id: '1') }
    it 'tktk' do
      # allow(Gravity).to receive(:debit_commission_exemption).and_return(1000)
      # allow(GravityGraphql).to receive_message_chain(:authenticated, :debit_commission_exemption).with({:input=>{:partnerId=>"seller1", :exemption=>{:amountMinor=>100000, :currencyCode=>"USD"}, :referenceId=>order.id, :notes=>"test"}})
      stub_request(:post, "https://gravity.biz")
      response = Gravity.debit_commission_exemption(order.seller_id, order.items_total_cents, order.currency_code, order.id, "test")
      byebug
    end
  end
end
