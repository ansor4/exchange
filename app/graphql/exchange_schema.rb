class ExchangeSchema < GraphQL::Schema
  max_depth 10
  max_complexity 300
  default_max_page_size 20

  mutation(Types::MutationType)
  query(Types::QueryType)

  rescue_from(Errors::ApplicationError) do |err, _obj, _args, _ctx, field|
    # Currently this only handles muatation errors; for other types we simply
    # bubble up the error.
    raise err unless field.owner == Types::MutationType

    Raven.capture_exception(err)

    { order_or_error: { error: Types::ApplicationErrorType.from_application(err) } }
  end
end
