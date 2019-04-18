class ScriptManager
  #
  # Notice, that there are actually 2 types of scripts:
  # 1. Scripts which are used during regular playing, like find_path_in_exception or add_map_with_gateways.
  #       These scripts has no security impact and it can be used without any confirmation.
  #
  # 2. Scripts which USE the structure of the bot. "travel_world" is an example.
  #       This type of scripts can be (at least partly) controlled by console during usage, so to avoid security problems and abuse of bot
  #       possibilities without permission, there is a list of known script which cannot do any harm. Moreover - to use it,
  #       user has to log in with :script permissions.
  #
  # Names of all scripts of "type 2" which can be used are stored in scripts/known_scripts.json file.
  # Note, that in type 2 scripts, username has to be name of script (saved to known_scripts file)
  require_relative '../game'
  def delete_logs
    system('rm Logs/margobot.log*')
  end
  def delete_temporary_files
    # delete map and settings data files which are not used anymore
    require 'time'
    require 'json'
    deleted = 0
    map_files = Dir.glob "#{Game::MAIN_DIR}Data/MapData/*"
    set_files = Dir.glob "#{Game::MAIN_DIR}Data/Sets/*"
    map_files.each do |file|
      begin
        time = Time.parse JSON.parse(File.readlines(file)[-1])
        # note that in this case it's time of last read of the file.
        puts Game.log :debug,"Set #{file}: last read time #{time}."
        if Time.now > time + 60*60*4 # if last read was more than 4 hours ago
          File.delete file
          deleted+=1
        end
      rescue
        puts Game.log :error,"#{file} raised an error."
      end
    end
    set_files.each do |file|
      begin
        time = Time.parse JSON.parse(File.readlines(file)[10])
        # note that in this case it's end time specified when setting up the bot.
        puts Game.log :debug,"Set #{file}: end time #{time}."
        if Time.now > time
          File.delete file
          deleted+=1
        end
      rescue
        puts Game.log :error,"#{file} raised an error. Will delete it."
        File.delete file
      end
    end
    puts Game.log :info,"#{deleted} files deleted."
    deleted
  end
  def add_map_with_gateways(driver)
    #
    # redis server contains, let's say, two types of data:
    # # first: key is the map name and value is an array which contains ids of all maps with given name.
    # # second: key is the map id and value is an array which contains ids of all gateways that are accessible from given map.
    #
    require_relative '../local_driver'
    require 'json'
    return false unless driver.map_loaded?
    map_id = driver.script 'return map.id'
    map_name = driver.script 'return map.name'
    return [nil,[]] unless $redis.get(map_id).nil?
    if $redis.get(map_name).nil?
      $redis.set map_name, [map_id].to_json
      puts Game.log :debug, "Added #{map_name}: #{[map_id]} to redis db."
    else
      maps = $redis.get map_name
      maps = JSON.parse(maps)
      unless maps.include?(map_id)
        maps << map_id
        $redis.set map_name, maps.to_json
        puts Game.log :debug, "Actualised #{map_name} in redis db (added #{map_id})."
      end
    end
    gateways = []
    begin
      driver.script('return Object.keys(g.gwIds)').each { |gw|
        a = driver.find_elements(class: "gwmap#{gw}")[0].attribute(:tip)
        # a is map name of given gw id, which is also id of the map.
        #
        # some gateways has descriptions like 'key required', 'accessible on levels 10-50', etc...
        # all of those starts with <br> however (it's in new line), so it's easy to get rid of it.
        a.slice! /<br>.*/
        gateways << gw.to_i
        if $redis.get(a).nil?
          $redis.set a, [gw.to_i].to_json
          puts Game.log :debug, "Added #{a}: #{[gw]} to redis db."
        else
          maps = JSON.parse($redis.get(a))
          unless maps.include?(gw.to_i)
            maps << gw.to_i
            $redis.set a, maps.to_json
            puts Game.log :debug, "Actualised #{a} in redis db (added #{gw})."
          end
        end
      }
      puts Game.log :debug, "Gateways: #{gateways}."
    rescue => error
      puts Game.log :error,"Something wen't wrong while getting gateways."
      puts Game.log :error, "#{error}: #{error.backtrace[-1]}"
      return false
    end
    puts Game.log :debug,"Adding #{map_name} (id: #{map_id}) to db. Gateways: #{gateways}."
    x = $redis.set map_id.to_i, [map_name.to_s, gateways].to_json
    puts Game.log :debug,"Redis: #{x}."
    [map_name, gateways]
  end
  def find_path_in_exception(start, target)
    require 'json'
    start = JSON.parse($redis.get(start))[0] if start.is_a? String
    target = JSON.parse($redis.get(target))[0] if target.is_a? String
    path_exceptions = Dir.glob "#{Game::MAIN_DIR}MargoBot/Exceptions/path*"
    puts Game.log :debug, "Searching exception for #{start} - #{target}. Found #{path_exceptions.size} files with exceptions."
    path_exceptions.each do |file|
      data = JSON.parse File.read(file)
      if data["problem"].map{|x| JSON.parse($redis.get(x))[0] }.include? start and data["problem"].map{|x| JSON.parse($redis.get(x))[0]}.include? target
        if JSON.parse($redis.get(data["problem"][0]))[0] == start
          puts Game.log :debug, "Found path #{data['solution']}."
          return data["solution"]
        else
          puts Game.log :debug, "Found path #{data['solution'].reverse}."
          return data["solution"].reverse
        end
      end
    end
    puts Game.log :debug, "Couldn't find exception."
    nil
  end
  def travel_world
    require 'json'
    require_relative '../bot_manager'
    # # # # # # # # # # #
    # # # # # # # # # # # # # # # # # # # # # # #
    # this script will use the bot to travel the map in order to actualise redis db
    # it will create queue with maps to visit. It will be sorted by a priority.
    # Priority will be determined basing on amount of known gateways of that map.
    # queue is created in get_next_map method (it returns id of first map in queue)
    # # # # # # # # # # # # # # # # # # # # # # #
    # # # # # # # # # # #
    bot_man = BotManager.new :script, 'travel_world', []
    bot_man.driver = LocalDriver.new
    puts Game.log :info, "Enter username: "
    username = gets.chomp
    puts Game.log :info, "Enter password: "
    password = gets.chomp
    bot_man.driver.log_in username, password
    puts Game.log :info, "Enter nickname: "
    nickname = gets.chomp
    bot_man.driver.switch_hero nickname


    mirek = MargoBot.new bot_man.driver
    mirek.bot_manager = bot_man
    require_relative '../bot'
    hero = Bot.new('', bot_man.driver).hero
    added_maps = []
    without = []
    20.times do
      map = get_next_map without
      result = hero.go_to [map[1][0], map[0]], false, nil
      added_maps << map if result
      without << map[0]
    end
    puts Game.log :info, "Visited #{added_maps.size} maps: #{added_maps}."
  end

  #private
  def get_next_map(without = [])
    # ++ ========= ++ #
    # this method return map which hasn't been visited yet (is not present in database) which should be visited next (is the most important)
    # ++ ========= ++ #
    require 'json'
    unknown_maps_with_priority = {}
    all_maps_in_db = []
    keys = $redis.keys '*' # gets all keys
    keys.each do |key|
      all_maps_in_db << key.to_i if key.to_i != 0 # adds to array only int keys (string keys are unnecessary there)
    end
    all_maps_in_db.each do |id_of_known_map|
      maps_in_neighbourhood = JSON.parse($redis.get(id_of_known_map))[1]
      maps_in_neighbourhood.each do |neighbour|
        unless keys.include? neighbour.to_s # adding map to queue if isn't present in db (hasn't been visited yet)
          unknown_maps_with_priority[neighbour] << id_of_known_map if     unknown_maps_with_priority[neighbour] # if map has been added to hash already, add the map to array
          unknown_maps_with_priority[neighbour] =  [id_of_known_map] unless unknown_maps_with_priority[neighbour] # otherwise create new key
        end
      end
    end
    sorted = unknown_maps_with_priority.sort_by {|k,v| v.size}
    to_return = nil
    sorted.reverse.each do |map|
      to_return = map unless without.include? map[0]
      break unless to_return.nil?
    end
    puts Game.log :info, "#{sorted.size} known maps which are not saved in db."
    puts Game.log :info, "Map #{to_return[0]} with #{to_return[1].size} references is the most needed to see."
    to_return
  end
end

