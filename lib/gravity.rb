module Gravity
  def self.fetch_partner(partner_id)
    Adapters::GravityV1.get("/partner/#{partner_id}/all")
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_partner, partner_id: partner_id)
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_merchant_account(partner_id)
    merchant_account = Adapters::GravityV1.get('/merchant_accounts', params: { partner_id: partner_id }).first
    raise Errors::ValidationError.new(:missing_merchant_account, partner_id: partner_id) if merchant_account.nil?

    merchant_account
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:missing_merchant_account, partner_id: partner_id)
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_credit_card(credit_card_id)
    Adapters::GravityV1.get("/credit_card/#{credit_card_id}")
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:credit_card_not_found, credit_card_id: credit_card_id)
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_artwork(artwork_id)
    Adapters::GravityV1.get("/artwork/#{artwork_id}")
  rescue Adapters::GravityError, StandardError => e
    Rails.logger.warn("Could not fetch artwork #{artwork_id} from gravity: #{e.message}")
    nil
  end

  def self.fetch_partner_locations(partner_id, tax_only: false)
    url = "/partner/#{partner_id}/locations"
    params = { private: true }
    params = params.merge(address_type: ['Business', 'Sales tax nexus']) if tax_only
    locations = Gravity.fetch_all(url, params)

    raise Errors::ValidationError.new(:missing_partner_location, partner_id: partner_id) if locations.blank?

    locations.map { |loc| Address.new(loc) }
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_partner, partner_id: partner_id)
  rescue Adapters::GravityError
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.deduct_inventory(line_item)
    if line_item.edition_set_id
      Adapters::GravityV1.put("/artwork/#{line_item.artwork_id}/edition_set/#{line_item.edition_set_id}/inventory", params: { deduct: line_item.quantity })
    else
      Adapters::GravityV1.put("/artwork/#{line_item.artwork_id}/inventory", params: { deduct: line_item.quantity })
    end
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_artwork, line_item_id: line_item.id)
  rescue Adapters::GravityError
    raise Errors::InsufficientInventoryError, line_item.id
  end

  def self.undeduct_inventory(line_item)
    if line_item.edition_set_id
      Adapters::GravityV1.put("/artwork/#{line_item.artwork_id}/edition_set/#{line_item.edition_set_id}/inventory", params: { undeduct: line_item.quantity })
    else
      Adapters::GravityV1.put("/artwork/#{line_item.artwork_id}/inventory", params: { undeduct: line_item.quantity })
    end
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_artwork, line_item_id: line_item.id)
  rescue Adapters::GravityError
    raise Errors::ProcessingError.new(:undeduct_inventory_failure, line_item_id: line_item.id)
  end

  def self.get_user(user_id)
    Adapters::GravityV1.get("/user/#{user_id}")
  rescue Adapters::GravityError, StandardError => e
    Rails.logger.warn("Could not fetch user #{user_id} from gravity: #{e.message}")
    nil
  end

  def self.fetch_all(url, params)
    items = []
    page = 1
    size = 20

    loop do
      params = params.merge(page: page, size: size)
      new_items = Adapters::GravityV1.get(url, params: params)
      items += new_items if new_items
      page += 1
      break if new_items.blank? || new_items.size < size
    end
    items
  end

  def self.debit_commission_exemption(partner_id, amount_minor, currency_code, reference_id, notes)
    byebug
    mutation_args = {
      input: {
        partnerId: partner_id,
        exemption: { amountMinor: amount_minor, currencyCode: currency_code },
        referenceId: reference_id,
        notes: notes
      }
    }
    response = GravityGraphql.authenticated.debit_commission_exemption(mutation_args).to_h
    response['data']['debitCommissionExemption']
  # rescue Adapters::GravityNotFoundError
  #   raise Errors::ValidationError.new(:unknown_partner, partner_id: partner_id)
  # rescue Adapters::GravityError
  #   raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.credit_commission_exemption(partner_id, amount_minor, currency_code, reference_id, notes)
    mutation_args = {
      input: {
        partnerId: partner_id,
        exemption: { amountMinor: amount_minor, currencyCode: currency_code },
        referenceId: reference_id,
        notes: notes
      }
    }
    response = GravityGraphql.authenticated.credit_commission_exemption(mutation_args)
    response['data']['creditCommissionExemption']
  end
end
