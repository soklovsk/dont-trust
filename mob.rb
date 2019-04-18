class Mob
  attr_accessor :id, :spawn_time, :kill_time, :name, :coords, :size, :lvl, :type, :group_size
  def initialize(id, driver)
    @driver = driver
    stt = Time.now
    id = id.to_s
    unless /npc/.match(id)
      id = "npc#{id}"
    end
    @id = id # id of the mob.
    @spawn_time = Time.now
    number_id = /\d+/.match(@id)[0]
    js_mob_obj = @driver.script("return g.npc[#{number_id}]")
    if js_mob_obj.nil?
      puts Game.log :warning,"Wrong id given or mob was killed already. ID: #{@id}."
      return nil
    end
    @coords = [js_mob_obj['x'], js_mob_obj['y']]
    @name = js_mob_obj['nick']
    @lvl = js_mob_obj['lvl']
    @lvl = -1 if @lvl == 0
    begin
      @size = driver_element.size
    rescue
      puts Game.log :error,'Mob has disappeared.'
      return nil
    end

    @group_size = get_group_size
    require 'json'
    npcs = JSON.parse File.read "#{Game::MAIN_DIR}MargoBot/GameFiles/NPCS/NPCS_LIST"
    if npcs.include? name
      @type = :npc
    elsif @driver.script("return g.npc[#{id.delete('npc').to_i}].type") != 0
      @type = :mob
    else
      @type = :npc
    end
    puts Game.log :debug,"#{@type} #{@name} (coords: #{@coords}, id: #{@id}), group size #{@group_size} created in #{Time.now - stt}s."
  end
  def real?
    begin
      elem = driver_element
      unless elem
        return false
      end # driver element returns false, when there's no this element.
      data = driver_element.attribute(:style) # example of +:style+ "  left: 1608px; top: 70px; z-index: 14;
      #                     background-image: url(\"http://legion.margonem.pl/obrazki/npc/tmp/132_1497783022tvynsq.gif\");
      #                     width: 80px; height: 90px;"  "

      url = /http:.*?\.gif/.match(data) # +url+ contains pure website address.
      if url.nil?
        return false
      end
      require 'open-uri'
      image_data = nil # it'll store image as a text.
      begin
        open(url[0]) { |f|
          image_data = f.read
        } # save image code to the image_data variable
      rescue # 404 not found error
        return false
      end
      length = image_data.to_s.squeeze.length
      puts Game.log :debug,"Size of image representing mob: #{length}"
      # if gif is blank - actually mob didn't spawn, so return false (it's not real.)
      if length < 500 # after deleting repeatable chars from string, when it's empty image, left less than 500 characters. (npc14099 - 423)
        # todo: check length of image at first kill (there are smaller mobs sometimes) and then check if later lengths are equal.
        puts Game.log :debug,'Ghost mob.'
        false # it's not the real mob - return false.
      else
        puts Game.log :debug,'Real mob.'
        true # it's real mob - return true.
      end
    rescue => error
      Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      false
    end
  end  # There are sometimes bugs which symptom is invisible mob which can't be attacked and disappears after refreshing.
  # To avoid errors caused by impossibility of clicking 'autobattleButton' and 'battleclose' (because battle won't start), check if spawned mob is actually the real one.
  def driver_element
    @driver.find_elements(id: @id)[0]
  end # will try to find element for 10 seconds. After that, it'll refresh page, try again and after that return false.
  private
  def get_group_size
    # each npc has .grp key in db in game.
    # when .grp is equal 0, then mob is without group
    # else, the .grp == n means that mob is in group number 'n', to determine how big is the group, we need to find another mobs with this .grp number.
    group_number = @driver.script "return g.npc[#{@id.delete('npc').to_i}].grp"
    return 1 if group_number == 0 # one mob in group
    @driver.script("{var npc_keys = Object.keys(g.npc); var counter = 0; npc_keys.forEach(function(id) {
                                  if(g.npc[id].grp == #{group_number}) { counter++;}}); return counter;}").to_i
  end
end