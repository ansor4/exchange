Fabricator(:shipment) do
  external_id { SecureRandom.hex(10) }
  price_currency { 'EUR' }
  price_cents { rand 1000..500000 }
  line_item { Fabricate(:line_item) }
end
