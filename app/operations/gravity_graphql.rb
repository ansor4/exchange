class GravityGraphql < Artemis::Client
  after_execute do |data, errors, extensions|
    raise "GraphQL error: #{errors.to_json}" if errors.present?
  end

  def self.authenticated
    with_context( headers: {'X-XAPP-TOKEN' => Rails.application.config_for(:gravity)['xapp_token']} )
  end
end
