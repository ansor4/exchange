Fabricator(:shipping_quote) do
  external_id { 239698 }
  shipping_quote_request { Fabricate(:shipping_quote_request) }
  tier 'select'
  price_cents 4000
  price_currency 'USD'
end
