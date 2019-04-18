class MargoBot

  require_relative 'game'
  require_relative 'bot'
  require_relative 'local_driver'
  require_relative 'bot_settings'
  extend Game

  attr_accessor :bot_manager, :current_set, :driver

  def initialize(driver)
    @driver = driver
    puts Game.log :debug,"Mirek's ready to start."
  end

  def use(set, time)
    return false unless set
    if set.class == Array # array containing sets with intention to kill elites
      puts Game.log :info,"#{set.size} sets with intention :elite."
      begin
        static_killing(set, time)
      rescue StandardError => error
        Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      end
      set.each { |ss|
        ss.last_perform = Time.now
        puts Game.log :debug,"Last perform of set #{ss.name}, intention #{ss.intention}: #{ss.last_perform}."
      }
    elsif set.intention == :elite
      puts Game.log :info,"Next set: #{set.name}: #{set.intention}. #{set.npc_name}."
      begin
        static_killing([set], time)
      rescue StandardError => error
        Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      end
      set.last_perform = Time.now
    elsif set.intention == :exp
      puts Game.log :info,"Next set: #{set.name}: #{set.intention}."
      begin
        exp set
      rescue StandardError => error
        Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      end
      set.last_perform = Time.now
      puts Game.log :debug,"Last perform of set #{set.name}, intention #{set.intention}: #{set.last_perform}."
    elsif set.intention == :search
      puts Game.log :info,"Next set: #{set.name}: #{set.intention}, #{set.npc_name}."
      begin
        find_mob set
      rescue StandardError => error
        Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      end
      set.last_perform = Time.now
      puts Game.log :debug,"Last perform of set #{set.name}, intention #{set.intention}: #{set.last_perform}."
    else
      puts Game.log :warning,"Can't recognize this type of intention #{set.intention}"
    end
  end
  def initialize_set(set)
    @driver.switch_hero set.nick
    set.bot_obj = Bot.new(set.npc_name, @driver,set.loot_filter, set.value_to_filter)
    set.hero_obj = set.bot_obj.hero
  end
  private
  def static_killing(bot_settings = [], time = -1)
    # bot setting should be an array with BotSetting objects.
    # method will be used for +time+ seconds. Negative number == infinity
    puts Game.log :info,"Bot will handle #{bot_settings.size} hero(es)."
    puts Game.log :info,"Will handle static killing until #{(Time.now+time).strftime '%H:%M:%S'} (#{(time/60).round(2)} minutes)." if time >= 0
    puts Game.log :info, 'Will handle static killing until the end of playing.' if time < 0


    begin_time = Time.now
    until Time.now - time >= begin_time and time > 0
      bot_settings.map! do |set|
        unless set.status.class == FalseClass
          set
        end
      end
      bot_settings.compact!

      bot_settings.each_with_index do |set, _|
        @current_set = set
        if set.bot_obj.nil?
          initialize_set set
        end
        while true
          begin
            @driver.switch_hero(set.nick) if @driver.script('return hero.nick') != set.nick
            break
          rescue
            puts Game.log :debug, 'Error in MargoBot line 89.'
          end
        end

        bot_thread = Thread.new {
          # Joining bot
          puts Game.log :debug,"bot_thread joined for bot #{set.bot_obj}"
          unless @driver.current_map_name == set.default_map
            set.hero_obj.check_up # healing, refilling arrows and checking if @map is proper
            require_relative 'Map/path_finder'
            m = PathFinder.new
            path = m.find_way_through_world set.hero_obj.map.id, set.default_map
            if path
              unless set.hero_obj.go_to(path)
                path.unshift set.hero_obj.map.name unless path.include? set.hero_obj.map.name # path doesn't include the map hero is currently on.
                next_map = path[path.index(set.hero_obj.map.name) + 1] # getting number of next map
                path = m.find_way_through_world set.hero_obj.map.id, set.default_map, [next_map] # now we're trying to create path without inaccessible gateway.
                Thread.exit if path.empty?
                unless set.hero_obj.go_to path
                  Thread.exit
                end
              end
              set.hero_obj.go_to [set.default_coords]
            end
          end
          set.bot_obj.handle_kill(set.value_to_filter, set.player_reaction, set.wait)
          if @current_set.hero_obj.status.class == FalseClass
            set.status = false
          end
        }
        check_thread = Thread.new {
          setup_time = Time.now
          puts Game.log :debug,'Check thread Thread joined.'
          while bot_thread.status
            sleep(3)
            if setup_time + set.time_to_wait < Time.now and @current_set.bot_obj.can_interrupt
              puts Game.log :debug,"#{set} hasn't return for a while (too long). Killing thread and switching to next."
              bot_thread.exit
              sleep(2)
              puts Game.log :debug,"bot_thread status: #{bot_thread.status}."
            end
            if setup_time + (360 * set.time_to_wait) < Time.now
              puts Game.log :debug,"#{set} hasn't return for 6 minutes, and @current_set.bot_obj.can_interrupt is #{@current_set.bot_obj.can_interrupt}. Force exiting this thread."
              bot_thread.exit
              sleep(2)
              puts Game.log :debug,"bot_thread status: #{bot_thread.status}."
            end
          end
        }
        begin
          bot_thread.join
          check_thread.join
        rescue => error
          puts Game.log :error,"Bot #{set.bot_obj} raised an error!"
          Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
        end
        if bot_settings.size == 1
          @driver.navigate.refresh
          sleep(8)
        end
      end
    end
  end # run_bot
  def find_mob(set)
    bot_thread = Thread.new {
      # Joining bot
      puts Game.log :debug,"bot_thread joined for bot #{set.bot_obj}"
      find_mob_logic set
    }
    check_thread = Thread.new {
      setup_time = Time.now
      puts Game.log :debug,'Check thread Thread joined.'
      while bot_thread.status
        sleep(3)
        if setup_time + 1 * 60 * 60 < Time.now
          puts Game.log :debug,"#{set} hasn't return for a while (too long). Killing thread and switching to next."
          bot_thread.exit
          sleep(2)
          puts Game.log :debug,"bot_thread status: #{bot_thread.status}."
        end
      end
    }
    begin
      bot_thread.join
      check_thread.join
    rescue => error
      puts Game.log :error,"Bot #{set.bot_obj} raised an error!"
      Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
    end
  end
  def find_mob_logic(set)
    ## This function is programmable.
    ## Argument is a file with instructions.
    ## Every instructions should be in new line
    ## There are a few types of instructions:
    ##    'name'           = go to map 'name'
    ##    [[x,y]]            = go to coords x,y
    ##    empty line     = check if there is mob we're looking for.
    ##
    ## File should be in dir Sequences
    ## Instructions has to be saved as JSON!
    ## First line has to be 'Format stamp' - it means that file was changed by commands_to_json
    ## Second line is name of mob (not in JSON)
    require 'json'
    require 'fileutils'
    #
    #
    @current_set = set
    @driver.switch_hero(set.nick) unless set.bot_obj.nil?
    initialize_set(set) if set.bot_obj.nil?
    #
    # npc is mob we're looking for
    #
    npc = ''
    #
    # path is an array storing path hero went in current place. It's used later to find way back.
    #
    path = []
    File.readlines("MargoBot/Sequences/#{set.sequence_file}").each_with_index do |line, index|
      line.chomp!
      #
      if index == 0
        if line != 'Format stamp'
          puts Game.log :error,'Use commands_to_json script on given file before starting bot.'
          raise SecurityError
        end
      elsif index == 1
        npc = line
      elsif index == 2
        start_map = JSON.parse(line, :quirks_mode => true)
        path << JSON.parse(line, :quirks_mode => true)
        # trying to teleport
        towns = ['Ithan', 'Torneg', 'Werbin', 'Karka-han', 'Eder', 'Nithal', 'Tuzmer', 'Thuzal']
        if set.hero_obj.map.name != start_map and towns.include? set.hero_obj.map.name
          set.hero_obj.tp_to start_map
        elsif set.hero_obj.map.name != start_map
          require_relative 'Map/path_finder'
          m = PathFinder.new
          if m.find_way_through_world set.hero_obj.map.id, start_map
            puts Game.log :info,"Hero was't on start map, but I can move there. Will go through #{m.find_way_through_world set.hero_obj.map.id, start_map}."
            return false unless set.hero_obj.go_to(m.find_way_through_world set.hero_obj.map.id, start_map)
            puts Game.log :info,"Hero has been moved to start map #{start_map} succesfully."
          else
            #
            # try to go to any town (second argument empty)
            if m.find_way_through_world set.hero_obj.map.id
              puts Game.log :debug,"It's possible to reach one of towns."
              return false unless set.hero_obj.go_to(m.find_way_through_world set.hero_obj.map.id)
              puts Game.log :info,"Hero was moved to #{set.hero_obj.map.name}."
              set.hero_obj.tp_to start_map
              puts Game.log :info,"Teleported to #{set.hero_obj.map.name}."
            else
              puts Game.log :warning,"I'm not able to move hero to start map #{start_map}. Breaking..."
              return false
            end
          end
        end
      else
        #
        path << JSON.parse(line, :quirks_mode => true)
        set.hero_obj.go_to([JSON.parse(line, :quirks_mode => true)], set.player_reaction, set.npc_name)

        if set.hero_obj.map.is_there? npc
          if set.player_reaction
            loop {
              sleep 1
              break unless set.hero_obj.map.is_there? npc
            }
            sleep(15)
          else
            set.bot_obj.handle_kill(set.value_to_filter, set.player_reaction, set.wait)
          end
          way_back = set.hero_obj.map.create_way_back(path)
          set.hero_obj.go_to(way_back)
          return true
        end
        #
      end
      #
      sleep(0.5)
      #
      #
    end
  end
  def exp(set)
    #
    # Manage exp
    require_relative 'mob'
    @current_set = set
    @driver.switch_hero(set.nick) unless set.bot_obj.nil?
    initialize_set(set) if set.bot_obj.nil?
    ##
    ## creating new map for hero, because in this mode, 'fill' feature has to be enabled.
    set.hero_obj.map = Map.new set.hero_obj, :fill
    set.hero_obj.dazed
    unless set.sequence_file.include?(@driver.current_map_name)
      set.hero_obj.check_up
      require_relative 'Map/path_finder'
      m = PathFinder.new
      if m.find_way_through_world set.hero_obj.map.id, set.default_map
        return false unless set.hero_obj.go_to(m.find_way_through_world set.hero_obj.map.id, set.sequence_file[0])
      end
    end
    exp_thread = Thread.new {
      #
      # We have to travel all the map and kill mobs of specified lvl range
      # The idea is to randomly choose places to go and mark fields around as visited. When no places to visit left, it's done.
      #
      queue = set.sequence_file # in this case it's array of maps to visit.
      until queue.empty?
        set.hero_obj.go_to [queue[0]]
        ## creating new map for hero, because in this mode, 'fill' feature has to be enabled.
        set.hero_obj.map = Map.new set.hero_obj, :fill, :travel
        travel_map set if set.hero_obj.map.name == queue[0]
        set.hero_obj.refill_arrows
        set.hero_obj.use_items_adding_gold
        queue.shift
      end
      set.sequence_file.reverse.each do |map|
        set.hero_obj.go_to [map]
      end
    }
    check_thread = Thread.new {
      puts Game.log :debug,'Check thread Thread joined.'
      while exp_thread.status
        sleep(10)
        if @current_set.hero_obj.status == :dazed
          puts Game.log :debug,"Hero is dazed. Changing the thread."
          exp_thread.exit
          sleep(2)
          puts Game.log :debug,"bot_thread status: #{exp_thread.status}."
        end
      end
    }
    exp_thread.join
    check_thread.join

  end
  #
  # 3 methods below (travel_map, find_mobs_to_kill and closest_mob) are just to purify +exp+
  def travel_map(set)
    #
    # At beginning lets check if there are visible mobs somewhere around
    # If so, let's check if the levels are ok.
    mobs = closest_mobs
    counter = 0
    while true
      #
      # Lets check out if we can see any mobs.
      # If so, attack them
      # Otherwise, move somewhere around and check it out again then
      if mobs.nil?
        #
        # Ok, there are no mobs ;/
        # Lets go to random place at map and then check it.
        fields_to_see = set.hero_obj.map.unseen_fields
        accessible_fields = set.hero_obj.map.amount_of_accessible_fields
        puts Game.log :debug,"Fields to see #{fields_to_see}"
        puts Game.log :debug,"#{((fields_to_see.size/accessible_fields.to_f)*100).round 2}% of fields remaining unseen."
        return true if fields_to_see.size/accessible_fields.to_f < 0.05
        coords = fields_to_see.keys
        max = coords.size
        coords = coords[rand(max) - 1]
        puts Game.log :debug,"Going to random coords: #{coords}."
        set.hero_obj.go_to [coords]
        mobs = closest_mobs
      else
        #
        # Now we have array with mobs which are ok to attack, let's do this.
        mobs = closest_mobs
        while mobs
          mobs.each do |mob|
            puts Game.log :debug,"Going to mob #{mob.name}."
            if mob.driver_element
              result = set.bot_obj.attack(mob, false, false, false, true)
              if result == :lose
                puts Game.log :info,"#{set.hero_obj.nick} lost battle with #{mob.name}."
                sleep 10
                set.hero_obj.dazed
              end
              set.hero_obj.heal if set.hero_obj.need_healing?
              set.bot_obj.loot
              counter+=1
              puts Game.log :info,"Killed #{counter} mobs."
              set.hero_obj.refill_arrows if counter%10 == 0
            else
              puts Game.log :warning,"Something went wrong while getting mob #{mob.name} driver element."
            end
          end
          mobs = closest_mobs
        end
      end
    end
  end
  def find_mobs_to_kill
    mobs = @current_set.hero_obj.map.visible_mobs
    puts Game.log "#{mobs.size} mobs was found." if mobs
    mobs.map!{ |mob|
      mo = Mob.new mob, @driver
      if mo.lvl >= @current_set.lvl_range[0] and mo.lvl <= @current_set.lvl_range[1] and mo.type == :mob and mo.group_size.to_i <= @current_set.max_group
        mo
      else
        puts Game.log :debug,"Won't attack #{mo.type}. Lvl: #{mo.lvl}, set lvl_range: #{@current_set.lvl_range},
                        group_size: #{mo.group_size}, set max_group: #{@current_set.max_group}."
        nil
      end
    }
    mobs.compact!
    mobs
  end
  def closest_mobs
    mobs = find_mobs_to_kill
    return nil if mobs.empty?

    mobs_dist = {}
    mobs.each do |mob|
      path = @current_set.hero_obj.map.find_path mob.coords, mob, :quick_mode, :without_npc, :const_mob_field
      mobs_dist[mob] = path.size if path
    end
    #
    # hash.sort_by return nested array of.
    #              In this case the first element is an array storing mob with the shortest path
    begin
      m = (mobs_dist.sort_by{|k,v| v})
      [m[0][0], m[1][0]]
    rescue
      nil
    end
  end

end # MargoBot










