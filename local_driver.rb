extend Game
require 'selenium-webdriver'

class LocalDriver
  # It's supposed to be only 1 LocalDriver object in 1 process run.
  # It should be created in margobot.rb
  # Usage is quite simple - one driver can handle single account (it might be forbidden to run more than 1 account on a single ip. (i think that you can't use the bot as well)).
  #
  attr_accessor :amount_of_kills, :bot_manager
  attr_reader :start_time

  def initialize(bot_manager = nil, driver = nil)
    @start_time = Time.now
    @bot_manager = bot_manager
    @amount_of_kills = 0
    @driver = driver if driver
    @driver = Selenium::WebDriver.for :firefox unless driver # setting up a driver
    ## every method missing will be send to @driver (see below)
    #
    manage.timeouts.page_load=360
    puts Game.log :debug,'LocalDriver has been set up successfully.'

    # Set up site
    get 'https://www.margonem.pl'
    get 'https://www.margonem.pl'
    puts Game.log :debug,'LocalDriver has loaded main page of the game.'

  end

  def log_in(username, password)
    sleep 1
    find_element(class: 'menu-login').click
    username_field = find_element(:id, 'popup-login-input')
    username_field.send_keys(username)
    password_field = find_element(:id, 'popup-login-password')
    password_field.send_keys(password)
    sleep(0.2)
    find_element(class: 'btn-pink2').click
    #
    sleep 2.5
    #
    if find_elements(class: 'select-char').empty? # this field appears after logging in. If the data was incorrect, then there's no this field. (Logging in wasn't successful)
      puts Game.log :error,'LoggingError'
      raise "Username: #{username} or password: #{password.gsub(/./,'*')} is probably incorrect. If you typed correct data, please contact developer."
    end
    sleep(1)
    puts Game.log :debug,'Logged in.'
    username
  end # logs in on the main page

  def switch_hero(nick)
    sleep(1)
    unless current_url == 'https://www.margonem.pl/'
      get 'https://www.margonem.pl/' # go back to main page
    end
    sleep(1)
    return true if nick == ''
    # waiting page for load
    sleep 0.2 until find_element(class: 'select-char')
    #
    ## charc
    #
    find_element(class: 'select-char').click
    #
    # now there is new window where specific hero can be chosen
    options = find_elements(class: 'charc')
    exit = false
    options.each { |option|
      if /#{nick.downcase}/.match(option.attribute(:'data-nick').downcase)
        option.click
        exit = true
      end
    }
    unless exit
      puts Game.log :warning,"Cannot find given nick on list: #{nick} "
    end
    sleep 1
    find_element(class: 'enter-game').click
    while find_elements(id: 'bagc').empty?
      sleep(0.5)
    end # waiting for loading page.
    #
    #
    #
    # it's just temporarily - when there will be method checking if the page has been loaded - replace code below.
    while find_elements(:css, "[id^=\"item\"]").size < 2
      sleep 0.1
    end
    # !!! !!! !!!
    #
    # sometimes after logging in there is pop-up window with advertisements.
    # checking if there is one and closing it
    if find_elements(class: 'news-panel')[0]
      while find_elements(class: 'news-panel')[0].displayed?
        find_element(class: 'closebut').click
        sleep 1
      end
    end
    #
    #
    #
    # return value
    nick
  end


  def distance(element1, element2)
    coords1 = element1
    coords2 = element2
    coords1 = element1.location unless element1.is_a? Array
    coords2 = element2.location unless element1.is_a? Array
    #
    top = coords1[1] - coords2[1]
    left = coords1[0] - coords2[0]
    #
    # actual distance
    [Math.sqrt(left**2 + top**2), top.abs, left.abs]
  end # returns [3 values] how many pixels in straight line [and x, y distances] are 2 elements far away.
  # position1 and position2 are arrays like:
  # position1 = [pos_top1, pos_left2]
  # pos_top and pos_left can be extracted from element data (element.attribute(:style))
  #     example of +:style+ "
  #                             left: 1608px; top: 70px; z-index: 14;
  #                             background-image: url(\"http://legion.margonem.pl/obrazki/npc/tmp/132_1497783022tvynsq.gif\");
  #                             width: 80px; height: 90px;"   "
  # In this case array1 is [70, 1608] # # #
  def touch?(obj1, obj2, x = 1, y = 1, round = true)
    # x,y params are used to change the radius of touching. Sometimes, when this method is called, caller needs to know if element touches its (for example x1 = 0 and x2 = 1 should return true)
    # but sometimes elements has to have common space (has to cover each ones). So in this case x1 = 0 and x2 = 1 should return false.
    # So, when you need to determine if it TOUCHES, x and y should be 1
    # When it has to cover, the params should be 0.
    #
    # Also, when you need to check if the element1 is inside element 2, x should be the width and y should be length of smaller element
    # But if it's just about touching/covering, the params can be both 1 or both 0.
    #
    # When round == true and edge is less than 32px, it's being set to 32 pixels.
    #
    stt = Time.now # start time.
    if obj1.is_a?(String)
      obj1 = find_elements(id: obj1)[0]
    end
    if obj2.is_a?(String)
      obj2 = find_elements(id: obj2)[0]
    end

    unless obj1.is_a?(Selenium::WebDriver::Element) and obj2.is_a?(Selenium::WebDriver::Element)
      puts Game.log :warning, "Wrong argument type (Given: #{obj1.class} and #{obj2.class}. Expected String or Selenium::WebDriver::Element.)"
      return false
    end
    # l1, l2, k1, k2 are straights with the sides of the rectangle 1 (l1 and l2 vertical, k1 and k2 horizontal)
    # l3, l4, k3, k4 are straights with the sides of the rectangle 2 (l3 and l4 vertical, k3 and k4 horizontal)
    # If l1 is between l3 and l4 (or l1 == l3 or l1 == l4) + k1 is between k3 and k4 - there's touch
    # And similarly in other cases.
    # Point returned by location method is referring to the top left hand corner of the element
    obj1x = obj1.location[0] # x coordinate of the point
    obj1y = obj1.location[1] # y coordinate of the point
    obj2x = obj2.location[0] # x coordinate of the point
    obj2y = obj2.location[1] # y coordinate of the point
    width1 = obj1.size[0]
    height1 = obj1.size[1]
    width2 = obj2.size[0]
    height2 = obj2.size[1]
    if round
      if width1 < 32
        width1 = 32
      end
      if width2 < 32
        width2 = 32
      end
      if height1 < 32
        height1 = 32
      end
      if height2 < 32
        height2 = 32
      end
    end# if round
    # # some mobs are smaller than 32 px (32px is length and width of 1 field) but hero can't move closer to them (it won't touch element, but it will be able to attack it.)
    x1 = obj1x - x # vertical straight passing through the point of +obj1+
    x2 = obj1x + width1 + x # vertical straight not passing through the point of +obj1+
    y1 = obj1y - y # horizontal straight passing through the point of +obj1+
    y2 = obj1y + height1 + y # horizontal straight not passing through the point of +obj1+
    x3 = obj2x # vertical straight passing through the point of +obj2+
    x4 = obj2x + width2 # vertical straight not passing through the point of +obj2+
    y3 = obj2y # horizontal straight passing through the point of +obj2+
    y4 = obj2y + height2 # horizontal straight not passing through the point of +obj2+

    puts Game.log :debug,"Touch method returned in #{Time.now - stt}s."
    if x1 > x4 or x2 < x3 or y1 > y4 or y2 < y3
      return false
    end
    true
  end # returns true, when obj1 touches obj2. x and y are additional params,
                                     # which can be used to determine, how deeply object 1 has to cover obj2 in order to return true.
  def fight?
    a = find_elements(id: 'battleclose') # battle window has id: 'battle'. When battle window is open there ALWAYS is a button with 'battleclose' id.
    # Battle window can be opened by clicking mob and closed by clicking 'close battle' button with id: 'battleclose'
    if a.empty?
      false # there's no battle
    elsif a[0].displayed?
      true
    else
      false
    end
  end
  def spawned_mob(group)
    spawned_mobs = []
    mob_elements = []
    group.each do |id|
      unless id.nil?
        puts Game.log :debug,"id of mob to check #{id}"
        if /npc/.match id.to_s
          f = find_elements(id: id.to_s)
        else
          f = find_elements(id: "npc#{id}")
        end
        unless f.empty?
         mob_elements << f
        end
      end
    end
    if mob_elements.empty?
      false # there's no either ghost or real mob.
    else
      i = 0
      mob_elements.each do
        spawned_mobs[i] = Mob.new("npc#{group[i]}", @driver) # +x+ is nested array
        i+=1
      end
      if spawned_mobs[0].real? # it all spawned in the same time
        puts Game.log :debug,"Mob(s) #{group} are spawned."
        return spawned_mobs # mobs are spawned and real - return Mob objects.
      else
        return false # if the mob isn't real - return false (it's actually not spawned).
      end
    end
  end # input argument is array with ids of all mobs which can spawn (in group!), returns  Mob objects.
  def get_group
    mobs_id = []
    troops = find_elements(class: 'troop')
    # Array with ALL troop (including player). Although it's easy to distinguish which is hero, because hero id is like "troop1234" and mob id:"troop-1234".
    troops.each do |troop|
      if /troop-\d*/.match(troop.attribute(:id))
        mobs_id << /\d+/.match(troop.attribute(:id))[0].to_i
      end
    end
    puts Game.log :debug,"NPC is in group that counts #{mobs_id.size} mobs. ID of mobs: #{mobs_id}"
    mobs_id
  end # return attacked group.
  def map_loaded?
    begin
      script('return map.loaded')
    rescue
      false
    end
  end

  def find_closest_element(object, elements) # searching closest element from object.
    unless elements.is_a?(Array)
      puts Game.log :warning,"Wrong argument type (elements). Expected Array, given #{elements.class}."
      return elements
    end
    unless object.is_a?(Item) or object.is_a?(Selenium::WebDriver::Element)
      puts Game.log :warning,"Wrong argument type (object). Expected Item or Selenium::WebDriver::Element, given #{object.class}."
      return elements
    end
    if elements.size == 1
      puts Game.log :debug,"There's only one element on given array."
      return elements[0]
    end # if there's one element, it is the closest one.
    distances = []
    elements.each do |element|
      # distance method accepts only Selenium::WebDriver::Element elements.
      # but let's accept also Item and Mob, because it's not really convenient to call this method with Element.
      # To get Item's element, we need to call .driver_element function, voila!.
      # To get Mob - exactly the same as the Item.
      if element.is_a? Item or element.is_a? Mob
        distances << distance(object, element.driver_element)[0]
      elsif element.is_a?(Selenium::WebDriver::Element)
        distances << distance(object, element)[0]
      else
        puts Game.log :warning,"Wrong type of element on array given. Expected: Array[Item, Mob or Selenium::WebDriver::Element]. Given: Array[#{element.class}]."
      end
    end
    # now we have +distances+ array. First element of this array corresponds to first element from elements array, etc.
    # lets find the closest distance (lowest value)
    #
    # to do code more neat, we return elements[i], where i is index of lowest value from distances.
    # So, we return this, what we were asked about.
    ret = elements[distances.index(distances.min)] # asked value.
    puts Game.log :debug,"Returning #{ret}."
    ret
  end
  def get_all_items_ids
    puts Game.log :debug,'Getting list of all items belonging to hero.'
    until map_loaded?
      sleep 0.1
    end
    items = script('return Object.keys(g.item)')
    hero_id = script('return hero.pid').to_s
    hero_items = []
    items.each do |item_id|
      hero_items << item_id.to_s if script("return g.item[#{item_id}].own").to_s == hero_id
    end
    puts Game.log :info,"Hero own #{hero_items.size} items."
    hero_items
  end # get Selenium::WebDriver::Element objects of every item in game.

  def press_key(key,time)
    unless time == 0
      if time < 0
        puts Game.log :warning,"Warning: Wrong time given (#{time}). Time has been changed to #{time.abs}."
        time = time.abs
      end
      #
      # simulating human-likely behaviour - the key press times have to differ
      percent = rand 7
      value = time/100.0 * percent
      time += value
      return false if key.nil?    # no key
      return false if key.empty?  # empty string
      puts Game.log :debug,"Pressing key #{key} for #{time}s."
      action.key_down(key).perform # press key
      sleep(time)
      action.key_up(key).perform  # release key
      sleep(0.002)
    end
  end # send key to driver for concrete period of time.

  def close_battle
    a = []
    while a[0].nil?
      a = find_elements class: 'win' # battle's finished when this element becomes visible
      sleep 0.05
    end # waiting for end of battle (when it's ended there appears element with 'win' class.)
    begin
      find_element(id: 'battleclose').click # close battle after end of it.
      stt = Time.now
      until find_elements(id: 'battle')[0] or Time.now > stt + 2
        break unless find_elements(id: 'battle')[0].displayed?
        find_element(id: 'battleclose').click
        sleep 0.05
      end
    rescue
      false
    end
    sleep 0.1
  end # close battle window.
  def other_players?
    others = find_elements(class: 'other')
    if others.empty?
      false
    else
      true
    end
  end
  def list_of_players
    require_relative 'other_player'
    list_of_players = []
    unless find_elements(class: 'other').empty?
      players = find_elements(class: 'other')
      players.each do |p|
        player = OtherPlayer.new(p, self)
        list_of_players << player
      end
    end
    list_of_players
  end
  def other_player(player_reaction, group)
    def print_players(players)
      unless players.empty?
        players.each do |player|
          puts Game.log :info,"Player #{player.nick} (#{player.lvl}, #{player.profession}) occupies mob."
        end
      end
    end # prints log with all other players data.
    def dazed?
      if find_elements(id: 'dazed')[0]
        if find_elements(id: 'dazed')[0].displayed?
          x = rand(270) + 30
          puts Game.log :debug,"Too long inactivity. Waiting #{x} seconds to refresh."
          sleep(x)
          navigate.refresh
          puts Game.log :debug,'Refreshed.'
          sleep(10)
        end
      end # after some time of absence, player has been logged off.
    end # when player is absent for a while, he's logged off (there is a window hovering game, after refreshing it disappears).

    if player_reaction
      require_relative 'other_player'
      spawned = false
      other_players = list_of_players
      print_players(other_players)
      if list_of_players.empty?
        return
      end
      until list_of_players.empty?
        if list_of_players.size != other_players.size
          other_players = list_of_players
          print_players(other_players)
        end # printing list of other players if there is someone new.
        if not spawned and spawned_mob(group)
          puts Game.log :debug,"Mob(s) #{group} spawned!"
          spawned = true
        end # We need this announcement only once, when mob spawns.
        chat_monitor
        # It's needed to check is other player(s) killed it.
        if spawned and find_elements(id: "npc#{group[0]}")[0].nil? # if mob was spawned but now we can't find its' element means that someone killed it.
          # if there was only 1 player - we know who killed mob. Otherwise it could be one of present players or group of players.
          if other_players.size > 1
            puts Game.log :info,"Mob(s) #{group} was/were killed by someone else!"
            puts Game.log :info,'List of present players: '
            print_players(other_players)
            Game.save_data("Kills list", "#{Time.now.strftime('%F %T')} Mob was killed by someone else.\n", "#{@bot_manager.dir}/")
          else
            puts Game.log :info,"Mob(s) #{group} was(were) killed by #{other_players[0].nick}(#{other_players[0].lvl}, #{other_players[0].profession})"
            Game.save_data("Kills list", "#{Time.now.strftime('%F %T')}: Mob was killed by #{other_players[0].nick}(#{other_players[0].lvl}, #{other_players[0].profession}).\n", "#{@bot_manager.dir}/")
          end
          spawned = false
        end
        sleep(1)
      end # end of loop waiting for player to be alone.
      puts Game.log :info,'No other players.'
    end # end of body
  end
  def change_bag(bag_id)
    if find_elements(id: bag_id)[0].nil?
      puts Game.log :warning,"Bag #{bag_id} doesn't exist."
    else
      find_elements(id: bag_id)[0].click
      puts Game.log :debug,"Bag changed to #{bag_id}."
    end
  end

  def back
    puts Game.log :debug,'Getting page through get method in LocalDriver.'
    begin
      navigate.back
    rescue StandardError => error
      Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      sleep(60)
      navigate.refresh
    end
  end
  def get(page)
    puts Game.log :debug,'Getting page through get method in LocalDriver.'
    begin
      @driver.get page
    rescue StandardError => error
      Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      sleep(60)
      @driver.get page
    end
  end
  def current_map_name
    begin
      script 'return map.name'
    rescue
      nil
    end
  end
  def current_map_id
    begin
      script('return map.id').to_i
    rescue
      nil
    end
  end
  def method_missing(m, *args)
    @driver.send(m, *args)
  end # to avoid redefining methods like send_key, click, etc.

  private

end # end of LocalDriver class.