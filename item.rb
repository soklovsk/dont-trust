# It's very important to create items using add_item method in LocalDriver
# Every item belonging to player has to be created this way.
# Otherwise, it won't be on list of player's items and won't be used, or included in stats.

require 'selenium-webdriver'
class Item
  attr_reader :name, :item_id, :id, :loot_time, :accepted, :healing_object, :description
  attr_accessor :bag, :hero
  # +type+ contains items groups: :arrows, :dragon_runes, :teleportation, :healing
  # Items are not divided only into @rarity group, but more.
  # it's used to filter (sometimes player want to save healing potions, or arrows and he can choose what want to see in equipment.)
  # Also, bot can sometimes turn on saving healing items, when hero don't have anymore, in order to work longer.

  # driver_element after refreshing page (and not refreshing itself) is useless and can cause errors (element not attached to DOM).
  def initialize(hero, element, minimal_value = 0, loot = true, loot_filter = [:unique, :heroic, :legendary, :dragon_runes])
    puts Game.log :debug,"Creating item #{element}."
    @hero = hero
    raise ArgumentError, 'Item has to belong to specific hero.' if @hero.class != Hero
    unless element.is_a?(Selenium::WebDriver::Element) or element.is_a? String
      puts Game.log :warning,"Wrong argument type given. Expected Selenium::WebDriver::Element or String, given #{element.class}."
      return false
    end
    if loot
      @loot_time = Time.now
    else
      @loot_time = nil
    end
    if element.is_a? Selenium::WebDriver::Element
      @item_id = element.attribute(:id)
    elsif element.is_a? String
      foo = String.new
      foo = 'item' + element unless element[0] == 'i'
      @item_id = foo
    end
    @id = @item_id.delete('item')

    @description = set_description.to_s
    begin
      puts Game.log :debug,@id
      @name = @hero.driver.script "return g.item[#{@id}].name"
    rescue => error
      puts Game.log :error,error
      return nil
    end
    puts Game.log :debug,'Description was found.'
    if type == :healing
      require_relative 'potion'
      @healing_object = Potion.new(self)
    end
    if loot
      accepted?(minimal_value, loot_filter) # setting up @accepted value
    else
      @accepted = nil
    end
    puts Game.log :debug,"Created new item! #{@name} (#{rarity}) worth #{value} pieces of gold."
    # using item if it adds gold
    self
  end
  def dragon_runes
    if @name == 'Smocza Runa'
      dragon_runes = /Dodaje \d+/.match(@description)[0].delete('Dodaje ').to_i
      # an example of Dragon Runes description:  <b>Smocza Runa</b><b class=unique>* unikat *</b>Typ:  Konsumpcyjne
      #                                       Dodaje 375 Smoczych Run<br>Związany z właścicielem<br>Wartość: 375">
    else
      dragon_runes = 0
    end
    dragon_runes
  end
  def rarity
    if /unikat/.match(@description)
      :unique # unique item
    elsif /heroiczny/.match(@description)
      :heroic # heroic item
    elsif /legendarny/.match(@description)
      :legendary # legendary item
    else
      :common # common item
    end # @rarity
  end
  def type
    if /Leczy \d+/.match(@description) or /Pełne leczenie/.match(@description)
      return :healing
    end
    if /Typ:Strzały/.match(@description.delete(' '))
      return :arrows
    end
    if /teleport/.match(@description.downcase)
      return :teleportation
    end
    if @name == 'Smocza Runa'
      return :dragon_runes
    end
    if /Typ:Torby/.match(@description.delete(' '))
      return :bag
    end
    nil
  end
  def amount_of_added_gold
    if /oto \+\d+/.match(@description)
      return /oto \+\d+/.match(@description)[0].delete("\s[A-Za-z]+").to_i
    end
    0
  end
  def value
    @hero.driver.script "return g.item[#{@id}].pr"
  end # returns value of the item

  def driver_element
    elements = @hero.driver.find_elements(id: @item_id)
    elements.map do |x|
      if x.displayed?
        x
      else
        false
      end
    end
    element = elements.compact[0]
    if element.nil?
      nil
    else
      element
    end
  end # after page refreshment, driver element becomes out of date. Method returns false, if haven't found element, and element if it have found it.
  def set_description
    #   All this data is stored in +tip+: attribute which looks like:
    #      "  <b>Dobrej jakości magiczna zbroja</b><b class=unique>* unikat *</b>Typ:  Zbroje<br />Pancerz: 296<br>Odporność na truciznę +15%<br>
    #         Odporność na ogień +8%<br>Absorbuje do 1110 obrażeń fizycznych<br>Absorbuje do 814 obrażeń magicznych<br>Intelekt +62<br>
    #         Przywraca 191 punktów życia podczas walki<br>Mana +44<br>SA +0.6<br>Wiąże po założeniu<br>
    #         <b class=&quot;att&quot;>    # Wymagany poziom: 105</b><br><b class=&quot;att&quot;>Wymagana profesja:  Tropiciel</b>
    #         <br>Wartość: 102.16k" style="left: 33px; top: 0px;  "
    begin
      @hero.driver.script "return g.item[#{@id}].tip"
    rescue
      "Item #{@id} doesn't exist."
      @hero.remove_item(@item_id)
      nil
    end
  end # returns description of the item

  def use
    if @healing_object
      return @healing_object.use
    end
    if @bag.is_a?(Bag)
      @bag.item_object.driver_element.click
      sleep(0.2)
    else
      puts Game.log :warning,"@hero.driver.find_bag returned wrong argument type. Required class: Item, given class: #{@bag.class}"
    end
    # bag is changed, now just use item.
    sleep(0.1)
    @hero.driver.action.drag_and_drop(driver_element, @hero.driver.find_element(id: 'b_pvp')).perform
    sleep(0.1)
  end
  private

  def accepted?(minimal_value, loot_filter)
    if value == 0
      puts Game.log :debug,"Item #{@name} has no value!"
    end
    if type and loot_filter.include?(type)
      puts Game.log :info,"Accepting item #{@name} because loot_filter includes this group #{type}."
      @accepted = true
    elsif loot_filter.include?(rarity)
      puts Game.log :info,"Accepting item #{@name} because loot_filter includes this rarity #{rarity}."
      @accepted = true
    elsif amount_of_added_gold > 0
      puts Game.log :info,"Accepting item #{@name} because it adds #{amount_of_added_gold} gold."
      @accepted = true
    else
      if value >= minimal_value
        puts Game.log :info,"Accepting item #{@name} because it's worth more than minimal value #{minimal_value} gold."
        @accepted = true
      else
        puts Game.log :info,"Refusing item #{@name}."
        @accepted = false
      end
    end # end of if loot_filer...
  end # end of accepted
end