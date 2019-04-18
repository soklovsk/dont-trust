class NotificationSender
  attr_accessor :enabled # enabled = true - send notifications; false - don't send.
  attr_reader :token # unique token generated in app

  def initialize(token)
    @token = token
    enable
  end

  def enable
    @enabled = true
  end
  def disable
    @enabled = false
  end
end