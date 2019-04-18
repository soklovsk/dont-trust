class AntiBot
  require_relative '../game'
  extend Game

  def bypass_images_anti_bot(driver)
    if driver.find_elements(class: 'ansRound')[0]
      elem = driver.find_elements(class: 'ansRound')[0]
      if elem.displayed?
        elements = driver.find_elements(class: 'unit')
        ele = elements[0] # each element has the same image which contains all pictures.
        data = ele.attribute :style # example of +:style+ "  left: 1608px; top: 70px; z-index: 14;
        #                     background-image: url(\"http://legion.margonem.pl/obrazki/npc/tmp/132_1497783022tvynsq.gif\");
        #               width: 80px; height: 90px;"  "
        #
        # url("/obrazki/npc/tmp/118_sun_1524767916lssbev.gif")
        url = /obrazki.*?\.gif/.match(data) # +url+ contains pure website address.
        filename = nil
        if url.nil?
          puts Game.log :debug,"Couldn't find url."
        else
          url = driver.current_url + url[0] # url contains only part of actual url
          puts Game.log :debug, "Found image: #{url}."
          filename = url.split('/')[-1]
        end
        begin
          require 'open-uri'
          Game.save_data filename, open(url).read, 'MargoBot/AntiBot/'
        rescue # 404 not found error

         puts Game.log :debug, "Something wen't wrong while getting image."
         puts Game.log :debug, "Url: #{url}"
         return false
        end
        # calling function which determines which images are identical (reminder: the image (url) contains 12 smaller images. We need to pick 2 the same of them.)
        indexes = find_identical_images filename
        sleep(rand(200)/100) # sleeping for 0-2000 ms
        elements[indexes[0]].click
        sleep(rand(300)/1000 + 0.2) # sleeping for 200-400 ms
        elements[indexes[1]].click
        sleep 0.5
        puts Game.log :debug, "Images anti-bot bypassed."
        # deleting file containing image.
        File.delete "#{Game::MAIN_DIR}MargoBot/AntiBot/#{filename}"
        true
      end
    end
  end
  private
  def find_identical_images(image)
    # input: file which contains 12 images (generated while bypassing image anti-bot (used on 'Siberia' world for example))
    # output: indexes of identical images.
    require 'mini_magick'
    images = []
    12.times do |n|
      images << MiniMagick::Image.open("#{Game::MAIN_DIR}MargoBot/AntiBot/#{image}").crop("32x32+#{n*32}+0")
    end
    images.each_with_index do |img, index|
      images.each_with_index do |img2, index2|
        if index!=index2 and img==img2
          puts Game.log :debug, "Found solution. Images #{index} and #{index2} are identical."
          return [index, index2]
        end
      end
    end
  end
end