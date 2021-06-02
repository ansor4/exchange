module Api
  class GraphqlController < Api::BaseApiController
    before_action :set_current_user_for_error_reporting

    def execute
      variables = ensure_hash(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]
      context = {
        # Query context goes here, for example:
        current_user: current_user,
        user_agent: request.headers['User-Agent'],
        user_ip: request.headers['x-forwarded-for']
      }
      result = ExchangeSchema.execute(query, variables: variables, context: context, operation_name: operation_name, max_depth: 13)
      render json: result
    end

    private

    # Handle form data, JSON body, or a blank value
    def ensure_hash(ambiguous_param)
      case ambiguous_param
      when String
        if ambiguous_param.present?
          ensure_hash(JSON.parse(ambiguous_param))
        else
          {}
        end
      when Hash, ActionController::Parameters
        ambiguous_param
      when nil
        {}
      else
        raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
      end
    end
  end
end
