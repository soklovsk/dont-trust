## * * * * * * * * * * * * * * * * * * * * *
##
## This class is used for managing bots.
## Each objects is another account.
## With this class you can manage several accounts at the same time.
##
## * * * * * * * * * * * * * * * * * * * * *
class BotManager
  require_relative 'game'
  extend Game

  require          'fileutils'
  require_relative 'margobot'
  require_relative 'bot_settings'
  require_relative 'local_driver'
  require_relative 'scripts/script_manager'
  attr_reader   :username, :license, :dir
  attr_accessor :current_set, :sets, :driver

  def initialize(key, username, sets = [])
    check_access_key key
    sets = set_priorities sets
    init_attrs username, sets

    @dir = "Data/#{@username}"
    FileUtils::mkdir_p "#{Game::MAIN_DIR}#{@dir}" unless Dir.exist? "#{Game::MAIN_DIR}#{@dir}"
    if @license == :script
      puts Game.log :info, "Using scripts. Bot structure can be used only with known scripts."
      # Names of all scripts of "type 2" which can be used are stored in scripts/known_scripts.json file.
      require 'json'
      known_scripts = JSON.parse File.read("#{Game::MAIN_DIR}MargoBot/scripts/known_scripts.json")
      if known_scripts.include? username
        puts Game.log :info,"Using script #{username}."
      else
        puts Game.log :fatal, "Tried to run unknown script! #{username}."
        exit!
      end
      return
    end
    unless File.exist? "#{Game::MAIN_DIR}#{@dir}/Kills list"
      Game.save_data 'Kills list', "List of all kills for #{username}\n", "#{@dir}/"
    end

  end
  def handle_account(login, password = nil, start_time = Time.now, end_time = Time.now + 60*60*6, driver = nil)
    # license check-up
    raise StandardError unless @license
    puts Game.log :warn, 'End time was set improperly.' if Time.now > end_time or end_time < start_time
    return false if Time.now > end_time
    puts Game.log :info,"Start time #{start_time}."
    sleep(0.5) until Time.now >= start_time
    @driver = LocalDriver.new self, driver

    puts Game.log :debug,'Driver is ready.'
    mirek = MargoBot.new @driver
    mirek.bot_manager = self
    puts Game.log :debug,'Created MargoBot obj.'
    #
    # Start and end times
    puts Game.log :info,"Will play until #{end_time}" if end_time
    # logging in
    @driver.log_in(login, password)
    #
    # bot thread
    bot_thread = Thread.new {
      loop {
        begin
          start_time = Time.now
          nxs = next_set
          if nxs.nil?
            @driver.get 'https://www.margonem.pl'
            sleep 60
          else
            play = Thread.new{ mirek.use nxs, available_time }
            stop = Thread.new{
              puts Game.log :debug,'Control thread joined.'
              while play.status
                sleep(1)
                play.exit if Time.now >= start_time + nxs.time_to_play
              end
              puts Game.log :debug,'Time to play ended.' if Time.now >= start_time + nxs.time_to_play
            }
            play.join
            (stop.join if nxs.intention == :exp) if nxs.is_a? BotSettings
            (nxs.last_perform = Time.now if nxs.intention == :exp) if nxs.is_a? BotSettings
          end
        rescue StandardError => error
          Game.save_data("Data (error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
        end
        sleep 5
      } # loop
    }
    #
    # control thread
    check_thread = Thread.new {
      while bot_thread.status
        sleep(1)
        if Time.now >= end_time
          puts "End time was set to #{end_time}. Stopping bot..."
          bot_thread.exit
          sleep(5)
        a  puts Game.log :debug,"bot_thread status: #{bot_thread.status}."
          @driver.quit
          system("rm #{Game::MAIN_DIR + @dir}/Sets/*")
          exit
        end
      end
    }
    begin
      bot_thread.join
      check_thread.join if end_time
    rescue StandardError => error
      puts Game.log :fatal,"Not rescued error got to BotManager class. Returning false."
      @driver.quit
      Game.save_data("Data (fatal error) #{Time.now.strftime('%F %T')}", [error.message, error.backtrace.inspect], 'Errors/Error Data/') # saving data about error
      return false
    end

  end

  private
  def next_set
    # sets priority:
    #     1. :search
    #     2. :exp
    #     3. :elite
    #
    # checking if there is set not performed yet
    puts Game.log :debug,'Pointing next set.'
    @sets.map! do |set|
      if set.end_time < Time.now
        puts Game.log :info,"End time of set with intention #{set.intention} (#{set.name}) had been set to #{set.end_time}. Won't use it anymore."
      else
        set
      end
    end
    @sets.compact!
    @sets.each do |set|
      return set if set.last_perform == nil and not set.intention == :elite
    end
    puts Game.log :debug,'All :search and :exp sets were performed.'
    #
    # Now lets check if there is set with priority 1 which should be used
    @sets.each do |set|
      return set if set.priority == 1 and set.last_perform + set.time_to_wait < Time.now
    end
    puts Game.log :debug,'There are no sets with intention :search which are ready to be performed.'
    #
    # Now lets check if there is set with priority 2 which should be used
    @sets.each do |set|
      return set if set.priority == 2 and set.last_perform + set.time_to_wait < Time.now
    end
    puts Game.log :debug,'There are no sets with intention :exp which are ready to be performed.'
    #
    # Lets check if there are sets with priority 3, if there are, return all of this.
    elites = []
    @sets.each do |set|
      elites << set if set.priority == 3
    end
    puts Game.log :debug,"Found #{elites.size} sets with intention :elite"
    return elites unless elites.empty?
    #
    # if got here - there are no sets available for this moment.
    nil
  end
  def init_attrs(username, sets)
    @username = username
    @sets = sets
  end
  def set_priorities(sets)
    sets.each do |set|
      set.priority = 1 if set.intention == :search
      set.priority = 2 if set.intention == :exp
      set.priority = 3 if set.intention == :elite
    end
    sets.sort_by! {|set| set.priority}
  end
  def available_time
    # This method return how much we have time for next action (exp/search)
    remaining_times = []
    @sets.each do |set|
      if set.intention == :search or set.intention == :exp
        if set.last_perform
          time = set.time_to_wait - (Time.now - set.last_perform)
          #
          # if time is a negative number it means that it should be performed already and we have a delay
          return 0 if time <= 0
          remaining_times << time
        else
          # there is a set with high priority which hasn't been performed already.
          # so there is no time for actions with lower priority
          return 0
        end
      end
    end
    #
    # if we've got here it means that we still have some time.
    # how much? Lets check
    remaining_times.compact!
    #
    # returning infinity if array is empty (using only :elite)
    return -1 if remaining_times[0].nil?
    remaining_times.sort_by! {|time| time}
    remaining_times[0]
  end
  def check_access_key(key)
    # will be soon
    mode = key
    @license = :admin if mode == :admin
    @license = :tester if mode == :tester
    @license = :user if mode == :user
    @license = :trial if mode == :trial
    @license = :demo if mode == :demo
    @license = :script if mode == :script
    raise SecurityError, 'Provided access key is invalid.' unless @license
    puts Game.log :info, "Using bot with privileges of #{mode}."
    true
  end


end