###v.4.4.?:
######Added:
* 
######Changed:
*
######Fixed:
* Problems with logging in

###v.4.4.30:
######Added:
* new sequence file - oblo_seq
######Changed:
* adapted logging in to the new interface (NI)

####v.4.4.10:
######Changed:
* Added new field to stats file template and changed layout a little bit.

####v.4.4.00:
######Added:
* Bot is able to cross gateways which requires to click them and which may start a dialog.
* New option :without for PathFinder.find_way_through_world method which gives possibility to avoid using some maps when searching path.
* When during traveling the maps, the given gateway is unreachable, bot will try to find alternative path.
* sequence files (_seq) can contain map ids.
* current_map_id method for LocalDriver.
* Map.go_to_map can be called with id of map as argument.
* possibility to create exceptions. For example, when in order to move from map A to map B, hero has to go through map C (map A has gateway to map B, but it's inaccessible without crossing map C). There are a few exceptions in "Exceptions" dir, which can be used as a templates to create the new ones.
* new script to interpret the exceptions
* sequence file for "Swiety braciszek" hero. (braciszek_seq)
######Changed:
* Rewritten Game.log (each call has to specify log level now). 
* Restored old version of LocalDriver.fight? method since new version from 4.3.00 update caused driver lags.
* Randomized algorithm in Map.dijkstra (generated paths will differ).
* Changed organisation of redis db. Now, maps are saved with id as a key, so there will be no more bugs. Map names are also saved to db and it stores id of maps with that name. IMPORTANT: it's impossible to move data from previous databases. Unfortunately, old databases are not supported anymore, and new has to be created and filled again.
* arguments for find_maps_path in PathFinder can be map ids as well. Returned path will be array of map ids.
* gateways in Map class won't contain map names anymore. Map ids instead.
* Stats will be stored in one file for one mob (earlier: one file for one period of using bot) & 2 versions of each stats file - json and plain text.
######Fixed:
* fixed counting kills for stats.
######Removed:
* move_time method from Hero class (not used anywhere and no chances it would be).

####v.4.3.00:
######Added:
* AntiBot class which at this moment can be used to bypass anti-bot protection based on marking the same images.
######Changed:
* more bulletproof and faster checking if hero participates in battle (LocalDriver.fight?)
* basic_map and empty_map are stored as instance variables again (in order to find path quicker.)
* faster reaction on attacks while moving hero in Map.move_to_coords
######Fixed:
* bug in path_finder which caused impossibility of finding long paths.
* issues with wrongly set Hero.status
* bulletproofed using potion.
* rarely occurring bug which caused hero being impossible to attack mob when it is shadowed by another mob.
####v.4.2.00:
######Added:
* redis database storing maps and gateways
  - script to add new maps and gateways to that db
  - maps are added automatically
  - $redis is new global variable used to get/save data.
* new options for BotSettings: :default_map, :default_coords
  - if :default_map is set, bot will automatically (if will be able to find path) return to the map when will die or start from another place.
  - if :default_coords are set, bot will go to the coords on :default_map when coming back.
* Reaction on attacks while waiting for mob in Bot.attack_with_wait
* New option for BotSettings for :intention == :exp: :max_group
  - getting group size when creating Mob object.
  - while exp bot will attack groups up to max size (:max_group)  
* changing set after losing battle during exp.
######Fixed:
* changing Hero.map after losing battle
* problems with confusing mobs with npcs.
* hero heals/reacts on losing the battle when is attacked while moving.
* bug with exp on wrong map after losing the battle.
######Changed:
* way of splitting logs to files.
* find_path_through_world method in PathFinder has been completely rebuilt and now it uses maps_with_gateways file. 
######Known Issues:
* Slow work during exp on big maps.
* :travel mode in map sometimes does not work properly. It will be repaired in next update.
######Good to know:
* using redis in bot is tested now and it will take some updates before it will work well. Currently, bot won't set up the db. User has to do this manually. There is new file in GameFiles/MAPS, which contains about 200 maps with gateways. It should be manually added to redis. While working bot will update the db, however after the restart of the server data will be lost.

####v.4.1.10:
######Added:
* TP to/from Nithal.
######Fixed:
* bugs in travelling map in :exp mode.
 
####v.4.1.00:
######Added:
* new script for deleting temporary files
* Map objects save to file amount of accessible fields.
* End time has to be set for each BotSettings object.
######Changed:
* way of initializing BotSettings objects. Now it uses a hash as a default parameter, so creating new object is more convenient.
* access to temporary files in Map/Bot_Settings is more neatly.
* creating list of items is faster. It's not needed anymore to move hero.
######Fixed:
* crashes after travelling map during exp
* bugs on linux

####v.4.0.10:
######Fixed:
* fixed loot filter

####v.4.0.00:
######Added:
* Auto exp
* 'use' method in MargoBot.
* lvl_range option in BotSettings (used to set up :exp).
* visible_mobs method in Map class.
* fill_inaccessible_fields method in Map class. 
* Added saving lvl's for Mob objects.
* quick_mode for finding path. When it's enabled, the first found path will be returned when given coords are not accessible (i.e. path to mob)
* Selenium WebDriver can be given to bot_manager to use it as a @driver
* List of names of all npcs in game (in file NPCS_LIST)
* Determining if mob is an interactive npc while creating object.
* accessible_fields method added to Map class. Return fields which can be visited but hero haven't seen it yet.
* travel in Map class. (saving fields which haven't been seen yet)
######Changed:
* some logic moved from BotManager to MargoBot class.
* use and initialize_set are now the only public methods in MargoBot class.
* find_closest_accessible_field is called every time hero can't move to given field.
* classes are a little bit more independent so it's easier to test some functions, for example.
* BotSettings objects save data to file.
* Map objects store some data in files.
* all private methods in map are public now.
* starting driver after start time (lower precision although less bugs).
* way of printing time in logs.
######Upgraded:
* bulletproofed battle management
* LocalDriver.distance - arguments can be also coordinates.
* press_key times are now randomized a little bit.
* bulletproofed creating Mob objects.
######Fixed:
* Attacking mobs is way more fluent.
* Optimized healing
* need_healing? method fixed.
* quitting driver when stopping bot from BotManager.
* find_closest_accessible_field fixed.
* reacting on menu which sometimes shows while attacking mobs.
######Known issues:
* Some bugs may occur when using low level heroes (lower than about 25)
* Exp isn't fluent enough.
* Some bugs may occur while exping.

####v.3.4.11:
######Fixed:
* deleting old logs at start.
######Changed:
* bot logs in after start_time (old: was logging in after opening driver).

####v.3.4.10:
######Added:
* user can now specify when to start and stop playing.

####v.3.4.00:
######Added:
* PathFinder class. At this moment it contains one method to find map sequences. Will be developed in future.
* bot_sets with intention :search are now called similarly to :elite (added control thread).  
* rescuing errors raised in MargoBot.find_mob
######Changed:
* more flexible system of going back to towns, when hero is not on start_map when calling MagoBot.find_mob
######Fixed:
* problems with breaking handle_kill thread during first call.
* because of features described above, bot is more bulletproof now.


####v.3.3.10:
######Added:
* New class ScriptManager.rb (it will be developed gradually).
* Deleting logs on start of the bot.
######Fixed:
* rarely occurring crash during the movement.
* rarely occurring crash during the teleportation.
* problems with looping in infinity while waiting for response


####v.3.3.00:
######Added:
* reaction on attacks while moving.
######Fixed:
* typo in atalia_seq
######Changed:
* more flexible searching gateways when moving to map.

####v.3.2.00:
######Added:
* Lines separating Kills list (after each start saving 'separator' to Kills list)
* Two new sequence files (atalia_seq, demonisPl_seq)
######Optimized:
* Aborted saving too much details in logs.
######Changed:
* Lowered specific times for wait, so bot play faster.
######Fixed:
* separating logs between files.
* saving empty lines in Kills list

####v.3.1.22:
######Added:
* separation of logs between files (avoid creating pretty big files.)

####v.3.1.21:
######Added:
* saving header in file 'Kills list' when creating.
######Fixed:
* crashes after performing all sets
* rarely occurring bug while waiting for mob which resulted in dropping current set.
* typo in oblo_seq

####v.3.1.20:
######Added:
* new sequence for searching a mob (oblo_seq)
######Fixed:
* issue with saving every kill in kills list in newline.

####v.3.1.14: 
######Fixed:
* breaking performance of a set after appearing new message on a chat.

####v.3.1.13:
######Added:
* @file_name instance variable storing name of log file for ChatMonitor objects.
######Changed:
* chat log files naming convention
######Fixed:
* error occurring while adding kill to kills log.
######Known issues:
* when new message appears on chat, bot may raise an error and switch to next set.

####v.3.1.12:
######Fixed:
* switching hero when set intention is :search
* saving chat monitor file even though there were no new messages.

####v.3.1.11:
######Fixed:
* saving stats to file
* bug with killing elites (in BotManager)
######Changed:
* kill logs are now saved to one file (Kills list)
* using items which adds gold moved from Bot to Hero.

####v. 3.1.10:
######Fixed:
* bug causing impossibility of killing elites.
######Changed:
* versions naming convention: last char [a-z] changed to number [0-9].

####v. 3.1.0a:
######Added:
* BotManager class which is used to handle several accounts.
* priorities for bot sets
* intentions for bot sets (searching mob, exp or killing elites.)
######Changed:
* Logs and statistics are now individual for each account (stored in different dirs)
* some logic moved from MargoBot to BotManager
* calling Driver methods in LocalDriver (using method missing instead of @driver inside the class.)
* $can_stop_thread was changed to Bot.can_interrupt 
* $start_time and $amount_of_kills are now instance variables of LocalDriver
######Removed:
* $speed, $refresh global variables (deleted and no equivalent).
* $driver (now each class using LocalDriver has instance variable with it. It was obligatory to be able to handle several drivers.)
* sound alerts (it was working only in MAC OS.)
* $hero global variable
* $current_set global variable
######Fixed:
* quite often occurring bug which resulted in not taking an action after finding mob.
* rarely occurring problems with switching hero.

####v. 3.0.2c:
######Deleted:
* requiring not used gem in game.rb
###### Known issues:
* same as in 3.0.2a

####v. 3.0.2b:
######Changed:
* parsing from json works in linux now.
###### Known issues:
* same as in 3.0.2a

####v. 3.0.2a: #####
######Added:
* Using items which add gold
* initializing BotSettings objects from MargoBot class
* checking if hero lost the battle, waiting while is dazed and healing after.
* added method use in Item class.
######Changed:
* heal method moved to Hero class
###### Known issues:
* Problems while working on slow internet connection

####v. 3.0.1a: #####
######Added:
* safe map.move calling and checking if moving went ok.
* method to check current map name independently in LocalDriver
* solution when given coords (map.move_to_coords) were inaccessible.
######Changed:
* way of checking hero nick and profession to more bulletproof
######Bugs fixed:
* issues with ChatMonitor
* problems with clearing path
###### Known issues:
* Problems while working on slow internet connection.

####v. 3.0.0a: #####
* bot can follow paths (instruction in README)
* detecting mobs
* alerts about finding wanted mob
* possibility of teleportation between towns
* bot attacks mobs which are blocking access to coords when moving.
* a few prepared sequences to search heroes
* optimized creating a path
* fixed bug with finding path (last few steps are OK now).
* lots of small bugs fixed
* Many little changes in way methods do its work
* Several other small features added. Mostly not visible for user.


####v. 2.1.1a: #####
* fixed bug with saving chat log to file.

####v. 2.1.0b: #####
* renamed CHANGELOG to CHANGELOG.md
  
####v. 2.1.0a: #####
* Revised chat monitor:
  - Added ChatMonitor class
  - removed chat_monitor method from local_driver
  - chat_monitor works better now 

####v. 2.0.0b: #####
* Fixed bug that caused some problems with finding path when moving hero
* Fixed bug with getting group of mobs
* Fixed bug with saving a part of logs to wrong directory.

####v. 2.0.0a: #####
* New way of moving hero (bot can find and follow a path to target).
* player_reaction = nil option removed. (Now it can be only true/false)
* Saving logs was really fucked up and it took about 300 ms to do it. Optimized - now it's several ms.
* Removed get_process_mem and cpu-memory-stats gems.
* Removed thread sending test messages to log.
* added map class
* added possibility of changing maps (hero can go to another map)

####v. 1.0.1a: #####
* User can choose how long bot should wait for each mob.

####v. 1.0.0a: #####
* Handling several heroes works well.
* No known bugs.
* player_reaction option has new functions and works better.
* Bot works faster.
* Haven't observed too high CPU usage after optimisation.
* Fixed errors handling.
* New versions scheme (n1.n2.n3[a-z]: [a-z] - changed details, n3 - little changes (usually fixed bugs), n2 - changed/added some functions, n1 - big actualises)