class Gravity < Artemis::Client
  def self.authenticated
    with_context(headers: { "Authorization" => "Bearer #{ENV['GRAVITY_JWT']}" })
  end
end
