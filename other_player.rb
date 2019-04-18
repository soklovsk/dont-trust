class OtherPlayer
  attr_accessor :id, :nick, :lvl, :profession, :driver

  def initialize(element, driver)
    @driver = driver
    @id = element.attribute(:id).delete('other')
    n = /<b>.*?<\/b>/.match(element.attribute(:tip))[0]
    if n.nil?
      @nick = nil
      puts Game.log :warning,"Couldn't find player's nick! (:tip attribute: #{element.attribute(:tip)}"
    end
    @nick = n.gsub(/<\/?b>/, '')
    l = /Lvl: ?\d+./.match(element.attribute(:tip))[0]
    l.delete!('Lvl: ')
    @lvl = l.delete(l[-1]).to_i
    if @lvl.nil?
      @lvl = 0
      puts Game.log :warning,"Couldn't find player's level! (:tip attribute: #{element.attribute(:tip)}"
    end
    prof = l[-1] # profession signatures: m, p, w, t, h, b (magician, paladin, warrior, tracker, hunter, blade runner)
    case prof
      when 'm'
        @profession = 'magician'
      when 'p'
        @profession = 'paladin'
      when 'w'
        @profession = 'warrior'
      when 't'
        @profession = 'tracker'
      when 'h'
        @profession = 'hunter'
      when 'b'
        @profession = 'blade runner'
      else
        @profession = 'unknown'
        puts Game.log :warning,"Couldn't find player's profession! (:tip attribute: #{element.attribute(:tip)}"
    end
  end
  def driver_element
    @driver.find_element(id: @id)
  end
end