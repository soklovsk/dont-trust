module Game
  require 'redis'
  require 'logger'
  BOT_VERSION = '4.4.10'.freeze
  MAIN_DIR = (Dir.pwd.gsub(/\/MargoBot.*/, '') + '/')
  $garbage_collector_running = false
  $logger = Logger.new "#{MAIN_DIR}Logs/margobot.log", 20, 5 * 1024000 # 20 files, each 5 mb
  $logger.level = Logger::DEBUG
  $logger.progname = "MargoBot #{BOT_VERSION}"
  $redis = Redis.new

  def self.save_data(file, data, path = MAIN_DIR)
    require 'fileutils'
    # Checking for existence of directory.
    # Create if it doesn't exists
    if path != MAIN_DIR
      path = path[1..-1] if path[0] == '/'
      path += '/' if path[-1] != '/'
      unless File.exist?(MAIN_DIR + path)
        FileUtils::mkdir_p (MAIN_DIR + path)
      end
    end
    # Checking for existence of specified file and creating it if not

    unless File.exist?("#{MAIN_DIR + path}#{file}")
      File.new("#{MAIN_DIR + path}#{file}", "w")
      puts Game.log :debug,"Creating file: #{MAIN_DIR + path}#{file}"
    end
    #finally we can save data
    open("#{MAIN_DIR + path}#{file}", "a+") { |f|
      if data.is_a?(Array)
        data.each do |d|
          f << "#{d} \n"
        end
      else
        f << data
      end
    }
  end # saves data to file. If data is an array, every element is saved in new line.
  # method is used to save logs, errors etc. to files.
  # path format has to be like this: dir1/dir2/project/
  # file with extension!
  def self.log(level, message = '')
    unless [:unknown, :fatal, :error, :warn, :info, :debug].include? level
      message = level
      level = :debug
    end
    data = "#{caller[0].split('/')[-1]}: #{message}"
    begin
      $logger = Logger.new "#{MAIN_DIR}Logs/margobot.log", 20, 5 * 1024000  unless $logger # 20 files, each 5 mb
      case level
        when :fatal
          $logger.fatal data
        when :error
          $logger.error data
        when :warn
          $logger.warn data
        when :info
          $logger.info data
        when :debug
          $logger.debug data
        else
          $logger.unknown data
      end
    rescue
      "Logger error!"
    end
    data # return
  end # Log creates strings with messages used to real time log.
  # An example of returned string: "17:56:23.021 :  Chat Monitor: No new messages."

end