class Bot
  require_relative 'game'
  require_relative 'mob'
  require_relative 'hero'
  require_relative 'local_driver'
  require_relative 'chat_monitor'
  require 'selenium-webdriver'
  extend Game
  attr_reader :last_kill_time, :group, :loot_filter, :npc_name, :kills, :chat_monitor, :hero, :driver, :value, :can_interrupt # group stores group of mobs to which target belongs.

  def initialize(npc_name, driver, loot_filter = [], value = 0)
    @value = value
    @driver = driver
    @price = [0,0,0]  # summed value of looted items [all, accepted, refused]
    @amount = [0,0,0]  # number of looted items [all, accepted, refused]
    @rarity = [0,0,0,0] # number of items with division for its' rarity [common, unique, heroic, legendary]
    @kills = 0
    # Set up values of instance variables. All of them are actualised in +loot()+ method
    while @driver.find_elements(id: 'skillSwitch')[0].nil?
      sleep(0.5)
    end
    sleep(1)
    @hero = Hero.new driver, self # creating hero object.
    @driver.change_bag(@hero.main_bag_id) # change bag to the main one.
    @npc_name = npc_name
    puts Game.log :debug,npc_name
    # nil value in @group is needed only to check if the group was already set in attack or it's first call.
    # The group never changes so it's enough to check it once.
    # Checking group every time can make some bugs and it can't do anything more than checking it once, so lets get rid of it after first kill.
    @group = [npc_name, nil]
    filter = []
    loot_filter.each do |items_group|
      # possible item groups: 'arrows', 'dragon runes', 'teleportation', 'healing'
      # possible rarities: 'common', 'unique', 'heroic', 'legendary'

      possibilities = [:arrows, :dragon_runes, :teleportation, :healing, :common, :unique, :heroic, :legendary]
      if possibilities.include?(items_group)
        puts Game.log :debug,"#{items_group} items added to exceptions from filter."
        filter << items_group
      else
        puts Game.log :warning,"Can't recognize the '#{items_group}' group of items. Here is list of groups of items I can recognize: #{possibilities}."
      end
    end
    @loot_filter = filter
    @chat_monitor = @hero.chat_monitor
    puts Game.log :info,"Bot will accept: #{p @loot_filter} items no matter what the value of minimum price of item."
    #
  end
  def handle_kill(value = 0, player_reaction = true, wait = false)
    @can_interrupt = true # setting to true (nil would block interrupting this thread at first run)
    result = attack_with_wait(@group, @npc_name, player_reaction, wait)
    unless result
      puts Game.log :warning,'Attack method returned false.'
      return false
    end
    puts Game.log :info,"#{@hero.nick} won the battle with #{@npc_name}." if result == :win
    @kills += 1 if result == :win
    if result == :lose
      puts Game.log :info,"#{@hero.nick} lost the battle with #{@npc_name}."
      @hero.dazed
      @hero.heal
      return false
    end
    # refusing loot if it's value is too low
    loot_info = loot true # array: [0] is data to save, [1] is array with raw data
    # saving kill to file
    add_kill_to_list loot_info

    sleep(0.2)
    @hero.bags.each do |bag|
      bag.refresh
    end # refreshing bags
    # using items which add gold
    @hero.use_items_adding_gold
    @hero.heal
    @chat_monitor.check_and_save
    if @hero.profession == 'tracker' or @hero.profession == 'hunter'
      @hero.refill_arrows
    end # refilling arrows
    @driver.change_bag(@hero.main_bag_id) # change bag to the main one.
    @driver.press_key 's', 0.02 if rand(2) == 0
    @can_interrupt = true
    true
  end
  def attack(mob = nil, wait = false, player_reaction = false, get_group = false, auto_battle = true)
    ####
    ##  Attacks given mob
    ##  Mob has to be spawned
    ####
    #
    # argument class check-up
    unless auto_battle
      puts Game.log :warning,'Manual battle is not available for this moment. Changing mode to auto battle...'
      auto_battle = true
    end
    unless mob.is_a? Mob or mob.nil?
      puts Game.log :warning,"Wrong argument type. Given: #{mob.class}, expected: Mob."
      return false
    end
    #
    # moving to mob
    if wait
      sleep(5 + rand(8)/5)
    end
    #
    # When mob is nil - battle has been started already
    if mob
      until move mob, player_reaction
        return false unless mob.driver_element
        puts Game.log :warning,"move(#{mob}, #{player_reaction}) returned false. Trying again."
        @driver.navigate.refresh
        sleep(5)
      end
      puts Game.log :debug,"Moved hero to mob #{mob.name} successfully."
      unless start_battle player_reaction, mob
        return false
      end
      #
      # now thread shouldn't be stopped from MargoBot (it might have wrong affect on work of the bot)
      @can_interrupt = false
      #
      # Getting group if caller want this
    end
    #
    mobs = @driver.get_group
    @group = mobs if get_group
    mobs.each do |m|
      moo = Mob.new(m, @driver)
      @hero.map.erase_collision moo.coords if moo
    end
    #
    # auto/manual battle
    #
    sleep(0.05)
    if auto_battle
      @driver.press_key('f', 0.15)
    else
      # todo: manual battle
    end
    result = find_result
    #
    # close battle
    @driver.close_battle
    #
    # return result
    if @driver.find_elements(id: 'dlgwin')[0]
      sleep(0.2)
      @driver.find_element(class: 'closebut').click if @driver.find_elements(id: 'dlgwin')[0].displayed?
    end

    result
  end
  def attack_with_wait(target_group, npc_nick, player_reaction = true, wait = false)
    n=0
    begin
      # waiting for spawn of the mob
      mobs = []
      puts Game.log :debug,'Waiting for spawn of mob.'
      spawned = false
      until spawned
        #
        # if there's someone else and player wanted not to attack in this situation, other_player will wait and save data.
        #
        if @driver.other_players? and player_reaction
          @driver.other_player(player_reaction, target_group) # Check if there are other players (if player_reaction is true)
        end
        npc = @hero.map.is_there? npc_nick
        if npc
          mobs[0] = npc if mobs[0].is_a? String
          foo = nil
          if target_group[-1].nil?
            foo = @driver.spawned_mob([npc]) # this method returns array with Mob objects
          else
            foo = @driver.spawned_mob(target_group) # this method returns array with Mob objects
          end
          if foo.is_a?(Array)
            mobs = foo
            puts Game.log :debug,"@driver.spawned_mob returned #{target_group}."
            break
          end
        end
        #
        # Saving messages to chat log.
        # Checking it too often leads to slow down the computer.
        #
        if n==100
          @chat_monitor.check_and_save
          n = 0
        else
          n+=1
        end
        #
        #
        sleep(0.02)
        #
      end # waiting for spawn of the mob.
      #
      # mob was spawned, so let's ensure that thread won't be killed
      @can_interrupt = false
      #
      puts Game.log :debug,'Sleep for a while.'
      sleep(rand(800)/1000.0)
      puts Game.log :debug,'Sleep ended.'

      if rand(5) == 0 and @driver.other_players?
        sleep 60 + rand(60)
        return false
      end

      #
      # Moving hero and attacking bot.
      # Details are explained in move and start_battle methods.
      # move returns mob which is touched by hero
      #
      mob = @driver.find_closest_element(@hero.driver_element, mobs.compact)

      get_group = false
      if target_group[-1].nil?
        puts Game.log :debug,'Will get group.'
        get_group = true
      end
      #
      #
      result = attack(mob,wait,player_reaction,get_group,true)
      return false unless result
      #
      #
      mobs.each do |a|
        a.kill_time = Time.now
      end
      #
      puts Game.log :info,"Killed npcs: #{target_group}"
      @last_kill_time = Time.now
      #
      #
      return result
    rescue StandardError => error
      Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      return false
    end
    #
    # won't get here
    #
  end
  def loot(actualise_stats = false) # scraping looted items, adding it to @driver.all_items and accepting or refusing.
    # Scheme is very simple. After battle loots appears in element with id: 'loots'.
    # That element is divided into smaller, where every smaller includes item, and yes/no buttons.
    # So, at first we scrap the loots element. The we check how many items were looted.
    # If it's zero - there's no loot, leaving this method, returning 'No loot.'
    #
    # If it's more - for each smaller element (id: 'loot000000000', where 000000000 is item id) we check item value - by sending it to @driver.add_item.
    # When accepted, go to nex item. When refused, click class: 'no' button, and go to next item.
    def find_loots_panel(*args)
      n = 1
      n = 0.2 if args.include? :quick_mode
      time = Time.now
      until false
        if time + 0.2 < Time.now
          return false
        end
        loots = @driver.find_elements(id: 'loots')[0]
        unless loots.nil?
          if loots.displayed?
            return loots
          end
        end
        sleep(0.1)
      end
    end # returns driver_element or false, when couldn't find.
    loots = find_loots_panel
    unless loots # if the box isn't visible
      puts Game.log :info,'No loot.'
      add_item_to_stats @npc_name if actualise_stats
      return [nil]
    end # checking if there is loot.
    # if we're here it means that there is at least 1 looted item.
    loots_ids = loots.attribute(:innerHTML).scan(/loot\d+/) # amount of returned strings is equal to number of loots.
    puts Game.log :info,"Looted #{loots_ids.size} items."

    return_data = [] # array with data about every item.

    loots_ids.each do |loots_id|
      loot_box = loots.find_element(id: loots_id)
      # loot_box contains item element and yes/no buttons
      # now we create Item object using LocalDriver method: add_item
      id_of_looted_item = /item\d+/.match(loot_box.attribute(:innerHTML)) # getting id of looted item
      loot = loot_box.find_element(id: id_of_looted_item) # this is item element.
      # now we will create Item object for this item
      item_object = @hero.add_items([loot], @value, true, @loot_filter) # [loot] is obviously element of the item. value is minimum_value to accept,
      #                                                    true - it means that this is looted item, and loot_filter are the exceptions for loot.
      #
      # So, now Item object is created.
      # Now we just need to get item_object.accepted value and refuse item, or go to next one :)
      unless item_object.accepted
        # refusing item
        sleep(0.25)
        loot_box.find_element(class: 'no').click
      end # default choose is to accept item. So if we want to have it in eq - do nothing. Otherwise, we need to click class: 'no' button.
      add_item_to_stats(@npc_name, item_object) if actualise_stats
      # returning array with data to stats.
      return_data << ["#{item_object.rarity} (#{item_object.value}) #{if item_object.accepted; '- accepted' end}"]
    end # creating Item objects and accepting/refusing.

    @driver.find_element(id: 'loots_button').click # confirm acceptation or refusal
    return_data # return data for stats
  end

  private
  # start_battle should be called when hero touches mob. This method won't move hero! (move should be called first.)
  def start_battle(player_reaction, mob)
    #
    # when hero is below mob and mob is small, mob.driver_element.click will click on hero.
    special_action = nil
    if mob.size[1] <=70
      puts Game.log :debug,'Special action will be performed.'
      special_action = @driver.action.move_to(mob.driver_element).move_by(0, -((mob.size[1] - 2)/2)).click
    else
      puts Game.log :debug, 'Special action will not be performed.'
    end
    #
    # in this situation there are no other players but we have to check if someone has logged into game.
    #
    if player_reaction and not @driver.other_players?
      3.times do
        if special_action
          special_action.perform
        else
          begin
            mob.driver_element.click
            sleep(0.5)
            click_in_mob_menu 'Atakuj' if @driver.find_elements(id: 'hmenu')[0]
          rescue
            puts Game.log :error,"element is not interactable. Hero coords #{@hero.coordinates}. Mob coords #{mob.coords}"
          end
        end

        click_time = Time.now

        #
        # There are 2 possible things to happen:
        # 1 - Hero successfully attacked mob
        # 2 - Something went wrong and battle haven't start.
        #
        until @driver.fight? or Time.now > click_time + 3
          sleep(0.5)
          if @driver.other_players?
            puts Game.log :debug,"Player_reaction is true and there are other players - returning false."
            return false
          end
        end

        if @driver.fight?
          return true
        else
          puts Game.log :debug,'Special action will be performed.'
          special_action = @driver.action.move_to(mob.driver_element).move_by(0, -((mob.size[1] - 2)/2)).click
          special_action.perform
        end

      end
      return false
    elsif player_reaction and @driver.other_players?
      puts Game.log :debug,'Player_reaction is true and there are other players - returning false.'
      return false
    end

    #
    # in this situation player_reaction is false
    #
    unless player_reaction

      2.times do
        if special_action
          special_action.perform
        else
          begin
            mob.driver_element.click
            sleep(0.5)
            click_in_mob_menu 'Atakuj' if @driver.find_elements(id: 'hmenu')[0]
          rescue
            puts Game.log :error,'mob element is not interactable ;/'
          end
        end
        click_time = Time.now
        sleep(0.5)

        #
        # There are 2 possible things to happen:
        # 1 - Hero successfully attacked mob
        # 2 - Something went wrong and battle haven't start, but it's still possible to attack mob.
        # 3 - Someone else attacked mob
        #
        if @driver.fight?
          return true
        end

        until @driver.fight? or Time.now > click_time + 5
          sleep(0.5)
          unless  @hero.map.is_there?(mob.name)
            puts Game.log :info,'Somebody else killed mob.'
            return false # somebody else killed
          end
        end
        ##
      end # 2 times
      if @driver.fight?
        return true
      else
        puts Game.log :debug,'Special action will be performed.'
        special_action = @driver.action.move_to(mob.driver_element).move_by(0, -((mob.size[1] - 2)/2)).click
        special_action.perform
      end
      puts Game.log :debug,'Got to end of function without returning. Returning false..'
      return false
    end

    #
    false
    #
  end # click on mob and interpret what happened
  # move returns touched mob id which should be attacked, or nil.
  def click_in_mob_menu(action)
    menu = @driver.find_elements(id: 'hmenu')[0]
    if menu
      if menu.displayed?
        puts Game.log :debug,"Menu is displayed. Will click #{action}"
        menu.find_elements(:css, "*").each do |ee|
          if ee.attribute(:innerHTML).include? action
            ee.click
            puts Game.log :debug,"Clicked: #{ee.attribute :innerHTML}"
          end
        end
      end
    end
  end
  def move(mob, player_reaction)
    #
    # If player want bot to do nothing when there are other players and there is someone else around
    # Return nil - bot won't do any action further.
    #
    @hero.map = Map.new @hero if @driver.current_map_name != @hero.map.name


    if player_reaction and @driver.other_players?
      puts Game.log :debug,'Player_reaction is true and there are other players - returning false.'
      return false
    end

    #
    # This variant is used when player don't want to do anything when someone is around but there is no one.
    # If there is nobody around - trying to move to mob until it will be successful.
    # Also checking if someone around entered game.
    #
    if player_reaction and not @driver.other_players?
      puts Game.log :debug, 'Player reaction is true but there are no others.'
      go_to = @hero.go_to([mob], player_reaction)
      unless go_to
        puts Game.log :debug,"@hero.go_to returned false. Something went wrong..."
        return false
      end
      return go_to
    end

    #
    # If player want bot to ignore another players
    #
    unless player_reaction
      puts Game.log :debug, 'Player reaction is false. Ignoring others (if there are).'
      go_to = @hero.go_to([mob], player_reaction)
      if go_to
        return go_to
      else
        puts Game.log :debug,'@hero.go_to returned false/nil'
        return false
      end
    end

    #
    puts Game.log :debug,'Got to end of the function without returning value. Returning false.'
    false
    #
  end # move to mob
  def find_result
    stt = Time.now
    result = @driver.find_elements(class: 'win')[0]
    until result
      result = @driver.find_elements(class: 'win')[0]
      sleep 0.093
      # if there is anti-bot protection
      require_relative 'AntiBot/anti_bot'
      AntiBot.new.bypass_images_anti_bot @driver if @driver.find_elements(class: 'ansRound')[0]
      #
      return false unless @driver.fight?
      @driver.press_key('f', 0.13) if Time.now - stt > 5
    end
    result_bar = result.attribute :innerHTML
    if result_bar.match @hero.nick
      :win # return
    else
      :lose
    end
  end
  def add_kill_to_list(loot_info)
    #
    # Getting amount of kills
    # (every line with kill has its number, so we're basically finding first line from reverse including \d+ kill pattern)
    f = File.open "#{Game::MAIN_DIR}#{@driver.bot_manager.dir}/Kills list"
    str = nil
    f.readlines.reverse.each do |line|
      str = line.match /\d+ kill/ if line
      break if str
    end
    amount = 0 unless str
    amount = str[0].to_i if str

    amount += 1
    #
    # spaces are used to make kill logs look more neatly.
    spaces = 10 - @hero.nick.size
    if spaces < 0
      spaces = ''
    else
      spaces = ' ' * spaces
    end

    data = "#{@hero.nick}#{spaces}: #{amount} kill #{npc_name} at #{Time.now.strftime('%F %T')}: Looted: " # variable storing data to log (data is set in loop below.)
    if loot_info[0].nil? # when there was no loot.
      data += "\n"
    else
      # now +data+ is "#{@hero.nick}: #{add_kill} at #{Time.now.strftime('%F %T')}: Looted:"
      #
      # getting size of +data+ to make neatly log
      length = data.size
      loot_info.each_with_index do |loot, index|
        if index == 0
          data += "#{loot[0]}\n"
        else
          data += "#{"\s"*length}#{loot[0]}\n"
        end
      end
    end # creating +data+ string
    Game.save_data('Kills list', data, "#{@driver.bot_manager.dir}/")

  end
  def add_item_to_stats(npc_name, item = nil)
    require 'fileutils'
    require 'json'
    require_relative 'item'

    if File.exist?("#{@driver.bot_manager.dir}/Stats/#{npc_name}")
      FileUtils.rm("#{@driver.bot_manager.dir}/Stats/#{npc_name}")
    end
    # loots_stats stores summed data about looted items: [0loots_amount, 1value_of_all, 2amount_accepted, 3value_of_accepted
    #                             4amount_refused, 5value_of_refused, 6common, 7unique, 8heroic, 9legendary, 10dragon_runes,
    #                                            11amount_of_dragon_runes(each_"dragon_runes"_item_adds_some_dragon_runes)]
    #
    # String as keys, because it will be converted to json.
    data_template = {"first_kill" => @last_kill_time.strftime('%F %T'), "last_kill" => nil, "killers" => [], "mob" => npc_name, "kills" => 0, "looted" => 0, "looted_value" => 0,
                     "accepted" => 0, "accepted_value" => 0, "refused" => 0, "refused_value" => 0, "common" => 0, "common_accepted" => 0, "unique" => 0,
                     "unique_accepted" => 0, "heroic" => 0, "heroic_accepted" => 0, "legendary" => 0, "legendary_accepted" => 0,
                     "dragon_runes" => 0, "dragon_runes_accepted" => 0, "dragon_runes_amount" => 0, "added_gold_amount" => 0, "adding_gold_items" => 0}
    if File.exist?("#{@driver.bot_manager.dir}/Stats/#{npc_name}.json")
      data = JSON.parse(File.read("#{@driver.bot_manager.dir}/Stats/#{npc_name}.json"))
      FileUtils.rm("#{@driver.bot_manager.dir}/Stats/#{npc_name}.json")
    else
      data = data_template
    end
    #
    # This method may be called several times after one kill.
    # To avoid saving mistaken data, we need to check if we're operating on new kill
    # This is why there is conditional in data["kills"] == ...
    #
    data["kills"] += 1 if data["last_kill"] != @last_kill_time.strftime('%F %T')
    data["last_kill"] = @last_kill_time.strftime('%F %T')
    data["killers"] << @hero.nick unless data["killers"].include? @hero.nick
    if item
      data["looted"] += 1
      data["looted_value"] += item.value
      data["accepted"] += 1 if item.accepted
      data["accepted_value"] += item.value if item.accepted
      data["refused"] += 1 unless item.accepted
      data["refused_value"] += item.value unless item.accepted
      data["common"] += 1 if item.rarity == :common
      data["common_accepted"] += 1 if item.rarity == :common and item.accepted
      data["unique"] += 1 if item.rarity == :unique
      data["unique_accepted"] += 1 if item.rarity == :unique and item.accepted and not item.type == :dragon_runes
      data["heroic"] += 1 if item.rarity == :heroic
      data["heroic_accepted"] += 1 if item.rarity == :heroic and item.accepted
      data["legendary"] += 1 if item.rarity == :legendary
      data["legendary_accepted"] += 1 if item.rarity == :legendary and item.accepted
      data["dragon_runes"] += 1 if item.type == :dragon_runes
      data["dragon_runes_accepted"] += 1 if item.type == :dragon_runes and item.accepted
      data["dragon_runes_amount"] += item.dragon_runes if item.type == :dragon_runes and item.accepted
      data["added_gold_amount"] += item.amount_of_added_gold.to_i if item.accepted
      data["adding_gold_items"] += 1 if item.amount_of_added_gold.to_i > 0 and item.accepted
    end
    # adding spaces to that number
    data["added_gold_amount"] = data["added_gold_amount"].to_s.chars.to_a.reverse.each_slice(3).map(&:join).join(" ").reverse
    Game.save_data "#{npc_name}.json", data.to_json, "#{@driver.bot_manager.dir}/Stats/"

    plain_text_data = [  "First kill: #{data["first_kill"]}",
            "Last kill: #{data["last_kill"]}",
            "Killers: #{data["killers"].join ', '}",

            "\nMob: #{npc_name}",
            "Kills: #{data["kills"]}",

            "\nLooted items: #{data["looted"]} (value: #{data["looted_value"]})",
            "Accepted items: #{data["accepted"]} (value: #{data["accepted_value"]})",
            "Refused items:  #{data["refused"]} (value: #{data["refused_value"]})",

            "\nCommon items: #{data["common"]} (Accepted: #{data["common_accepted"]})",
            "Unique items: #{data["unique"]} (Accepted: #{data["unique_accepted"]})",
            "Heroic items: #{data["heroic"]} (Accepted: #{data["heroic_accepted"]})",
            "Legendary items: #{data["legendary"]} (Accepted: #{data["legendary_accepted"]})",

            "\nAmount of Dragon Runes: #{data["dragon_runes_amount"]} (from #{data["dragon_runes_accepted"]} items)",
            "Amount of earned gold: #{data["added_gold_amount"]} (from #{data["adding_gold_items"]} items)"       ]
    # data is an array which stores all data needed to fill file. It's array because save_data method saves every element of array in new line.
    Game.save_data("#{npc_name}", plain_text_data, "#{@driver.bot_manager.dir}/Stats/")
    puts Game.log :debug,'Stats actualised.'
    # save_data is defined in Game module.
  end
end