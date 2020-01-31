class Gravity < Artemis::Client
  def self.authenticated
    with_context( headers: {'X-XAPP-TOKEN' => Rails.application.config_for(:gravity)['xapp_token']} )
  end
end
