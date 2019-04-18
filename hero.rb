class Hero
  require_relative 'local_driver'
  require_relative 'mob'
  require_relative 'Map/map'
  extend Game

  attr_accessor :used_arrows, :main_bag_id, :bags, :status, :map, :chat_monitor, :driver, :bot # status says what's going on with this hero. It might be: false - something is really wrong - stop using it, :dazed - hero was beaten in a battle, :fine - everything is ok.
  attr_reader :all_items, :nick, :profession, :loots_stats


  def initialize(driver, bot = nil)
    @bot = bot
    @driver = driver
    @map = Map.new self
    @used_arrows = nil # it's needed to know if this value has been set already.
    # It's set from refill_arrows method in Bot class.
    @main_bag_id = nil
    @nick = @driver.script('return hero.nick')
    set_profession
    @all_items = []
    unless @loots_stats
      @loots_stats = []
      16.times { |n| @loots_stats[n] = 0 }
    end
    add_items
    sleep(1)
    @bags = []
    @all_items.each do |item|
      if item.type == :bag
        if  /id="bs\d">\d+<\/small>/.match(item.driver_element.attribute :innerHTML )
          if /id="bs0">\d+<\/small>/.match(item.driver_element.attribute :innerHTML )
            @main_bag_id = item.item_id
            puts Game.log :debug,"Main bag has been found - #{item.item_id}."
          end
          require_relative 'bag'
          @bags << Bag.new(item, all_items, self)
        end # only bags which are used have this driver element (id: bs\d).
        # It's mandatory to check, since some bags can be inside other bags and we have to treat it like items.
      end
    end # setting up @main_bag_id and @bags
    puts Game.log :debug,"Hero uses #{@bags.size} bags."

    # log about bag.
    puts Game.log :warning,'Couldn\'t find hero\'s main bag.' if @main_bag_id.nil?


    # setting up @used_arrows_id
    set_used_arrows if @profession == 'tracker' or @profession == 'hunter'

    @chat_monitor = ChatMonitor.new self
  end

  def dazed
    daze_left = @driver.find_elements id: 'dazeleft'
    unless daze_left
      @status = true
      return false
    end
    unless daze_left[0].displayed?
      @status = true
      return false
    end
    daze_left = daze_left[0].attribute :innerHTML
    daze_left = daze_left.scan(/<b>.*?<\/b>/)[-1]
    unless daze_left
      @status = true
      return false
    end
    @status = :dazed
    daze_left = daze_left.delete 'A-Za-z<>\/.'
    daze_left = daze_left.split ' '
    if daze_left.size == 1
      dazed_time = daze_left[0].to_i
    else
      dazed_time = daze_left[0].to_i * 60 + daze_left[1].to_i
    end
    puts Game.log :info, "Hero is dazed for #{dazed_time}."
    if @driver.find_elements(id: 'battle')[0]
      @driver.find_element(id: 'battleclose').click if @driver.find_elements(id: 'battle')[0].displayed?
    end
    sleep dazed_time + 2
    @driver.navigate.refresh
    sleep 0.5 until @driver.map_loaded?
    @map = Map.new self
    puts Game.log :info, "Hero is no longer dazed!\nHealing"
    heal
    puts Game.log :debug, 'Hero is healed.'
    @status = true
    true
  end
  def safe_map_call(m, *args)
    #
    # This method is used to manage calls and returns
    # Also checks if everything went ok
    #
    puts Game.log :debug,"Calling map.#{m}()"
    if m == 'go_to_map'
      if args[0] == @map.name or args[0] == @map.id
        return true
      end
      puts Game.log :info,"Going to map #{args[0]}."
      loop {
        until @driver.map_loaded?
          sleep 0.1
        end
        v = @map.send(m,*args)
        if v == :stuck
          dialog = @driver.find_elements(id: 'dialog')[0]
          skipped_dialog = false
          if dialog
            if dialog.displayed?
              replies = dialog.find_elements css: "[class=\"icon icon LINE_EXIT\"]"
              if replies[0]
                replies[0].click
                sleep 0.5
                skipped_dialog = true
              else
                puts Game.log :info, "Can't exit the dialog."
                return false
              end
            end
          end
          unless skipped_dialog
            @driver.navigate.refresh
            sleep 0.2 until @driver.map_loaded?
            @map = Map.new self
          end
        elsif v == :found_mob
          return true
        elsif v.class == TrueClass
          sleep 1
          sleep 0.2 until @driver.map_loaded?
          @map = Map.new self
          return true if @map.name == args[0]
          return true if @map.id == args[0]
          #
          # If it's here it means that @map.name != wanted map
          sleep 5
          if @driver.current_map_name == args[0] or @driver.current_map_id == args[0]
            @map = Map.new self
            return true
          else
            puts Game.log :warning,"Something went wrong and hero wasn't moved to given map (destination: #{args[0]}, current map: #{@driver.current_map_name}). Trying again."
          end
        elsif v.class == FalseClass
          return false
        else
          puts Game.log :warning,"Can't recognize returned value #{v}."
        end
      }
    elsif m == 'move_to_coords'
      loop {
        v = @map.send m, *args
        if v == :stuck
          @driver.navigate.refresh
          sleep 5
          @map = Map.new self
        end
        return true if v.class == TrueClass
        return false if v.class == FalseClass
        puts Game.log :debug,"Trying again to call map.#{m}(#()."
      }
    elsif m == 'move_to_mob'
      loop {
        v = @map.send m, *args
        if v == :stuck
          @driver.navigate.refresh
          sleep 5
          @map = Map.new self
        end
        return true if v.class == TrueClass
        return false if v.class == FalseClass
        puts Game.log :debug,"Trying again to call map.#{m}()."
      }
    else
      puts Game.log :warning,"Not known method #{m}. Can handle 'go_to_map', 'move_to_coords', 'move_to_mob'."
    end
  end
  def go_to(target, player_reaction = false, mob_to_find = nil)
    #
    #
    if target.class == Array
      target.each do |ta|
        if ta.class == String or ta.class == Integer
          #
          # Travel to another map (map name/id)
          #
          unless safe_map_call  "go_to_map",ta, false, mob_to_find
            require_relative 'scripts/script_manager'
            puts Game.log :debug, "Couldn't move to #{ta}. Trying to find alternative path."
            path = ScriptManager.new.find_path_in_exception @map.name, ta
            puts Game.log :debug, "Path: #{path}."
            if path
              go_to path, player_reaction, mob_to_find
            else
              return false
            end
          end
          @chat_monitor.check_and_save
          sleep 0.5
          #
        elsif ta.class == Mob
          #
          # Obvious - go to mob.
          #
          return false unless safe_map_call "move_to_mob",ta, player_reaction
        elsif ta.class == Array
          #
          # If it's nested array, it should be coords
          #a
          unless ta[0].class == Integer and ta[1].class == Integer
            puts Game.log :warning,"Wrong argument type #{ta}."
          end
          return false unless safe_map_call "move_to_coords",ta, player_reaction, nil, mob_to_find
        else
          puts Game.log :warning,"Wrong argument type #{ta}."
        end
      end
      # end of .class == Array
      #
    else
      puts Game.log :error,"Wrong argument type given. Expected: Array. Given: #{target.class}"
      raise ArgumentError
    end
    #
    #
  end # end of go_to
  def tp_to(town)
    if @map.name == 'Tuzmer' or (town == 'Tuzmer' and not @map.name == 'Trupia Przełęcz')
      teleportation 'Trupia Przełęcz'
      puts Game.log :info,'Teleported to Trupia Przełęcz'
      teleportation town
    else
      teleportation town
    end
    sleep 2
    puts Game.log :info,"Teleported to #{town}."
    true
  end

  def dialogue_replies
    replies = {}
    reps = @driver.find_element(id: 'replies')
    reps = reps.find_elements(:css, "[class^=\"icon\"]")
    reps.each do |rep|
      inner_html = rep.attribute :innerHTML
      potato = inner_html.match(/<.*>/)
      if potato
        replies[inner_html.sub(potato[0], '')] = rep
      end
    end
    replies
  end
  def click_reply(text)
    dialogue_replies.each do |reply, element|
      if reply.match /#{text}/
        sleep(0.776)
        element.click
        puts Game.log :info,"Clicked #{text}."
        return true
      end
    end
    false # return
  end
  def need_healing?
    percent = ((health/max_health)*100.0).round 2
    puts Game.log :info,"Hero has #{percent}% of health."
    if percent < 75
      true
    else
      false
    end
  end
  def need_potions?(available_potions)
    # comparing amount of health points that can be healed to maximum player health.
    # If it can be healed less than 5 times, enable accepting health potions,
    #     even though there was no exception for this set up.



  end
  def add_items(items = [], minimal_value = 0, loot = false, loot_filter = [:unique, :heroic, :legendary, :dragon_runes]) # items - array required. minimal_value, loot and loot_filter are arguments used when its called from loot method in bot class.
    require_relative 'item'
    if items.is_a?(Selenium::WebDriver::Element)
      items = [items]
    end # When it's single Element - caller probably have forgotten that there is array required.
    items.each do |it|
      unless it.is_a?(Selenium::WebDriver::Element)
        puts Game.log :warning,"Wrong argument type. Expected Array, given: #{items.class}."
        return false
      end
    end # checking argument type
    unless items.is_a?(Array)
      puts Game.log :warning,"Wrong argument type. Expected Array, given: #{items.class}."
      return false
    end # checking argument type

    if items.empty?
      @driver.get_all_items_ids.each do |item_id|
        begin
          created_item = Item.new(self,item_id) # it returns false, when something went wrong. Otherwise it is self.
          if created_item
            @all_items << created_item if [:healing, :dragon_runes, :arrows, :bag].include?(created_item.type) or created_item.amount_of_added_gold > 0
          end
        rescue => error
          puts Game.log :error,"Something went wrong while creating item from element: #{item_id}."
          Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
        end
      end # elements added to array
    else
      if loot # loot is one of arguments. If its called from loot method in bot class, loot is true.
        created_item = Item.new(self,items[0], minimal_value, loot, loot_filter) # it returns false, when something went wrong. Otherwise it is self.
        if ([:healing,:dragon_runes,:arrows,:bag].include?(created_item.type) or created_item.amount_of_added_gold > 0) and created_item.accepted
          # we don't need all items in memory. Arrows, healing and items which adds some gold or dragon runes.
          @all_items << created_item # if everything went well
        else
          puts Game.log :debug,"No need to add #{created_item} to @all_items."
        end
      else
        created_item = Item.new(self,items[0]) # if returns false, when something went wrong. Otherwise it is self.
        if [:healing,:dragon_runes,:arrows,:bag].include?(created_item.type) or created_item.amount_of_added_gold > 0
          # we don't need all items in memory. Arrows, healing and items which adds some gold or dragon runes.
          @all_items << created_item # if everything went well
        else
          puts Game.log :debug,"No need to add #{created_item} to @all_items."
        end
      end
      created_item
    end #
  end # adds items to @all_items array. Can be called without argument - then automatically check if there are new items.
  def use_items_adding_gold
    all_items.each do |i|
      if i.amount_of_added_gold > 0
        puts Game.log :info,"Using item #{i.name} which adds #{i.amount_of_added_gold} gold."
        i.use
        # item is gone. Remove it from array with all items belonging to hero.
        remove_item i.item_id
      end
    end
  end
  def remove_item(item)
    if item.class == String
      unless @driver.find_elements(id: item)[0].nil?
        puts Game.log :warning,"Tried to remove an existing item from all_items array! Item id: #{item}"
        return false
      end # in case of mistaken call.
      # iterate @all_items and look for id of item we want to remove.
      @all_items.each do |it|
        if it.item_id == item
          puts Game.log :debug,"Deleted: #{@all_items.delete_at(@all_items.index(it))}" # removing item from array
          return true
        end
      end
    elsif item.class == Item
      unless @driver.find_elements(id: item.item_id)[0].nil?
        puts Game.log :warning,"Tried to remove an existing item from all_items array! Item id: #{item.item_id}"
        return false
      end # in case of mistaken call.
      puts Game.log :debug,"Deleted: #{@all_items.delete_at(@all_items.index(item))}" # removing item from array
      return true
    else
      puts Game.log :warning,"Wrong argument type given (#{item.class}). Expected String or Item."
      false
    end # removing item from array
  end # removes item from @all_items
  def health
    begin
      health_bar_data = @driver.find_element(id: 'life1').attribute(:tip)
    rescue
      sleep 5
      health_bar_data = @driver.find_element(id: 'life1').attribute(:tip)
    end
    puts Game.log :debug,'Health bar has been found.'
    puts Game.log :debug,"#{health_bar_data}"
    # health_bar_data example: "<B>Punkty życia:</B> 12 345 / 12 345"
    # Punkty życia:</B>2293 / 4556
    health_bar_data.delete!(' ')
    /\d+\//.match(health_bar_data)[0].delete('/').to_f # number of health points at this moment
  end # returns current amount of health points
  def max_health
    health_bar_data = @driver.find_element(id: 'life1').attribute(:tip)
    puts Game.log :debug,'Health bar has been found.'
    puts Game.log :debug,"#{health_bar_data}"
    # health_bar_data example: "<B>Punkty życia:</B> 12 345 / 12 345"
    health_bar_data.delete!(' ')
    /\/\d+/.match(health_bar_data)[0].delete('/').to_f # maximum number of health points
  end # returns maximum amount of health points
  def driver_element(wait_for_load = false)
    (sleep 0.2 until @driver.map_loaded?) if wait_for_load

    @driver.find_elements(id: 'hero')[0]
  end

  def coordinates
    coords = nil
    loop {
      begin
        coords = @driver.script('return [hero.x,hero.y]')
        break
      rescue
        puts Game.log :debug,'Page has not loaded yet.'
      end
    }
    [coords[0].to_i, coords[1].to_i]
  end # returns current [x,y]
  def refill_arrows
    return false unless @profession == 'tracker' or @profession == 'hunter'
    @all_items.each do |item|
      if item.driver_element.nil?
        remove_item item
      else
        if item.name == @used_arrows.name and item != @used_arrows
          @driver.change_bag(item.bag.item_object.item_id)
          sleep(0.2)
          @driver.action.drag_and_drop(item.driver_element, @used_arrows.driver_element).perform
          sleep(0.1)
          puts Game.log :info,'Arrows refilled.'
          return true
        end
      end
    end
  end # refilling arrows
  def click_in_hero_menu(button)
    #
    # default buttons in hero menu: "Przejdź", "Podnieś", "Złość Się"
    #
    # Opening menu, then clicking chosen button
    #
    # Opening menu
    begin
      driver_element(true).click
    rescue
      puts Game.log :debug, 'Page was probably refreshed, cannot click in hero menu.'
      return false
    end
    sleep(0.1)
    #
    # Getting menu element
    menu = @driver.find_elements(id: 'hmenu')[0]
    unless menu
      sleep 0.3
      menu = @driver.find_elements(id: 'hmenu')[0]
    end

    # getting buttons
    begin
      buttons = menu.find_elements(tag_name: 'button')
    rescue
      puts Game.log :debug,'hmenu disappeared. Probably page was refreshed.'
      return false
    end
    # pressing button
    begin
      buttons.each do |bu|
        if /#{button}/.match bu.text
          bu.click
          return bu
        end
      end
    rescue
      puts Game.log :error,'Something went wrong while clicking button in hero menu. :/'
      return false
    end
    #
    # If we're still here, it means that given button couldn't be found in the menu.
    # So, we obviously can't click it. But menu is already open and to close it we need to click somewhere.
    # We're going to click the 'Podnieś' button. It's always in this menu, and it's always possible to click it.
    # It also can't have a negative result on game. Usually it do nothing. Sometimes picks up an item.
    # But situation when given button wasn't found in the menu is rare. Items lying on the ground are also rare.
    # So, in very, very most cases it won't do any action.
    #
    begin
      buttons.each do |bu|
        bu.click if /Podnieś/.match bu.text
        return false
      end
    rescue
      puts Game.log :error,'Something went wrong while clicking button in hero menu. :/'
    end
    #
  end
  def heal # heals
    missing_points = max_health.to_i - health.to_i
    puts Game.log :debug,"#{missing_points} health points missing."
    if health/max_health > 0.80
      puts Game.log :debug,'No need to heal.'
      return true
    end # check if there's need to heal. If not, break.
    health_potions = [] # health_potions - array with healing items.
    all_items.each do |item|
      if item.type == :healing
        if item.driver_element
          health_potions << item.healing_object
        end # check if the item appears (it may be no more longer in eq.)
      end
    end # fill
    puts Game.log :debug,"#{health_potions.size} healing potions has been found."
    if health_potions.size == 0
      if max_health/2 > health
        puts Game.log :info,"Hero has no more potions to heal and #{health} health. Stopping bot on this hero."
        @status = false
        return false
      end
    end # ending program if there are no more health potions. Otherwise, hero will die attacking mob.
    full_healing_potions = [] # array with potions which can add full health. Those are used first.
    health_potions.each do |potion|
      if potion.full_healing
        puts Game.log :debug,"Adding #{potion.item_object.name} to full_healing_potions"
        full_healing_potions << potion
      end
    end # filling full_healing_potions
    if full_healing_potions.size > 0
      full_healing_potions.each do |potion|
        puts Game.log :info,"Using #{potion.item_object.item_id} potion."
        potion.use(missing_points) # argument - points to heal
        missing_points = max_health-health
        sleep(0.3)
        if health/max_health > 0.80
          puts Game.log :debug,'Healed.'
          return true
        end # if healed, return true. Otherwise, go to next item...
      end # healing. If healed - breaks, otherwise goes further.
    end # using full healing items.
    # if it haven't returned yet - it means that there were not enough full healing items.
    # Now we have to use common potions.
    # At first, we create a hash with each potion as keys, and healing points amount as value.
    # Then basing on this hash we will try to heal as much, as it's possible.
    potions_with_points = {}
    health_potions.each do |potion|
      unless potion.full_healing
        unless potion.heal_points == 0
          potions_with_points[potion] = potion.heal_points
        end # if something went wrong while checking heal_points value - it return 0.
        # we don't want insecure items here.
      end # we're not interested in full healing potions anymore (actually, all has been spent already)
    end # filling potions_with_points hash
    potions_with_points = potions_with_points.sort_by{ |k,v| v }.reverse
    potions_with_points.each do |pair|
      if pair[1] < missing_points
        sleep(0.2)
        n = missing_points.to_i/pair[1].to_i # rounded down amount of uses needed to heal
        if pair[0].uses >= n
          n.times do
            puts Game.log :info,"Using #{pair[0].item_object.item_id} potion."
            pair[0].use(missing_points)
            sleep(0.2)
            missing_points = max_health-health
          end # use item maximum number of times.
        else
          pair[0].uses.times do
            puts Game.log :info,"Using #{pair[0].item_object.item_id} potion."
            pair[0].use(missing_points)
            sleep(0.2)
            missing_points = max_health-health
          end # use item as many times as it is possible
        end # healing n times
        #
        #
      end # if item can be used - do it. Otherwise, go to next item.
      #
    end # healing with common items.
  end
  def check_up
    @map = Map.new(self) if @map.name != @driver.current_map_name
    heal if need_healing?
    refill_arrows
  end

  private
  def set_used_arrows
    armed_arrows = []
    @all_items.each do |item| # @driver.all_items returns array with Selenium::Webdriver::Element objects
      # if item is arrows and it doesn't belong to any bag that means it is armed arrows item.
      if item.type == :arrows and not item.bag
        armed_arrows << item
      end
    end

    case armed_arrows.size
      when 0
        @used_arrows = false
        puts Game.log :info,'Hero don\'t use arrows.'
        return false
      when 1
        @used_arrows = armed_arrows[0]
        puts Game.log :info,"Hero use #{@used_arrows.name} arrows."
        return true
      else
        puts Game.log :warning,"Couldn't determine if hero use arrows (armed_arrows value: #{armed_arrows})."
        return false
    end
  end
  def set_profession
   prof_shortcut = @driver.script('return hero.prof')
   case prof_shortcut
     when 'm'
       @profession = 'magician'
     when 'p'
       @profession = 'paladin'
     when 't'
       @profession = 'tracker'
     when 'b'
       @profession = 'blade runner'
     when 'w'
       @profession = 'warrior'
     when 'h'
       @profession = 'hunter'
     else
       puts Game.log :warning,"Couldn't find profession. Bot won't refill arrows."
       @profession = 'unknown'
   end
   puts Game.log :info,"Hero's profession is a #{@profession}."
  end
  def teleportation(town)
    destinations = File.read "#{Game::MAIN_DIR}MargoBot/GameFiles/NPCS/TP/A-Z_FILES_LIST"
    if destinations.include? town
      if destinations.include? @map.name
        npc = JSON.parse(File.read("#{Game::MAIN_DIR}MargoBot/GameFiles/NPCS/TP/#{@map.name}"), :quirks_mode => true)
        go_to([[npc['coords'][0], npc['coords'][1] + 1]])
        sleep(0.4)
        id = @map.is_there?(npc['nick'])
        return false unless id
        @driver.find_element(id: "npc#{id}").click
        sleep 0.4
        if @map.name == 'Tuzmer'
          click_reply 'Chciałem się teleportować'
          sleep 0.4
          click_reply 'Tak'
        elsif @map.name == 'Nithal'
          click_reply 'Teleportuj.'
        else
          click_reply 'Chciałem się teleportować'
          sleep 0.4
          if click_reply town
            puts Game.log :info,"Teleported to #{town}."
          else
            puts Game.log :warning,"Hero can not be teleported to given town (#{town})."
            return false
          end
        end
        sleep 0.1 until @driver.map_loaded?
        sleep 0.5
        # Map has changed so actualise it.
        @map = Map.new self
        return true
      else
        puts Game.log :warning,"Hero is not on map from where can be teleported. Hero map: #{@map.name}, can be teleported from: #{destinations}."
        return false
      end
    else
      puts Game.log :warning,"Can't be teleported to #{town}. Possible destinations: #{destinations}."
      false # return
    end
  end
end