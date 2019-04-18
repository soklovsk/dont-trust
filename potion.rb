require_relative 'item'

class Potion

  attr_reader :full_healing, :item_object, :hero, :heal_points # item object is object in Item class corresponding to self. It's given in element.
  def initialize(element)
    unless element.is_a?(Item)
      puts Game.log :warning,"Wrong argument type. Expected Item. Given: #{element.class}."
      return
    end
    @item_object = element
    @hero = item_object.hero
    if /Pełne leczenie/.match(element.description)
      @full_healing = true
    else
      @full_healing = false
    end
    refresh
  end

  def use(to_heal = nil)
    to_heal = @hero.max_health - @hero.health unless to_heal
    remove = false
    if @full_healing
      if heal_points < to_heal
        puts Game.log :debug,"To heal: #{to_heal}. Used potion has just #{heal_points}. Using and removing it."
        remove = true
      end
    else
      if uses == 1
        puts Game.log :debug,'Item has the last use. Using and removing it.'
        remove = true
      end
    end
    bag = @item_object.bag
    if bag.is_a?(Bag)
      bag.item_object.driver_element.click
      sleep(0.3)
    else
      puts Game.log :warning,"@hero.driver.find_bag returned wrong argument type. Required class: Item, given class: #{bag.class}"
      puts bag
    end
    # bag is changed, now just use item.
    sleep(0.1)
    begin
      @hero.driver.action.drag_and_drop(@item_object.driver_element, @hero.driver.find_element(id: 'b_pvp')).perform
    rescue
      return false
    end
    sleep(0.2)
    if remove
      @hero.remove_item(@item_object.item_id)
    end
    refresh
  end # perform action which uses the potion
  def refresh
    @item_object.set_description # refresh description
    if /ełne leczenie/.match(@item_object.description)
      foo = /ozostało \d+\.?\d+?k?/.match(@item_object.description)[0].gsub('ozostało ', '').gsub(' ', '')
      if foo.end_with?('k')
        @heal_points = foo.chomp('k').to_f*1000
      else
        @heal_points = foo.to_i
      end # setting up @healing_points
    else
      begin
        x = /eczy \d+/.match(@item_object.description)[0].gsub('eczy ', '').to_i
        puts Game.log :debug,"Item: #{@item_object.name} (id: #{@item_object.item_id}), healing points: #{x}."
        @heal_points = x
      rescue => error
        puts Game.log :error,'Something went wrong while looking for healing_points.'
        Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect, @item_object.description], 'Errors/Error Data/')
        # check if the item exists.
        foo = @hero.driver.find_elements(id: @item_object.item_id)
        if foo[0].nil?
          puts Game.log :warning,"Item #{@item_object.item_id} doesn't exist."
          @hero.remove_item(@item_object.item_id)
        end
        0
      end
    end
  end # returns how much points can this potion heal.
  def uses
    @item_object.set_description # refresh description
    if /Pełne leczenie/.match(@item_object.description)
      1
    else
      match = /lość:? \d+/.match(@item_object.description)
      if match.nil?
        1
      else
        match[0].gsub('lość: ', '').to_i
      end
    end
  end # returns number of uses of this potion.
end
