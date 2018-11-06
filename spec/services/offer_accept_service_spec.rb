require 'rails_helper'

describe OfferAcceptService, type: :services do
  describe '#process!' do
    subject(:call_service) { OfferAcceptService.new(offer: offer, order: order).process! }

    context 'with a approve-able order' do
      let(:order) { Fabricate(:order, state: Order::SUBMITTED) }
      let(:offer) { Fabricate(:offer, order: order) }

      it 'updates the state of the order' do
        expect do
          call_service
        end.to change { order.state }.from(Order::SUBMITTED).to(Order::APPROVED)
      end

      it 'instruments an approved order' do
        dd_statsd = double(Datadog::Statsd)
        allow(Exchange).to receive(:dogstatsd)
          .and_return(dd_statsd)
        allow(dd_statsd).to receive(:increment).with('order.approve')

        call_service

        expect(dd_statsd).to have_received(:increment).with('order.approve')
      end
    end

    context "when we can't approve the order" do
      let(:order) { Fabricate(:order, state: Order::PENDING) }
      let(:offer) { Fabricate(:offer, order: order) }

      it "doesn't instrument" do
        dd_statsd = double(Datadog::Statsd)
        allow(Exchange).to receive(:dogstatsd)
          .and_return(dd_statsd)
        allow(dd_statsd).to receive(:increment).with('order.approve')

        expect { call_service }.to raise_error(Errors::ValidationError)

        expect(dd_statsd).to_not have_received(:increment)
      end
    end
  end
end
