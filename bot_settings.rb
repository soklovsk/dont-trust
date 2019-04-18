class BotSettings
  require 'json'
  require_relative 'game'
  extend Game
  attr_accessor :status, :bot_obj, :hero_obj, :last_perform, :priority # status is set to false when, since some causes, bot shouldn't use this profile any more., e.g. hero has no more potions and low hp.
  attr_reader :filename, :intention, :loot_filter
  def initialize(options = {})
    default = {nick: '', intention: nil, npc_name: '', value_to_filter: 0, player_reaction: false, wait: false,
               loot_filter: [:unique, :heroic, :legendary, :dragon_runes],time_to_wait: 260, sequence_file: nil, lvl_range: nil,
               time_to_play: 600, end_time: Time.now + 60*60*48, default_map: nil, default_coords: nil, max_group: 3}
    options = default.merge! options
    # will save data to file, don't waste memory.
    require 'securerandom'
    @filename = SecureRandom.hex 15 # 30 char long name
    data = [Time.now.to_json, options[:nick].to_json, options[:npc_name].to_json, options[:value_to_filter].to_json, options[:player_reaction].to_json,
            options[:wait].to_json, options[:time_to_wait].to_json, options[:sequence_file].to_json, options[:lvl_range].to_json,
            options[:time_to_play].to_json, options[:end_time].to_json, options[:default_map].to_json, options[:default_coords].to_json,
            options[:max_group].to_json]
    @intention = options[:intention]
    @loot_filter = options[:loot_filter]
    Game.save_data(@filename, data, "Data/Sets/")
    puts Game.log :debug,"Bot profile #{@filename} has been set up."
  end
  #
  # File schema:
  # line    data
  # --------------
  #   0.    start_time
  #   1.    nick
  #   2.    npc_name
  #   3.    value_to_filter
  #   4.    player_reaction
  #   5.    wait
  #   6.    time_to_wait
  #   7.    sequence_file
  #   8.    lvl_range
  #   9.    time_to_play
  #   10.   end_time
  #   11.   default_map
  #   12.   default_coords
  #   13.   max_group
  #
  def method_missing(m, *args)
    case m.to_s
      when 'start_time'
        string = get_line 0
        require 'time'
        return Time.parse string
      when 'hero'
        return @hero_obj
      when 'name', 'nick'
        return get_line 1
      when 'npc_name'
        return get_line 2
      when 'value_to_filter'
        return get_line 3
      when 'player_reaction'
        return get_line 4
      when 'wait'
        return get_line 5
      when 'time_to_wait'
        return get_line 6
      when 'sequence_file'
        return get_line 7
      when 'lvl_range'
        return get_line 8
      when 'time_to_play'
        return get_line 9
      when 'end_time'
        string = get_line 10
        require 'time'
        return Time.parse string
      when 'default_map'
        return get_line 11
      when 'default_coords'
        return get_line 12
      when 'max_group'
        return get_line 13
      else
        super
    end
  end

  private
  def get_line(n)
    line = File.readlines("#{Game::MAIN_DIR}Data/Sets/#{@filename}")[n]
    JSON.parse line, :quirks_mode => true
  end
end
