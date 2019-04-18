class Map
  require_relative '../local_driver'
  require_relative '../mob'
  require_relative '../hero'
  require_relative '../margobot'

  attr_accessor :driver, :hero, :travel
  attr_reader :filename, :name

  def initialize(hero, *args)
    fill = false
    @travel = false
    fill = true if args.include? :fill
    @travel = true if args.include? :travel
    # when fill is true, all inaccessible coords on map will be marked as false
    require 'securerandom'
    @filename = SecureRandom.hex 15 # 30 char long name

    @hero = hero
    @driver = @hero.driver
    require_relative '../scripts/script_manager'
    ScriptManager.new.add_map_with_gateways @driver
    puts Game.log :debug, 'Creating new map.'
    stt = Time.now
    until @driver.map_loaded?
      sleep 0.1
      @driver.navigate.refresh if Time.now > stt + 5
      stt = Time.now           if Time.now > stt + 5
    end
    @name = @driver.script('return map.name')
    collisions = @driver.script('return map.col')
    size = {}
    size['x'] = @driver.script('return map.x')
    size['y'] = @driver.script('return map.y')
    puts Game.log :debug, 'Getting gateways'
    gateways = set_gateways
    map = create_map(size['x'], size['y'], all_collisions)
    map = fill_inaccessible_fields(map) if fill
    amount_of_accessible_fields = map.size
    basic_map = map
    empty_map = map
    @basic_map_instance = map
    @empty_map_instance = map
    accessible = {}
    map.each { |k,v| accessible[k] = v if v }
    id = @driver.current_map_id
    data = [id.to_json, @name.to_json,collisions.to_json, size.to_json, gateways.to_json, basic_map.to_json,
                          empty_map.to_json, accessible.to_json, amount_of_accessible_fields.to_json, Time.now.to_json]
    refresh_data data
    puts Game.log :debug, "Map #{@name} (#{@filename}) has been created."
  end
  def change_basic_map(map)
    @basic_map_instance = map
    #refresh_data [name.to_json,collisions.to_json, size.to_json, gateways.to_json, map.to_json,
    #              empty_map.to_json, unseen_fields.to_json, amount_of_accessible_fields.to_json, Time.now.to_json]
  end
  def change_accessible(map)
    af = {}
    map.each { |k,v| af[k] = v if v }
    refresh_data [id.to_json, name.to_json,collisions.to_json, size.to_json, gateways.to_json, basic_map.to_json,
                  empty_map.to_json, af.to_json, amount_of_accessible_fields.to_json, Time.now.to_json]
  end
  def refresh_data(data = [])
    if File.exist?("#{Game::MAIN_DIR}Data/MapData/#{@filename}")
      File.delete "#{Game::MAIN_DIR}Data/MapData/#{@filename}"
    end
    Game.save_data(@filename, data, "Data/MapData/")
  end
  def is_there?(npc)
    # anybody out there
    begin
      @driver.script("{var npc_keys = Object.keys(g.npc); var is = false;
                    npc_keys.forEach(function(id) { if(g.npc[id].nick == \"#{npc}\"){ is = id;}}); return is;}" )
    rescue
      # raises an error usually when page haven't load yet.
      # it the safest way to return false in this case.
      false
    end
    # returned value: false or id of mob
  end
  def mob_id_on_coords(coords)
    # getting id of mob which is on given coordinates
    #
    @driver.script("{var npc_keys = Object.keys(g.npc); var mob = false;
                    npc_keys.forEach(function(id) { if(g.npc[id].x == #{coords[0]} && g.npc[id].y == #{coords[1]}){ mob = id;}}); return mob;}")
    # return value: false or id of mob
  end
  def visible_mobs
    #
    # Getting id's of all visible mobs
    @driver.script("{var npc_keys = Object.keys(g.npc); var mobs = [];
                    npc_keys.forEach(function(id) { if(g.npc[id].x && g.npc[id].y && g.npc[id]['lvl'] != 0){ mobs.push(id);}}); return mobs;}")
    # return = array
  end
  def set_gateways
    gates = {}
    #
    # Script below return hash with key - id, value - coords.
    # To find name of the gateway (map which it send to), it's needed to find element "gwmap#{id}"
    #
    gw_ids  = @driver.script('return g.gwIds')
    gw_ids.each do |gw|
      #
      # coords are stored in gw[1]
      # its saved like that "15.34" (x = 15, y = 34) (xx.yy)
      coords = gw[1].split('.')
      #
      #
      gates[gw[0].to_i] = coords # gw[1] - coords
      #
    end # end of each
    gates # return
  end
  def get_all_gateways
    gates = {}
    #
    # Method will return all gateways which are on current map. The +set_gateways+ method returns only one gateway to each map.
    # I mean, that there are sometimes multiple gateways leading to the same map, and algorithm below will find all of them
    # (however this method is slower and less bulletproof than +set_gateways+).
    #
    # Ok, there are two types of gateways.
    #   First are the regular ones - those are visible as regular elements, and for what I know, we can't ask JS for coordinates of them.
    #           But, it is possible to count x,y basing on the position.
    #   Second are visible as mob elements, and we can just ask JS for it's coordinates. However, we can't see them from distance. So, it's kind of useless.
    #
    gateways1 = @driver.find_elements css: "[class^=\"gw gwmap\"]"
    gateways1.each do |gw|
      name = gw.tip
      coords = gw.style.scan /\d+/
      coords.map! { |e| e.to_i/32 }
      if gates[name]
        gates[name] << coords
      else
        gates[name] = [coords]
      end
    end
    gateways2 = @driver.find_elements css: "[]"
  end
  def go_to_map(target, player_reaction = false, mob_to_find = nil)
    ##
    instance_name = name
    instance_id = id
    ins_gateways = gateways
    if target.is_a? String
      maps = JSON.parse($redis.get(target))
      maps.each do |one|
        # choosing the one which is actual neighbour.
        ins_gateways.keys.each do |gw|
          target = one if gw.to_i == one.to_i # redis can store multiple maps under one name (when there are several maps with same name in world)
        end
      end
    end
    return true if @driver.current_map_id == target
    puts Game.log :info, "Going to map #{target}. Current map #{@driver.current_map_id}."
    until @driver.current_map_id != instance_id # nil (loading map) or another name.
      coords = ins_gateways[target]
      #
      if coords.nil?
        ins_gateways.each do |gw, crd|
          if (gw.to_s.downcase) == (target.to_s.downcase) and gw.to_s.downcase != name
            coords = crd
            break
          end
        end
        if coords.nil?
          puts Game.log :warn, "Wrong map name given. Can't find that name (#{target}) in accessible gateways."
          require_relative 'path_finder'
          path = PathFinder.new.find_way_through_world(instance_id, target)
          if path
            return true if @hero.go_to path, player_reaction, mob_to_find
          end
          return false
        end
      end
      #
      # if move_to_coords returned false - something went wrong.
      v = move_to_coords([coords[0].to_i, coords[1].to_i], player_reaction,nil, mob_to_find, target)
      return false if v.class == FalseClass
      return :stuck if v == :stuck
      return :found_mob if v == :found_mob
      #
      # change the map
      #
      sleep 0.1
      @hero.click_in_hero_menu('Przejdź')
      sleep 0.4
      if @driver.current_map_name == instance_name
        id = mob_id_on_coords coords
        if id
            mo = Mob.new id, @driver
            if mo.name.to_s.downcase == target.to_s.downcase
              puts Game.log :debug, "The gateway to #{target} requires to click it in order to use it."
              @driver.action.move_to(mo.driver_element).move_by(0, -((mo.size[1] - 2)/2)).click.perform
            end
        end
      end
      if @driver.find_elements(id: 'alert')[0]
        elem = @driver.find_element(id: 'alert')
        if elem.displayed?
          if elem.find_elements(class: 'a2')[0]
            if elem.find_elements(class: 'a2')[0].attribute(:innerHTML).match /Nie możesz przejść bez klucza!/
              puts Game.log "Hero doesn't have required key to enter map #{target}."
              sleep 0.3
              @driver.find_element(id: 'a_ok').click
              sleep 5
              return false
            elsif  elem.find_elements(class: 'a2')[0].attribute(:innerHTML).match /Przejście to dostępne jest dla graczy/
              puts Game.log "Hero has wrong lvl to enter map #{target}."
              sleep 0.3
              @driver.find_element(id: 'a_ok').click
              return false
            end
          end
        end
      end
    end
    sleep 0.1 until @driver.map_loaded?
    puts Game.log :info,"Moved hero #{@hero.nick} to #{@driver.current_map_name}."
    true
    #
  end
  def move_to_mob(mob_obj, player_reaction)
    mob_elem = mob_obj.driver_element
    if mob_elem.nil?
      puts Game.log :debug, "Given mob doesn't exists or can't be seen."
      return false
    end
    if @driver.touch?(@hero.driver_element, mob_elem, 1, 1, true)
      return true
    end
    puts Game.log :debug, 'Calling move_to_coords.'
    v = move_to_coords nil, player_reaction, mob_obj, nil
    if v.class == TrueClass
      true
    elsif v == :stuck
      :stuck
    elsif v == :found_mob
      :found_mob
    elsif v.class == FalseClass
      false
    else
      puts Game.log :warning, "move_to_coords returned unknown value #{v}. Returning false."
      false
    end
  end
  def path_to_moves(path)
    moves = []
    unless path
      return false
    end
    path.each_with_index do |cor, i|
      # path stores nested arrays with coords.
      # Maximum difference between adjacent elements is 1. So, it's not possible to be x and y changed.
      # So, when we found whats changed, we can break and go to next.
      #
      # if current x is greater than x of next position
      # elsif current x if smaller than x of next position
      # elsif current y is greater than y of next position
      # ELSE - current y is smaller than y of next position (something had to change)
      unless path[i.next] # when path[i.next] is nil, it means current position is the last one.
        break
      end
      if cor[0] > path[i.next][0] # current x > next x
        moves << 'a' # a - left
      elsif cor[0] < path[i.next][0] # current x < next x
        moves << 'd' # d - right
      elsif cor[1] > path[i.next][1] # current y > next y
        moves << 'w' # w - up   ## this one can be tricky, since the higher on map hero is, the lower y becomes. Not the other way.
      else
        moves << 's' # s - down
      end
    end
    moves
  end
  def move_to_coords(coords = nil, player_reaction = false, mob = nil, mob_to_find = nil, target = nil)
    #
    # this methods move to given coords and do some other actions
    #
    # coords is point where hero will be after calling this methods (if it's accessible)
    # #
    # player_reaction is needed to know if bot can do some actions when there are players around
    # #
    # mob is usually used when calling this method from Bot.handle_kill.
    #     When it's driver element, bot will check if it still exist and move to coordsd somewhere around it.
    # #
    # mob_to_find is string (name of mob). When it's given, after each several steps bot will check if there is mob we're looking for.
    # mob_to_find is usually used while searching special heroes (MargoBot.find_mob)
    # But be careful - this method will just return true when the mob will be seen. It won't do any further actions.
    # So after each return check again if there's a mob. It takes about 8ms so for single checkup so it won't be a problem.
    #
    const_mob_field = false
    if mob and coords.nil?
      coords = mob.coords
      bm = basic_map
      bm[coords] = -1
      change_basic_map bm
      const_mob_field = true
    end
    #
    # getting map
    ins_basic_map = basic_map
    #
    unless ins_basic_map[coords]
      puts Game.log :debug, "Given coords #{coords} are not accessible. Going somewhere around it."
      coords = find_closest_accessible_field coords
    end
    until coords == coordinates
      moves = []
      loop {
        path = nil
        if mob and const_mob_field
          path = find_path coords, nil,:const_mob_field
        else
          path = find_path coords
        end

        moves = path_to_moves path
        if moves
          puts Game.log :debug, "Moves: #{moves}."
          break
        else
          puts Game.log :debug, 'find_path returned false.'
          # creating path basing only on permanent collisions (mobs aren't)
          #
          pat = find_path(coords, nil, :without_npc)
          if pat
            puts Game.log :debug, 'It is possible to clear the path by killing some mobs.'
            #
            # Finding coords where the mob is, getting id and killing it.
            pat.reverse.each do |crd|
              # +crd+: [x,y]
              #
              mob_on_path = mob_id_on_coords crd
              if mob_on_path
                mob_on_path = Mob.new(mob_id_on_coords(crd), @driver)
              else
                # It's important when group of mobs was killed, or somebody else killed it.
                erase_collision crd if ins_basic_map[crd] != -1
              end
              if mob_on_path and find_path(mob_on_path.coords, mob_on_path, :const_mob_field)
                # Ok, it's tricky:
                # Some gateways are weird, and to use it we need to click at it.
                # I've checked and these gateways are displayed on map as npcs.
                # So, if +mob_on_path+ name is the same as the gateway it means this is one of those.
                # Notice that it's only when we're going to another map, so check the +target+ option (gw name).
                # target can be also id of the map, so we need to check this as
                # we're checking this by checking if redis db contains that name. But, the names are sometimes different (Map originally "Abc abc" is saved as "Abc Abc" etc.)
                yes = false
                $redis.keys('*').each do |key|
                  yes = true if key.to_s.downcase == mob_on_path.name.downcase
                  break if yes
                end
                if mob_on_path.name.downcase == target.to_s.downcase or yes
                  puts Game.log :debug, 'The gateway is set as npc.'
                  erase_collision coords
                  move_to_mob  mob_on_path, player_reaction
                  @driver.action.move_to(mob_on_path.driver_element).move_by(0, -((mob_on_path.size[1]/2)-4)).click.perform
                  #
                  # sometimes the dialog window can pop up after the click. If so, let's find it out.
                  #
                  sleep 0.875
                  dialog = @driver.find_elements(id: 'dialog')[0]
                  if dialog
                    if dialog.displayed?
                      replies = dialog.find_elements css: "[class=\"icon icon LINE_OPTION\"]"
                      if replies[0]
                        replies[0].click
                      else
                        puts Game.log :info, "Can't cross the gateway."
                        return false
                      end
                    end
                  end
                  return true
                end
                #
                # Killing mob.
                # Arguments: attack(mob_obj, wait, player_reaction, get_group, auto_battle)
                result = @hero.bot.attack(mob_on_path, false, false, false, true)
                @hero.bot.loot
                @hero.heal if @hero.need_healing?
                if result == :lose
                  puts Game.log :info, "#{@hero.nick} lost battle with #{mob_on_path.name}."
                  sleep 10
                  @hero.dazed
                  return false
                end
                #
                puts Game.log :info, "Killed mob #{mob_on_path.name}."
                erase_collision crd
                break
              end
              #
            end

          else
            if coords == @hero.coordinates
              return true
            end
            puts Game.log :debug, 'It is impossible to reach given coords.'
            af = unseen_fields
            af[coords] = false
            change_accessible af
            puts Game.log :debug, "Hero coordinates: #{coordinates}."
            puts Game.log :debug, "Target coords: #{coords}"
            return false
          end
        end
      }

      compressed_moves = compress_moves(moves)
      moves_counter = 0
      coords_before_perform = coordinates
      compressed_moves.each_with_index do |move_set, index|
        puts Game.log :debug,"Performing #{move_set} move."
        #
        # compressed_moves = [['a',5],['w',2],['d',1]...]
        # move_set[0] = key, move_set[1] = number in a row
        #
        return false if player_reaction and @driver.other_players?

        if mob
          unless mob.driver_element
            puts Game.log :debug,'Mob has disappeared (probably killed by somebody else).'
            return false
          end
          return true if (coordinates[0] - mob.coords[0]).abs <= 1 and (coordinates[1] - mob.coords[1]).abs <=1
        end
        #
        # time needed to travel 1 block is about 200ms.
        #
        @driver.press_key(move_set[0], 0.03 + move_set[1] * 0.18)
        moves_counter += move_set[1]
        #
        if index % 4 == 0
          if mob_to_find
            if is_there? mob_to_find
              puts Game.log :info,"#{mob_to_find} can be seen. Returning."
              return :found_mob
            end
          end
        end
        #
        # checking if the coordinates are accessible for sure
        coords = find_closest_accessible_field coords unless ins_basic_map[coords]
        #
        # breaking sometimes in order to refresh path
        break if moves_counter > 8
        break if @driver.fight?
      end
      set_as_visited coordinates if @travel
      #
      # Returning when hero hasn't move.
      if coords_before_perform == coordinates and moves_counter > 0
        if @driver.fight?
          result = @hero.bot.attack
          @hero.bot.loot
          @hero.heal if @hero.need_healing? and result == :win
          if result == :lose
            puts Game.log :info,"#{@hero.nick} lost battle which was not started by bot."
            sleep 10
            @hero.dazed
            return false
          end
        else
          return :stuck
        end
      end
      #
      # if moving to mob, there is another condition to return
      # because hero can't go on the field where is mob, return when hero touches mob.
      #
      if mob
        return true if @driver.touch?(@hero.driver_element, mob.driver_element, 1,1,true) or @driver.fight?
      end
    end
    true
  end # move_to_coords
  def set_as_visited(crd)
    #
    puts Game.log :debug,"Setting as visited fields around #{crd}."
    left_corner = [crd[0] - 9, crd[1] - 9]
    x = left_corner[0]
    y = left_corner[1]
    seen_coords = []
    19.times do |n|
      19.times do |k|
        seen_coords << [x+n, y+k]
      end
    end
    ac_f = unseen_fields
    seen_coords.each do |coords|
      ac_f[coords] = false if ac_f[coords]
    end
    change_accessible ac_f
  end
  def coordinates
    @hero.coordinates
  end # returns [x,y]
  def erase_collision(coords)
    puts Game.log :debug,"Erasing collision on coords #{coords}."
    return false unless coords.is_a? Array
    b_m = basic_map
    return true if b_m[coords] == -1
    b_m[coords] = -1
    change_basic_map b_m
    puts Game.log :debug,'Collision has been erased.'
  end
  def create_map(x,y, cols)
    map = {}
    x.times do |n|
      y.times do |m|
        if cols[n + m * x] == '1'
          map[[n,m]] = false # not visited and there is a collision so hero can't go there.
        else
          map[[n,m]] = -1 # not visited but accessible
        end
      end
    end
    map
  end
  def add_npc_collisions_to_map
    begin
      m = @driver.script("return Object.keys(g.npccol)") # ids of fields where are the colliding npc
    rescue
      m = nil
    end
    if m.nil?
       sleep 5
       m = @driver.script("return Object.keys(g.npccol)") # ids of fields where are the colliding npc
    end
    return false if m.nil?
    foo = basic_map
    m.each do |id|
      # id = x + 256*y
      y = (id.to_i/256.0).floor
      x = id.to_i - 256*y
      foo[[x,y]] = false
    end
    change_basic_map foo
  end
  def all_collisions
    cols = ''
    @driver.script('return map.col').split('').each do |c|
      cols += c
    end
    cols
  end
  def compress_moves(moves)
    compressed_moves = [[moves[0], 0]]
    moves.each_with_index { |m, i|
      compressed_moves[-1][1] += 1
      if m != moves[i+1] and not moves[i+1].nil?
        compressed_moves << [moves[i+1], 0]
      elsif compressed_moves[-1][1] >= 8 and not moves[i+1].nil?
        compressed_moves << [moves[i+1], 0]
      end
    }
    compressed_moves
  end
  def find_path(finish, mob = nil, *args) # finish - ary
    start = [coordinates[0], coordinates[1]] # current position
    without_npc = false
    quick_mode = false
    const_mob_field = false
    without_npc = true if args.include? :without_npc
    quick_mode = true if args.include? :quick_mode
    const_mob_field = true if args.include? :const_mob_field
    if without_npc
      map = empty_map
    elsif const_mob_field
      add_npc_collisions_to_map
      bm = basic_map
      bm[finish] = -1
      change_basic_map bm
      map = basic_map
    else
      add_npc_collisions_to_map
      map = basic_map
    end


    foo = Time.now
    if mob.nil?
      path = dijkstra(map, start, finish)
    else
      #
      # when moving to mob, it's impossible to go exactly on it's coords.
      # for example, when mob is on coords [10,10], hero can't enter [10,10].
      # So, we're creating 4 path here, for coords [9,10], [11, 10], [10, 9], [10, 11]
      # Then we're choosing the shortest one (to avoid 'rounding' mob.).
      #
      # When +quick_mode+ is set to true, we'll return the first found path.
      #
      f_x = finish[0]
      f_y = finish[1]
      paths = []
      if map[[f_x - 1, f_y]]
        path = dijkstra(map, start, [f_x - 1, f_y])
        return path if quick_mode and not path.empty?
        paths << path
      end
      if map[[f_x + 1, f_y]]
        path = dijkstra(map, start, [f_x + 1, f_y])
        return path if quick_mode and not path.empty?
        paths << path
      end
      if map[[f_x, f_y - 1]]
        path = dijkstra(map, start, [f_x, f_y - 1])
        return path if quick_mode and not path.empty?
        paths << path
      end
      if map[[f_x, f_y + 1]]
        path = dijkstra(map, start, [f_x, f_y + 1])
        return path if quick_mode and not path.empty?
        paths << path
      end
      paths.map! do |p|
        unless p.empty?
          p
        end
      end
      paths.compact!
      path = (paths.sort_by {|x| x.size})[0]
      unless path
        return false
      end
    end
    if path.empty?
      puts Game.log :debug,"Path is empty. Probably it's impossible to reach given coords: #{finish}."
      nil # return
    else
      puts Game.log :debug,"Path (#{path.size} steps) #{path} has been found in #{Time.now - foo}s."
      path # return
    end
  end
  def all_neighbours(pos, map)
    neighbours_cords = [[pos[0]-1,pos[1]],[pos[0]+1,pos[1]],[pos[0],pos[1]+1],[pos[0],pos[1]-1]] # only left, right, up, down
    neighbours = []
    neighbours_cords.each do |position|
      if map[position]
        neighbours << position
      end
    end
    neighbours
  end
  def not_visited_neighbours(pos, map)
    neighbours_cords = [[pos[0]-1,pos[1]],[pos[0]+1,pos[1]],[pos[0],pos[1]+1],[pos[0],pos[1]-1]] # only left, right, up, down
    neighbours = []
    neighbours_cords.each do |position|
      if map[position] == -1
        neighbours << position
      end
    end
    neighbours
  end
  def dijkstra(map,start,finish)
    #
    # Warning! +finish+ has to be accessible!
    #           When moving to mob, call this method with finnish somewhere around target.
    #           If finnish od basic_map is set to false, it may raise an error or loop for infinity.
    #
    #
    #
    # When starts from field next to finish.
    return [start, finish] if all_neighbours(start, map).include?(finish)
    #
    map[start] = 0
    stack = [start]
    stop = false
    until stop
      if stack.size == 0
        puts Game.log :debug,'Stack size is 0.'
        break
      end
      v = stack[0]
      stack.shift
      not_visited_neighbours(v, map).each do |pos|
        #
        if map[pos]
          map[pos] = map[v] + 1
          stack << pos
        end
        if all_neighbours(pos, map).include?(finish)
          map[finish] = map[pos] + 1
          stop = true
          break
        end
        #
      end
    end
    #
    #
    #
    #
    w = finish
    path = [w]
    until path.include?(start)
      cur_pos = path[-1] # for check-up
      all_neighbours(path[-1], map).each do |neigh|
        if map[neigh] and map[path[-1]]
          if map[neigh] < map[path[-1]] and map[neigh] != -1
            path << neigh
            break
          end
        end
      end
      #
      # when path[-1] == cur_pos, it's impossible to go to pointed coordinates.
      # algorithm exit loop, when path include start coords.
      # If cur_pos changes it means that there are still some possible moves.
      # When it doesn't change, it won't ever and loop will be infinite.
      #
      if path[-1] == cur_pos
        return []
      end
    end
    #
    path.reverse
  end
  def create_way_back(path)
    #
    #
    # INPUT: full path to current map/position
    # OUTPUT: shorter (not necessarily the shortest, but usually it is) path to start (first) position
    #
    # EXAMPLE:
    #     INPUT:  [start, map1, map2, map1, map3, coords1, coords2, map4]
    #     OUTPUT: [map3, start] (reversed, without map4 since it's current map) (coords are deleted.)
    #
    #
    path.map! {|p| p if p.is_a? String}
    path.compact!
    loop {
      changed = false
      path.each_with_index do |place, index|
        if path[index - 2] == place and index >= 2
          path[index - 2] = nil
          path[index - 1] = nil
          changed = true
        end
      end # each
      path.compact!
      break unless changed
    }
    #
    path.pop
    path.reverse # return
  end # create...
  def fill_inaccessible_fields(map)
    # This method sets to false fields which cannot be accessed.
    # To be easier to imagine, see, how the map looks:
    # 0  1  2  3  4  5
    # 1  +  +  +  +  +
    # 2  +  o  o  o  +
    # 3  o  *  *  *  o
    # 4  +  o  o  *  o
    # 5  +  +  o  *  o
    #
    # + and * means that field is marked as false on collisions (it can be accessed)
    # o means that field is marked as true on collisions - it can't be accessed
    # * are fields which can be actually accessed. + can't because are out of bounds.
    # So, as it can be seen, on the map (returned from script in driver), only borders are marked as fields where hero can't go.
    # In theory, if you would be able somehow to cross those borders, you could easily walk around on 'prohibited' area.
    # This is how the game engine is written.
    #
    # This state of affairs can lead to some confusion and even errors in some methods using map. For example +find_closest_accessible_field+
    # To avoid determining if the field can be accessed by trying to find a path every time it's needed,
    #       we'll just mark all those fields behind border as inaccessible.
    #
    # Notice that maps which can be accessed by several gateways are often split in half and this method won't work well on those.
    #                                                                                     (will find only a part of accessible fields)
    #
    #
    # coordinates return current position of hero. It's for sure accessible field because the hero is there.
    puts Game.log :debug,'Filling inaccessible coordinates.'
    sc = coordinates
    accessible_coords = [sc]
    stack = [sc]
    stt = Time.now
    map_copy = map.dup
    until stack.empty?
      all_neighbours(stack[0], map).each { |crd|
        accessible_coords << crd
        stack << crd unless map_copy[crd] == :visited
        map_copy[crd] = :visited
      }
      stack.shift
    end

    accessible_coords.uniq!
    puts Game.log :debug,"Found #{accessible_coords.size} accessible fields."
    # map is hash
    map_cp = map.dup
    #
    accessible_coords.each do |coords|
      map_cp[coords] = :access
    end
    #
    #
    map_cp.each { |k,v|
      if v == :access
        map[k] = -1
      else
        map[k] = false
      end
    }
    puts Game.log :debug,"Filled coordinates in #{(Time.now - stt)*1000}ms."
    #
    map # return
  end
  def find_closest_accessible_field(coords)
    #
    # This method will return closest field where hero can go
    #
    # Field is accessible when it's value on basic_map is not false.
    #
    # Important - fields may seem to be accessible for some time and then change to not accessible (loaded or spawned mob) -
    #                                                                                                 - so the return value is just a temporary answer
    #
    # In fields array we're going to store level of closest fields.
    # For example when there are no fields in neighbourhood (1 level), no fields in radius 2 (2 level), and 2 fields in radius 3,
    #                                                                           fields array will be filled with these 2 fields.
    #
    puts Game.log :debug,"Searching accessible coords around #{coords}."
    fields = []
    ins_basic_map = basic_map
    n = 1
    loop {
      n.times do |a|
        x = a+1
        n.times do |b|
          y = b+1
          fields << [coords[0] + x, coords[1] + y] if ins_basic_map[[coords[0] + x, coords[1] + y]]
          fields << [coords[0] + x, coords[1] + y] if ins_basic_map[[coords[0] + x, coords[1] + y]]
          fields << [coords[0] - x, coords[1] + y] if ins_basic_map[[coords[0] - x, coords[1] + y]]
          fields << [coords[0] - x, coords[1] - y] if ins_basic_map[[coords[0] - x, coords[1] - y]]
        end
        fields << [coords[0]    , coords[1] + x] if ins_basic_map[[coords[0]    , coords[1] + x]]
        fields << [coords[0]    , coords[1] - x] if ins_basic_map[[coords[0]    , coords[1] - x]]
        fields << [coords[0] + x, coords[1]    ] if ins_basic_map[[coords[0] + x, coords[1]    ]]
        fields << [coords[0] - x, coords[1]    ] if ins_basic_map[[coords[0] - x, coords[1]    ]]
      end
      break unless fields.empty?
      n+=1
    }

    fields.each do |field|
      path = find_path field
      unless path.nil?
        if path.size > 0
          puts Game.log :debug,"Found accessible field #{field}."
          return  field
        end
      end
    end
    fields[0]
  end
  #
  # #####################
  ## File with data:   ##
  ## 0. id
  ## 1. name           ##
  ## 2. collisions     ##
  ## 3. size            ##
  ## 4. gateways         ##
  ## 5. basic map          ##
  ## 6. empty map            ##
  ## 7. unseen fields           ##
  ## 8. amount of accessible fields ##
  ## 9. time of last access to file ##
  # #########################
  #
  def method_missing(m, *args)
    case m.to_s
      when 'id'
        return get_line 0
      when 'name'
        return get_line 1
      when 'collisions'
        return get_line 2
      when 'size'
        return get_line 3
      when 'gateways'
        return get_line 4
      when 'basic_map'
        # map with npcs
        #y = get_line 4
        ## JSON.parse return hash which has strings as keys. We saved it as an arrays, to lets undo this.
        #y.keys.each { |k| y[JSON.parse(k, :quirks_mode => true)] = y[k]; y.delete(k)}
        #return y
        return @basic_map_instance.dup
      when 'empty_map'
        # map without npcs
        #y = get_line 5
        ## JSON.parse return hash which has strings as keys. We saved it as an arrays, to lets undo this.
        #y.keys.each { |k| y[JSON.parse(k, :quirks_mode => true)] = y[k]; y.delete(k)}
        #return y
        return @empty_map_instance.dup
      when 'unseen_fields'
        # This method return only fields which are accessible by a hero.
        y = get_line 7
        ## JSON.parse return hash which has strings as keys. We saved it as an arrays, to lets undo this.
        y.keys.each { |k| y[JSON.parse(k, :quirks_mode => true)] = y[k]; y.delete(k)}
        return y
      when 'amount_of_accessible_fields'
        return get_line 8
      when 'last_save_time'
        tt = get_line 9
        require time
        return Time.parse tt
      else
        puts Game.log :warning,"Unknown method call: #{m}."
        super
    end
  end

  private
  def get_line(n)
    file = File.readlines("#{Game::MAIN_DIR}Data/MapData/#{@filename}")
    line = file[n]
    # save current time to file
    file[9] = Time.now.to_json
    refresh_data file.join if rand(4) == 0
    JSON.parse line, :quirks_mode => true
  end
end

