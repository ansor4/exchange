require 'rails_helper'

RSpec.describe Shipment, type: :model do
  let(:shipment) { Fabricate(:shipment) }

  describe 'validate status' do
    it 'raises invalid record for unsupported status' do
      expect do
        shipment.update!(status: 'eating banana')
      end.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Status is not included in the list')
    end
  end
end
