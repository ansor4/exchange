module QueryHelper
  CREATE_ORDER = %(
    mutation($input: CreateOrderWithArtworkInput!) {
      createOrderWithArtwork(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
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
  ).freeze

  SET_SHIPPING = %(
    mutation($input: SetShippingInput!) {
      setShipping(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
              requestedFulfillment {
                __typename
                ... on Ship {
                  addressLine1
                }
                ... on Pickup {
                  fulfillmentType
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
  ).freeze

  SELECT_ARTA_SHIPPING_OPTION = %(
    mutation($input: SelectShippingOptionInput!) {
      selectShippingOption(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
              state
              shippingTotalCents
              lineItems {
                edges {
                  node {
                    id
                    priceCents
                    listPriceCents
                    shippingQuoteOptions {
                      edges {
                        node {
                          id
                          tier
                          name
                          isSelected
                        }
                      }
                    }
                  }
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
  ).freeze

  SET_CREDIT_CARD = %(
    mutation($input: SetPaymentInput!) {
      setPayment(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
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
  ).freeze

  SUBMIT_ORDER = %(
    mutation($input: SubmitOrderInput!) {
      submitOrder(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
              state
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
  ).freeze

  APPROVE_ORDER = %(
    mutation($input: ApproveOrderInput!) {
      approveOrder(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
              state
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
  ).freeze

  FULFILL_ORDER = %(
    mutation($input: FulfillAtOnceInput!) {
      fulfillAtOnce(input: $input) {
        orderOrError {
          ... on OrderWithMutationSuccess {
            order {
              id
              state
              lineItems{
                edges{
                  node{
                    fulfillments{
                      edges{
                        node{
                          courier
                          trackingId
                          estimatedDelivery
                        }
                      }
                    }
                  }
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
  ).freeze
end
