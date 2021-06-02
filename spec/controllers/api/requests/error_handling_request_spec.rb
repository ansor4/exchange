require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'ErrorType' do
    let(:auth_headers) { jwt_headers(user_id: 'user-id', partner_ids: %w[p1 p2], roles: []) }
    let(:mutation_input) do
      {
        artworkId: 'test'
      }
    end
    let(:mutation) do
      <<-GRAPHQL
        mutation($input: CreateOrderWithArtworkInput!) {
          createOrderWithArtwork(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  buyer {
                    ... on Partner {
                      id
                    }
                  }
                  seller {
                    ... on User {
                      id
                    }
                  }
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    context 'StandardError' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise('something went wrong')
        post '/api/graphql', params: { query: mutation, variables: { input: mutation_input } }, headers: auth_headers
      end
      it 'returns 500' do
        expect(response.status).to eq 500
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(error['message']).to eq 'something went wrong'
        expect(error['extensions']['type']).to eq 'internal'
        expect(error['extensions']['code']).to eq 'generic'
        expect(error['extensions']['data']['message']).to eq 'something went wrong'
      end
    end

    context 'ActiveRecord::RecordNotFound' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise(ActiveRecord::RecordNotFound, 'cannot find')
        post '/api/graphql', params: { query: mutation, variables: { input: mutation_input } }, headers: auth_headers
      end
      it 'returns 404' do
        expect(response.status).to eq 404
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(error['message']).to eq 'type: validation, code: not_found, data: {:message=>"cannot find"}'
        expect(error['extensions']['type']).to eq 'validation'
        expect(error['extensions']['code']).to eq 'not_found'
        expect(error['extensions']['data']['message']).to eq 'cannot find'
      end
    end

    context 'ActionController::ParameterMissing' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise(ActionController::ParameterMissing, 'id')
        post '/api/graphql', params: { query: mutation, variables: { input: mutation_input } }, headers: auth_headers
      end
      it 'returns 400' do
        expect(response.status).to eq 400
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(error['type']).to eq 'validation'
        expect(error['code']).to eq 'missing_param'
        expect(error['data']['field']).to eq 'id'
      end
    end

    context 'Errors::ApplicationError' do
      context 'raised from a query' do
        let(:order) { Fabricate(:order, buyer_type: 'user', buyer_id: 'user-id') }
        let(:query) do
          <<-GRAPHQL
            query($id: ID) {
              order(id: $id) {
                id
              }
            }
          GRAPHQL
        end

        before do
          expect(Order).to receive(:find_by!).and_raise(Errors::ValidationError, :invalid_order)
          allow(Raven).to receive_messages({ user_context: nil, tags_context: nil, capture_exception: nil })

          post '/api/graphql', params: { query: query, variables: { id: order.id.to_s } }, headers: auth_headers
        end

        it 'returns 400 for a validation error' do
          expect(response.status).to eq 400
        end

        it 'returns formatted the error' do
          result = JSON.parse(response.body)
          expect(result).to eq(
            {
              'errors' => [
                {
                  'message' => 'type: validation, code: invalid_order, data: ',
                  'extensions' => {
                    'code' => 'invalid_order',
                    'data' => nil,
                    'type' => 'validation'
                  }
                }
              ]
            }
          )
        end

        it 'sets Sentry context but does not capture the error in Sentry' do
          expect(Raven).to have_received(:user_context).with(id: 'user-id')
          expect(Raven).to have_received(:tags_context).with(partner_ids: 'p1, p2')
          expect(Raven).to_not have_received(:capture_exception)
        end
      end

      context 'raised from a mutation' do
        before do
          expect(OrderService).to receive(:create_with_artwork!).and_raise(Errors::ProcessingError, :artwork_version_mismatch)
          allow(Raven).to receive_messages({ user_context: nil, tags_context: nil, capture_exception: nil })

          post '/api/graphql', params: { query: mutation, variables: { input: mutation_input } }, headers: auth_headers
        end

        it 'returns 200' do
          expect(response.status).to eq 200
        end

        it 'returns formatted the error' do
          result = JSON.parse(response.body)
          expect(result).to eq(
            {
              'data' => {
                'createOrderWithArtwork' => {
                  'orderOrError' => {
                    'error' => {
                      'code' => 'artwork_version_mismatch',
                      'data' => 'null',
                      'type' => 'processing'
                    }
                  }
                }
              }
            }
          )
        end

        it 'captures the error in Sentry' do
          expect(Raven).to have_received(:user_context).with(id: 'user-id')
          expect(Raven).to have_received(:tags_context).with(partner_ids: 'p1, p2')
          expect(Raven).to have_received(:capture_exception)
        end
      end
    end
  end
end
