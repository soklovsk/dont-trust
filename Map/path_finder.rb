##
## This class is used to find paths as well on maps as well paths through the world.
##
##
class PathFinder
  require_relative '../game'
  extend Game

  # below method return array with sequence of maps to go through to get to given map.
  def find_way_through_world(current_map = [], finish_map = :town, without = [])
    #
    #   when finish_map is :town, the destination will be one of the towns: Ithan, Torneg, Karka-han, Werbin, Eder, Nithal, Tuzmer or Thuzal.
    #   (first town (Ithan) has the highest priority - it means that we'll try to find path to that town unless successful, then next etc.)
    #
    #   when current_map is array, caller want to receive shortest path to finish map from one of the maps given in array.
    #
    # Logic moved to find_maps_path private method.
    towns = %w[Ithan Torneg Karka-han Werbin Eder Nithal Tuzmer Thuzal]
    finish_map = towns if finish_map == :town
    paths = []
    current_map = [current_map] unless current_map.is_a? Array
    finish_map  = [finish_map]  unless finish_map.is_a? Array
    without = [without] unless without.is_a? Array
    puts Game.log :debug,"Will search closest path from #{current_map} to #{finish_map}"
    current_map.each do |start|
      finish_map.each do |finish|
        paths << find_maps_path(start, finish, without)
      end
    end
    paths.map! {|p| p if p}
    paths.compact!
    puts Game.log :debug, "Found #{paths.size} paths."
    paths.sort_by! {|p| p.size}
    puts Game.log :debug,"Returning the shortest path #{paths[0]}."
    paths[0]
  end

  private
  def find_maps_path(start, finish_map, without = [])
    require 'json'
    #####
    # # # start - start map name/id (string/integer)
    # # # finish - last map name/id (string/integer)
    # # # without - maps which are forbidden to use in path (array of strings/integers)
    #####
    # # #  maps with gateways are saved in redis db. $redis is used to access it.
    #####
    # arguments check-up
    # Notice that it is safer to call this function with map ids not map names, since when there are several maps with the same name, the first one will be used.
    finish = finish_map
    finish = JSON.parse($redis.get(finish_map))[0] if finish_map.is_a? String
    start  = JSON.parse($redis.get( start))[0] if  start.is_a? String
    without.map! do |m|
      if m.is_a? String
        JSON.parse($redis.get(m))[0]
      else
        m
      end
    end
    puts Game.log :debug, "Searching path from #{start} to #{finish} without #{without}"
    puts Game.log :warning,"Doesn't have #{finish_map} in database. Go there and add it :-)." if finish.nil?
    #
    return false if finish.nil? or start.nil?
    begin
      return [finish] if JSON.parse($redis.get(start))[1].include? finish # when the maps are neighbours.
    rescue
      return nil
    end
    ##
    ## Algorithm will 'visit' every map which can be accessed from start, and mark those as '1' in +maps_with_number+ hash.
    ## The maps will be added to stack, and algorithm will repeat that procedure for stack[0], then shift it until stack will include finish.
    maps_with_number = {start => 0}
    ##
    stack = [start]
    stop = false
    until stop
      puts Game.log :debug, "stack empty" if stack.size == 0
      puts Game.log :debug, "#{stack}"
      break if stack.size == 0
      v = stack[0]
      stack.shift
      # getting all map which can be accessed from current +v+ map.
      neighbours = $redis.get(v) # its nested array: [id, [gateways]]
      if neighbours # if neighbours was nil, it means that this map is not in db as key, so we should skip this one.
        neighbours = JSON.parse(neighbours)[1] # neighbours[0] = map_id, neighbours[1] = gateways (see above)
        # actually we're interested only in maps we didn't 'visit'.
        neighbours -= maps_with_number.keys
        puts Game.log :debug, "neighbours: #{neighbours}, maps..: #{maps_with_number}"
        neighbours.each do |mp|
          stack<<mp
          #
          # incrementation of counter (map with counter +2 is 2 maps away)
          maps_with_number[mp] = maps_with_number[v] + 1
          if $redis.get mp
            if JSON.parse($redis.get(mp))[1].include? finish
              stop = true
              puts Game.log :debug,"Found finish"
              maps_with_number[finish] = maps_with_number[v] + 2
              break
            end
          end
          #
        end
      end
    end
    puts Game.log :debug,'Path exists.'
    puts Game.log :debug,"maps with number: #{maps_with_number}."
    #
    # Okay, so the maps we're interested are marked.
    # To reach finish we need to get its counter (n), then find map with n-1, then n-2... until we reach counter == 0
    puts Game.log :debug,"#{maps_with_number}" unless maps_with_number.keys.include? finish
    return false unless maps_with_number.keys.include? finish
    path = [finish]
    #
    until path.include?(start)
      #
      begin
        puts Game.log :debug,"I'm checking #{path[0]}"
        JSON.parse($redis.get(path[0]))[1].each do |neighbour|
          if maps_with_number.keys.include?(neighbour) and $redis.get(neighbour)
            puts Game.log :debug,neighbour
            if maps_with_number[neighbour] + 1 == maps_with_number[path[0]] and not without.include? neighbour
              # checking if we can go somewhere further from neighbour (sometimes there are bugs in db which causes that neighbour seems to be ok, but we can't go from it to any marked in previous loop map.)
              # so we just check if neighbour's neighbours are marked in maps_with_number (generated in previous loop)
              JSON.parse($redis.get(neighbour))[1].each do |next_neigh|
                if maps_with_number.keys.include? next_neigh
                  path.unshift neighbour
                  break
                end
              end
            end
          end
        end
      rescue => error
        puts [error.message, error.backtrace.inspect]
        puts Game.log :error, "Couldn't get data from db for map #{path[0]}."
      end
    end
    #
    path.shift # start map doesn't have to be in returned array
    path
  end
end