class Bag
  attr_reader :items, :size # items is an array with ALL items belonging to self bag
  attr_accessor :item_object, :hero # object of Item class.
  def initialize(item_object, all_items = nil, hero)
    @hero = hero
    @item_object = item_object
    set_size
    refresh(all_items) # importance of all_items is explained in refresh method.
  end

  def available_space
    inner_html = /id=\"bs\d\">\d+<\/small>/.match(@item_object.driver_element.attribute(:innerHTML))[0]
    # an example of innerHTML:
    # <small style=\"opacity: 0.5;\" id=\"bs1\">30</small><img dest=\"503605754\" src=\"/obrazki/itemy/bag/torba02.gif\">
    # There are 2 important information in +inner_html+:
    #     1. id="bs0" - it informs us that the bag is the first by the left. Every used bag has its own id, like bs0, bs1...
    #     2. The number inside (2) - its amount of free space. And in this method, this is what we're interested in.
    if inner_html.nil?
      puts Game.log :warning,"Can't find inner_html of #{@item_object} bag (#{@item_object.name})."
      return 0
    end
    space = inner_html.match(/>\d+</)[0].delete('><') # <small style="opacity: 0.5;" id="bs0">2</small> =>
    space.to_i
    # return amount of items which can be placed in this bag.
  end
  def refresh(all_items = nil)
    # erase @items and fill it again.
    @items = []
    @item_object.driver_element.click
    puts Game.log :debug,"Bag changed to #{@item_object.item_id}."
    sleep(0.2) # changing bag.
    if all_items.nil?
      all_items = @hero.all_items
    end # it's important, since when this method is called from Hero.initialize, then the @hero is nil.
    # However, after initializing new Hero object, the @hero is Hero object, so we won't need it anymore.
    # Concluding, all_items argument is used only when calling from Hero.initialize.
    number_i = 0
    all_items.each do |it|
      if @hero.driver.touch?('bagc', it.driver_element, 0, 0)
        @items << it # it is Item object.
        it.bag = self
        number_i += 1
      end
      if @size - available_space == number_i
        break
      end
    end
    puts Game.log :debug,"#{@items.size} items added to @items."
    @items
  end

  private
  def set_size
    foo = /\d+ przedm/.match(@item_object.description)
    @size = foo[0].match(/\d+/)[0].to_i
  end
end