class ChatMonitor
  #
  # The idea is that every hero has it's own ChatMonitor object
  # The messages are saved to different file for each hero.
  #
  require 'json'
  extend Game

  attr_reader :hero, :file_name

  def initialize(hero)
    @hero = hero
    @status = :enabled
    begin
      @file_name = "#{hero.driver.start_time.strftime("%F: %T")} #{hero.nick}"
      Game.save_data(@file_name, '[]', "#{@hero.driver.bot_manager.dir}/Chat/") unless File.exist? "#{@hero.driver.bot_manager.dir}/Chat/#{@file_name}"
    rescue
      puts Game.log :warning,"Unable to create some links. Chat Monitor won't work."
      @status = :disabled
    end
  end

  def check_and_save
    return false if @status == :disabled
    new_messages = get_all_displayed_messages - get_saved_messages
    return false if new_messages.empty?
    puts Game.log :info,"#{new_messages.size} new messages: \n#{new_messages}"
    messages = get_saved_messages + new_messages
    messages = (messages.sort_by {|m| m['time']}).to_json
    File.delete("#{Game::MAIN_DIR}#{@hero.driver.bot_manager.dir}/Chat/#{@file_name}")

    Game.save_data("#{@hero.driver.start_time.strftime("%F: %T")} #{@hero.nick}", messages, "#{@hero.driver.bot_manager.dir}/Chat/")
  end
  def get_all_displayed_messages
    return false if @status == :disabled
    # this method don't get system messages.
    # it will return only messages which were written by a players.
    #
    # messages written by a players divide into 2 groups.
    # after some time class of elements if changed from empty to 'abs'
    # we'll get both types to mess ary.
    mess = [] # messages :)
    #
    mess << @hero.driver.find_elements(css: "[class=\"\"]") # the newest messages
    mess << @hero.driver.find_elements(css: "[class=\"abs\"]") # older messages
    # an example of a message:
    # <div class="abs"><span c_nick="Adam ostry" class="chnick" tip="10:47:19">«Adam ostry» </span>ile będziesz tu kwitł :D</div>
    #
    # mess.flatten! = ary with driver elements
    #
    mess.flatten!
    #
    # messages will store messages to return
    # messages = [{message}, {message},...]
    #
    messages = []
    #
    # message scaffolding
    # It's just an example:
    #
    # message = {:time => Time, :nick => '', :message => ''}
    #
    mess.each do |m|
      #
      html = m.attribute(:innerHTML)
      # example of +html+:
      #   "<span c_nick=\"Opryskliwie\" class=\"chnick\" tip=\"10:53:37\">«Opryskliwie» </span>oo liszki hahaha"
      #
      # Time:
      #
      time = html.match(/tip="\d+:\d+:\d+/)
      if time
        time = time[0].delete("\"A-Za-z=")
        t = time.split(":")
        time = Time.new(Time.now.year, Time.now.month, Time.now.day, t[0],t[1],t[2])
        #
        # In some special situations we will analyze messages from a day before.
        #
        if time > Time.now
          time = time - 3600*24
        end
        #
        # Nick:
        #
        nick = html.match(/c_nick=".*?"/)[0]
        nick.gsub!('c_nick="', '')
        nick[-1] = '' # deleting last char ("\"")
        nick
        #
        # Message
        #
        mes = html.match(/<\/span>.*/)[0]
        mes.gsub!('</span>', '')
        mes
        #
        # Creating hash with data about message
        # I know that strings as a hash keys sucks, but JSON.parse returns keys as a string, even though it was saved as symbol
        # It makes impossible to compare these hashes later
        # Actually I could write method to convert string keys to symbol keys, but operating on string keys is just simpler (and faster)
        #
        message = {'time' => time.strftime('%F %T').to_s, 'nick' => nick, 'message' => mes}
        #
        # Saving it to array with all visible messages
        #
        messages << message
      end
    end # end of each
    # Returning array sorted by the time (oldest messages first.)
    messages.sort_by {|m| m['time']}
    #
  end
  def get_saved_messages
    return false if @status == :disabled
    if File.exist?("#{Game::MAIN_DIR}#{@hero.driver.bot_manager.dir}/Chat/#{@file_name}")
      file = File.read("#{Game::MAIN_DIR}#{@hero.driver.bot_manager.dir}/Chat/#{@file_name}")
      if file.size > 0
        JSON.parse(file, :quirks_mode => true)
      else
        []
      end
    else
      []
    end
  end
end