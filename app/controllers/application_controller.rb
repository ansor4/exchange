class ApplicationController < ActionController::Base
  include ErrorHandler
  include AuthHandler
  include ArtsyAuth::Authenticated
  alias authorized_artsy_token? valid_admin?

  attr_reader :current_user

  before_action :set_paper_trail_whodunnit

  def set_current_user_for_error_reporting
    return if current_user.blank?

    Raven.user_context(id: current_user[:id])
    Raven.tags_context(partner_ids: current_user[:partner_ids]&.join(', '))
  end

  def admin_display_in_eastern_timezone
    Time.zone = 'Eastern Time (US & Canada)'
  end
end
