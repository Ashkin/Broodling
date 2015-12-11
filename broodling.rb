# Name: Broodling
# Type: Poker bot
# File: Broodling.rb
# Auth: Terra
# Desc: Atonomously plays poker by interacting directly with the page


## TODO:

## Later:
# handle 60sec "can't sit down yet" thing.
# check_messagges()  # error/info dialogs
# Add key check: x should log the bot out, save the log, and exit.
# Should log_info player's money per hand, if less than blinds (or just 'all in due to blinds')
# [x] Tournament addons
# [x] Should also show per-stage cards.  can probably even display the suit chars in the log
# Change game settings: color scheme
# Randomly turn off animations
# Checks
#  - Game.tourney? instead of @gametype.in [:sng, :tournament]
#  - Pot + bet
#  - Funds - bet/call
#  - Chat actually adds to chatbox
#  - Hand frozen? (Game.sitting? and Game.hand_in_progress? and time since last action > 2.minutes  and hand_id == prev hand_id)
#  - Game.all_unique_cards?
#  - not our_turn? after random_action
#  - check funds against expected? (bet/wins/losses)
#  - queue an action, check if it happens.
#  - check positions of cards  (card marker)
#  - make sure everyone actually has two hole cards (objects and markup)
#  - disconnect from node and make sure a dialog shows up
#  - refresh browser (and wait a sec or two), and ensure same state (table, our_turn, etc)
#  - Check for inability to click buttons
#  - check for failure to switch tables during tourneys
#    x refresh if only_player? -> check if only_player?  // only possible on backend
#      ^ will generate false positives if all other tables are actually full


## Added:
# corrected handling of pending tournaments and rejoining tournaments (selenium's Wait was causing unexpected problems)
# Detect end of tournaments/sng's -- exit gracefully


## Next version:
# focus on callbacks
# scheduler:  Schedule.event(3.seconds, :sitting_check, *args)
# in decide() figure out current state (our_turn, our_turn_waiting_for_resolution, standing_pregame, standing, etc) and handle those individually.
# add expecting object
#  - expecting.accurate? ~> true/hash({:our_turn => false, :flop_or_higher=>true})
#  - expecting :our_turn, :flop_or_higher, etc.
#  - expecting :pot => 12.0
#    - :our_turn, :not_our_turn, :flop_or_higher, :showdown
#    - :pot => (Numeric), :funds => (Numeric)


require 'rbconfig'
require 'selenium-webdriver'
require './patches.rb'
require './patches-selenium.rb'
require './game.rb'
require './chat.rb'


class BotError < StandardError; end


class Broodling

  OS = case RbConfig::CONFIG['host_os']
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        :windows
      when /darwin|mac os/
        :osx
      when /linux/
        :linux
      when /solaris|bsd/
        :unix
      else
        :unknown
      end

  Tournament_Pending_Text     = "Tournament pending"
  Tournament_Paused_Text      = "Tournament is currently paused"
  Tournament_Finished_Text    = "Tournament finished"
  Tournament_Busted_Out_Text  = "Game Over"
  Browser_404_Titles          = ["Problem loading page", "Failed to open page"]

  Colorize_Output       = true
  Log_Debug_Messages    = true
  Debug_Display_Shares  = false
  Freeze_On_Kill        = false
  Resize_Browser        = {:none    => nil,
                           :smaller => [470, 480],  # four zoomouts
                           :small   => [620, 600]   # three
                          }[:small]
  Drivers = {
    :chrome => { :class => Selenium::WebDriver::Chrome, :path => "/usr/lib/chromium-browser/", :driver => "chromedriver" }
  }

  attr_accessor :browser, :url, :username, :password
  attr_reader   :driver,  :log, :alive,    :creation_time, :mode

  def initialize(opts={})
    @creation_time = Time.new

    @log        = []
    @log_indent = 0
    log_raw "Bot created at " + @creation_time.to_s + "\n"

    @opts       = opts

    @browser    = opts.delete(:browser)   || :firefox  # :firefox, :chrome, :ie, :safari, :opera, etc
    @url        = opts.delete(:url)       || "http://ashleyvm-frontend.sppinternal" || "https://test.realgaming.com"
    @url.chomp!("/")
    @username   = opts.delete(:username)  || "bot" + (1+rand(98)).to_s
    @password   = opts.delete(:password)  || "test1"
    @moneytype  = opts.delete(:moneytype) || :free     # :free, :money
    @gametype   = opts.delete(:gametype)  || :ring     # :ring, :sng,  :tournament
    @gameid     = opts.delete(:gameid)    ||  nil
    @mode       = :spawn
    @alive      = true


    raise ParamError, "Invalid game type specified!  (#{@gametype})"  if not @gametype.in  [:ring,  :sng, :tournament]
    raise ParamError, "Invalid money type specified! (#{@moneytype}"  if not @moneytype.in [:money, :free]
    # browser can be quite a few; i'll let selenium check that.



    # Set vars for the remainder, if present
    opts.each do |k,v|
      instance_variable_set("@#{k}", v)
      temp_class = class<<self; self; end
      temp_class.class_eval do
        attr_accessor k
      end
    end

    Chat.name = @username
    log_info "Bot creation finished."
    log_info "Host OS:  #{OS} (#{RbConfig::CONFIG['host_os']})"
    log_info "Browser:  #{@browser}"
  end

#################
## Start the bot!

  def init
    @mode   = :init

    create_webdriver
    login
    bypass
    enter_lobby
    join_game(@gametype, @gameid)
    play_game
  end



# Utility functions

  def reset
    log_debug("Resetting bot.")
    kill_browser if @driver

    printf "\n\n\n-------------------------------------\n\n\n"

    @table_controls_error  = nil
    @logged_sitdown_error  = nil
    @playing_timestamp     = nil
    @hand_stage            = nil
    @hand_id               = nil
    @only_player_timestamp = nil
    @log_indent            = 0

    initialize @opts
    log_debug("Bot reset.")
    init
  end



  # Allow for cooldowns on functions in one call.
  # return if unavailable?(:chat, 10.seconds)
  def unavailable?(key, cooldown, check_only=nil)
    @cooldowns ||= {}
    if @cooldowns[key].nil?
      @cooldowns[key] = Time.new
      return false
    end
    available = (Time.new - @cooldowns[key]) >= cooldown
    @cooldowns[key] = Time.new  if available and not check_only
    not available
  end




  # Return time since creation (in seconds)
  def timestamp
    "%.3f" % (Time.now - @creation_time)
  end


  # Indent log messages
  def increase_log_indent
    @log_indent += 1
  end
  def decrease_log_indent
    return if @log_indent == 0
    @log_indent -= 1
  end


  # Shorthand message logging
  def log_info(message);    log(message, :info);    end
  def log_error(message);   log(message, :error);   end
  def log_fatal(message);   log(message, :fatal);   end
  def log_warning(message); log(message, :warning); end
  def log_status(message);  log(message, :status);  end # less important entry
  def log_debug(message);   log(message, :debug);   end # logged only when enabled
  def log_end(message);     log(message, :end);     end # marks the beginning of the end
  def log_raw(message);     log(message, :raw);     end # logs without prefix or timestamp

  # Add message to the log, with timestamp
  def log(message=nil, type=:none)
    # Reader for log
    return @log if message.nil?
    # Make debug messages more distinguishable when colored output is not available/enabled.
    if type == :debug and not (OS.in [:unix, :linux] and Colorize_Output)
      message = "> " + message
    end

    # allow inserting of blank lines
    if message.gsub("\n","").empty? 
      @log << message
      puts    message
      return  message
    end

    return if type == :debug and not Log_Debug_Messages

    prefix  = case type
              when :info
                "info "
              when :error
                "error"
              when :fatal
                "fatal"
              when :warning
                "warn "
              when :end
                "-end-"
              when :debug
                "debug"
              when :raw
                nil
              else
                "     "
              end

    if not prefix.nil?
      prefix += "  " + timestamp().to_s + " sec    " + '| ' * @log_indent
    else
      prefix = ""
    end

    # add hanging indent to multi-line messages (if applicable)
    message = message.split("\n")  # always returns array
    message.map!.with_index do |m, id|
      id==0  ?  m.strip  :  m = " " * prefix.length + m.strip
    end
    entry = prefix + message.join("\n") + "\n"
    @log << entry

    if Colorize_Output and OS.in [:unix, :linux]
      printf  case type
              when :info
                @log.last.blue
              when :status
                @log.last.gray
              when :error
                @log.last.red
              when :fatal
                @log.last.red.bold
              when :warning
                @log.last.brown
              when :end
                @log.last.green.bold
              when :debug
                @log.last.magenta
              else
                @log.last
              end
    else
      printf @log.last
    end

    return entry
  end

  # Useless
  def display_log
    printf "Bot log:\n"
    @log.each{ |m| printf m }
    printf "\n\n\n"
  end


  def save_log
    separator   = (OS == :windows ? "\\" : "/")
    path        = ".#{separator}logs#{separator}"
    filename    = "#{@browser} ~ #{OS} ~ #{@username} ~ #{@creation_time.asctime}.log"
    filename.gsub!(":", ".") if OS == :windows

    file = File.new("#{path}#{filename}", "w")
    log_info("Saving log to file.")
    log_debug("filename: #{path}#{filename}")
    @log.each do |line|
      file.printf line
    end
    file.close
  end


  # Kill the bot.. cleanly, if possible.
  # Optionally freezes for debugging.
  # Also attempts to standup/logout
  def kill(err=nil)
    Kernel::exit() if @driver.nil?
    standup
    chat("Help!  I'm dying....", true) if @err and mode.in [:standing, :playing]
    log_end("Kill():  Killing bot...")
    return infinite_loop(err)   if Freeze_On_Kill

    increase_log_indent
      logout
      kill_browser
    decrease_log_indent
  ensure
    log_end("Finished.")
    @alive = false
    Kernel::exit()
  end

  # Closes the browser.
  # Selenium crashes upon calling driver#quit twice, and there's no alive check.
  def kill_browser
    return if @browser.nil?
    log_info("Closing browser")
    @driver.quit
    @driver = nil
  rescue StandardError => e
    return if e.message.include? "Connection refused"
    log_error("driver.quit failed!\nError message:\n#{e.message}")
  end



  # Terminate the bot
  # logs debugging info and optionally an error message
  def terminate(message, err=nil)
    log_debug("Call to terminate()")
    if @driver.nil?
      log_end '| Bot exiting.'
      Kernel::exit()
    end
    log_fatal(message)  if not message.empty?
    log_info("- current mode: #{@mode}")
    log_info("- current title: #{@driver.title}")  rescue log_info("- current title: n/a")

    kill(err)
  end


  def standup
    return if not @mode == :playing
    return if not @driver.ele_exists? "#btnStandUp"
    prevent_navigation_popups()
    log("Standing up")
    @driver.ele("#btnStandUp").click()
    @mode = :standing
  rescue
    log_warning '| Standup failed.'
  end


  def logout
    log("Logging out")
    return if @driver.nil?
    @driver.navigate.to(@url + "/account/logout")
  rescue StandardError => e
    return log_warning '| Logout failed.' if not e.message.include? "Connection refused"
    return log_warning "\| Logout failed. (#{e.message}"
  end





  # Set up the WebDriver
  def create_webdriver
    @mode = :webdriver
    # Add the driver to the path (in linux) if required
    ENV['PATH'] += ":" + Drivers[@browser][:path]  if OS == :linux  and not Drivers[@browser].nil?

    @driver = Selenium::WebDriver.for @browser
    raise BotError, "WebDriver creation failed.  Invalid browser? (#{@browser})" if @driver.nil?
    Game.bot    = self
    Game.driver = @driver

    # pretty-print the browser's info
    log_info("Browser Capabilities:\n" +
             @driver.capabilities.as_json.map{ |k,v|("%-30s" % "- #{k}:") + v.to_s }.join("\n"))

    if Resize_Browser
      w,h = Resize_Browser
      log "Resizing browser to #{w}x#{h}"
      @driver.manage.window.resize_to(w,h)
    end
  end



  # Login
  def login
    log("Navigating to login page.")
    @mode = :login
    @driver.navigate.to @url

    ## This may differ per browser
    if @driver.title.in Browser_404_Titles
      log("Navigating to login page. (again)")
      @driver.navigate.to @url
      return terminate("Cannot navigate to login page (server down)")  if @driver.title.in Browser_404_Titles
    end

    # log in
    Wait.upto(10.seconds).for { @driver.ele("#username") }
    do_login()

    # need to log in again?
    do_login(:again) if @driver.ele_exists?("#username")

    delay(1.second)
    # Still need to log in again?  Probably an error, or invalid username
    log_debug("Checking for #username")
    return terminate("Cannot seem to log in")  if @driver.ele_exists?("#username")
  end


  # Bypass captcha and geo checks
  def bypass
    @mode = :bypass
    prevent_navigation_popups()
    log("Using Bypass")
    @driver.navigate.to(@url + "/hacks/bypass_authentication.php?username=#{@username}&timestamp=" + Time.new.to_s)
  rescue StandardError => e
    return terminate("Error occured while using Bypass (Navigation popup?)", e)
  end



  # Enter the lobby
  def enter_lobby
    @mode = :lobby

    begin
      prevent_navigation_popups()
      log("Navigating back to the main page")
      @driver.navigate.to @url
    rescue StandardError => e
      return terminate("Navigation popup", e)
    end
    
    if not @moneytype.in [:free, :money]
      log_warning("invalid type for @moneytype (#{type}) -- should be :free or :money. Defaulting to :free")
      type = :free
    end


    begin
      caption = "Play " + (@moneytype == :free ? "Free" : "Real Money") + " Poker"
      log("Clicking [#{caption}]")
      Wait.upto(15.seconds).for { @driver.find_element({:link_text => "#{caption}"}) }
      @driver.find_element({:link_text => "#{caption}"}).click()
      let_page_load()
    rescue StandardError => e
      return terminate("Cannot find [#{caption}] button", e)
    end
  end



  # Join a particular type of game
  def join_game(type=:ring, id=nil)
    raise ArgumentError, "Invalid game type specified (#{type})" if not type.in [:tournament, :sng, :ring]
    @mode = :join

    join_specific_game type, id  if id
    join_random_game   type      if not id

    prevent_navigation_popups
  end


  def link_hrefs
    @mode = :link_hrefs
    # log_info("Updating link hrefs...")
    @driver.execute_script('
      window.gameCount = 0;
      for(i=0; i<document.links.length; i++) {
        if ((document.links[i].href.indexOf("tournament_id")>=0)  ||  (document.links[i].href.indexOf("table_id")>=0)) {
          document.links[i].href += "&format=raw&view=holdem";
          document.links[i].className += " game" + ++window.gameCount;
        }
      }')
    # log_info("...Finished.")
    game_count = @driver.execute_script("return window.gameCount")
    if game_count > 0
      log_info("Found #{game_count} link(s).")
      prevent_navigation_popups()
    end
    return game_count
  end


  def join_specific_game(type,id)
    raise ArgumentError if not type.in [:tournament, :sng, :ring]

    gametype = { :tournament => "Tournament", :sng => "Sit and Go", :ring => "Ring Game" }[type]
    game_id  = (type == :ring ? "table" : "tournament") + "_id=#{id}"

    begin
      prevent_navigation_popups()
      log("(Directly) Joining #{gametype} id #{id}")
      @driver.navigate.to(@url + "/component/camerona/?view=holdem&format=raw&#{game_id}")
    rescue StandardError => e
      return terminate("Could not join #{gametype}.  (Navigation popup?)", e)
    end

    # Table not available?
    if @driver.find_element(:tag_name => "body").text == "This table is not available"
      return terminate("That table is not available or does not exist.")
    end

    if type == :ring
      log_info("Allowing javascript to finish setting up")
      Wait.upto(10.seconds).until { Game.loaded? }
      @mode = :standing
      sitdown(:force)

    # Register for the tourney and agree to its terms.
    elsif type.in [:sng, :tournament]
      begin
        Wait.upto(15.seconds).for { tournament_pending? or Game.sitting? or @driver.ele(".register") or @driver.ele(".unregister") }
        if @driver.ele_exists?(".register")
          log("Registering")
          @driver.ele(".register").click()
        elsif tournament_pending?
          log_info("We're already registered, and the tournament is pending.")
        elsif Game.sitting?
          log_info("We're already playing.")
        end
      rescue StandardError => e
        # We might already be sitting at the table.
        return terminate("Failed to click Register button", e) if not Game.sitting?
      end

      if @driver.ele_exists?(".yes")
        log("Agreeing")
        @driver.ele(".yes").click()
      end
    end # type
  end


  # Joins a random available game
  # refreshes the lobby every 30 seconds if needed.
  def join_random_game(type, join_game=false)
    raise ArgumentError if not type.in [:tournament, :sng, :ring]
    return if @driver.nil?

    gametype = { :tournament => "Tournament",  :sng => "Sit and Go", :ring => "Ring Game" }[type]
    linktext = { :tournament => "Tournaments", :sng => "Sit and Go", :ring => "Ring"      }[type]

    # Handler
    if not join_game
      begin
        log_info "Waiting to join a #{gametype}..."
        Wait.upto(15.minutes).until { join_random_game(type, :join_game) }
        return true;
      rescue StandardError => e
        return terminate("Could not join game.  (Navigation popup?)", e)
      end
    end

    # Join a game
    return if not join_game # Sanity

    ele = nil
    Wait.upto(15.seconds).for { ele = @driver.find_element({:link_text => linktext}) }
    ele.click()

    # Count (and update) available links, refresh if lacking.
    link_count = link_hrefs()
    if link_count < 1
      delay 30.seconds
      log_info "Refreshing and trying again."
      @driver.navigate.to @driver.current_url.gsub(/&timestamp=.+/, "") + "&timestamp=#{Time.new.to_i}"
      # @driver.navigate.refresh()  ## Does not force-reload
      return false
    end

    # Click on a random link
    id = 1+rand(link_count)
    log("Joining random #{gametype} (id #{id})")
    @driver.ele(".game#{id}").click()


    log_info("Allowing javascript to finish setting up")
    Wait.upto(10.seconds).until { Game.loaded? }

    
    # sitdown if ring
    if type == :ring
      @mode = :standing
      sitdown(:force)

    # Register for the tourney and agree to its terms.
    elsif type.in [:sng, :tournament]
      begin
        Wait.upto(15.seconds).for { tournament_pending? or Game.sitting? or @driver.ele(".register") or @driver.ele(".unregister") }
        if @driver.ele_exists?(".register")
          log("Registering")
          @driver.ele(".register").click()
        elsif tournament_pending?
          log_info("We're already registered, and the tournament is pending.")
        elsif Game.sitting?
          log_info("We're already playing.")
        end
      rescue StandardError => e
        return terminate("Failed to click Register button", e)
      end

      if @driver.ele_exists?(".yes")
        log("Agreeing")
        @driver.ele(".yes").click()
      end
    end # type

    # signal successful join
    return true

  rescue StandardError => e
    return terminate("Could not join a #{gametype}", e)
  end



  def sitdown_button_exists?
    @driver.ele_exists?(".sitdown")
  end
  # Sit down at the table
  # (Only applicable to ring games)
  ## TODO: check for empty chairs (js:total players - js:player count)
  def sitdown(forced=nil)
    return if Game.tourney?
    if not sitdown_button_exists? and not forced
      log_warning("Tried to sit down, but there is no sitdown button.  (Non-forced sitdown)")
      log_info("There are #{Game.free_seats} seat(s) available.")
      return false;
    end
    begin
      # Forced, or
      # Non-forced + sitdown button
      log_info("Waiting to sit down at table")  if forced and not sitdown_button_exists?
      log_info("There are #{Game.free_seats < 1 ? "no" : Game.free_seats} seat(s) available.")

      Wait.upto(3.years).for { @driver.ele_exists? ".sitdown" }  if forced
      log("Sitting down at table#{forced ? " (forced)" : ""}")
      @driver.ele(".sitdown").click()


      ## Debugging
      if not Game.sitting? and not waiting_for_buy_in?
        log_warning("Strangly, we're not sitting after clicking sitdown.")
        log_info("Trying again.")
        if not sitdown_button_exists?
          log_warning("Sitdown button does not exist.")
          return terminate("We are not sitting after clicking sitdown, and the button no longer exists.")
        end
        @driver.ele(".sitdown").click()
        delay 2.seconds
        @was_sitting = Game.sitting?
        if not Game.sitting? and not waiting_for_buy_in?
          log_error("Not sitting after two attempts, and not waiting for buyin.")
          raise RuntimeError
        end
      end

      verify_matching_gametype
      return true

    rescue StandardError => e
      log_error "Cannot seem to sit down!"
      log_info  "- Sitdown button does #{ @driver.ele_exists?(".sitdown") ? "" : "NOT "}exist"
      log_info  "- We are #{Game.sitting? ? "" : "NOT " }sitting down."
      log_info  "- We are #{waiting_for_buy_in? ? "" : "NOT "}waiting for buyin."
      log_info  "- playercount: #{Game.playercount}"
      log_info  "- free seats:  #{Game.free_seats}"
      log_info  "- table id:    #{Game.table_id}"
      log_info  "- title:       #{@driver.title}"
      log_info  "- mode:        #{@mode}"
      return terminate("Cannot sit down at the table.", e)
    end
  end




  def play_game
    log("Playing")
    @playing           = true
    @mode              = :playing
    @last_decision     = Time.new
    @playing_timestamp = Time.new
    @hand_id           = nil

    while @playing and @alive do
      decide()
    end

    return if not @alive or @browser.nil?

    # stand_up
    log("Finished.")
    return kill()
  end


  def verify_matching_gametype
    tabletype = :ring  if not Game.tourney?
    tabletype = {"SIT_N_GO" => :sng, "MULTI_TABLE" => :tournament}[Game.tourney_type]  if Game.tourney?
    return true if @gametype == tabletype

    terminate("*** Bot Error: Game type (#{@gametype}) does not match table type (#{Game.tourney_type})")
  end


  def check_cards
    return if Game.all_unique_cards?
    log_error("Duplicate cards!")
    log_info("- Bot's cards:      #{Game.my_cards}")
    log_info("- Community cards:  #{Game.community_cards}")
    log_info("- All Player cards: #{Game.all_player_cards}")
  end


  # Log hand id and stage, if either changed.
  def log_hand_state
    return if (Time.new - @playing_timestamp) < 2.seconds  # let javascript create the game_meta object
    new_hand_id    = Game.hand_id
    new_hand_stage = Game.stage

    new_hand  = (new_hand_id    != @hand_id)
    new_stage = (new_hand_stage != @hand_stage)

    if new_hand
      @hand_id = new_hand_id
      log "\n"
      log_status "Hand ID:    #{@hand_id}"
      # log_info "Hole cards: #{Game.my_cards}"  ## cards' position in deck...
    end

    if new_hand or new_stage
      @hand_stage = new_hand_stage if new_stage
      log_status "Hand stage: #{@hand_stage}"
    end
  end



  # Check for missing table controls
  # Displays warning for each missing control
  # and a message when the control reappears on subsequent checks
  # Ignores first five seconds of gameplay.
  def check_table_controls
    return if (Time.new - @playing_timestamp) < 5.seconds
    return if waiting_for_buy_in? or waiting_for_tourney_rebuy?
    return if waiting_for_hand_resolution

    @was_missing ||= {}
    missing        = {}
    missing[:chatbar] = (not @driver.ele_exists? "new_table_chat")
    missing[:away]    = (Game.sitting? and not Game.all_in? and not @driver.ele_available? "#btnAway")
    missing[:standup] = (Game.sitting? and not Game.all_in? and not Game.tourney? and not @driver.ele_available? "#btnStandUp")
    missing[:lobby]   = (not @driver.ele_available? "#back_to_lobby" and not Game.tourney?)

    {:chatbar => "Chat bar",
     :away    => "Away button",
     :lobby   => "Back to Lobby button",
     :standup => "Stand Up button"}.each do |control, name|
      log_warning "Control is Missing: #{name}"  if missing[control] and not @was_missing[control]
      log_info    "Control Reappeared: #{name}"  if @was_missing[control] and not missing[control]
    end

    # one of the controls' states changed. log some details
    log_details = (not @was_missing == missing)  if not @was_missing.empty?
    log_details = missing.values.include?(true)  if     @was_missing.empty?

    if log_details
      log_info "- mode:      #{@mode}"
      log_info "- stage:     #{Game.stage}"
      log_info "- sitting:   #{Game.sitting?}"
      log_info "- our turn?: #{Game.our_turn?} (js)"
    end

    # store states for next check
    @was_missing = missing

    return missing.values.include? true
  end


  # Check for lingering sitdown button(s)
  ## TODO: check for 60second sitdown message.
  def check_sitdown_controls
    return if not Game.sitting?  # buttons should exist while standing!
    return if (Time.new - @playing_timestamp) < 15.seconds
    delay 1.second if @driver.ele_exists? ".sitdown"
    return if waiting_for_buy_in? or waiting_for_tourney_rebuy?

    if @driver.ele_exists? ".sitdown"
      if @driver.ele_exists? "#btnStandUp"
        log_error("Stranging, we are no longer sitting.")
        # sitdown
      elsif not @logged_sitdown_error
        @logged_sitdown_error = true
        log_error("There's a sitdown button still visible.")
      end
    end
  end



  def modal_dialogs_present?
    @driver.ele_exists?(".modal-header")
  end
###
# def foo(str,x=nil)
#   x = [:header,:body,:footer] if x.nil?
#   if x.is_a? Array
#     array = x.collect{|c| foo(str, c)}
#     p array
#     return array.include? true
#   end
#   str == x
# end


  def modal_contains?(text, components=nil)
    return false if not modal_dialogs_present?
    components = [:header, :body, :footer] if components.nil?
    if components.is_an? Array
      return components.collect{|c| modal_contains?(text, c)}.include? true
    end

    @driver.eles(".modal-" + components.to_s).each do |msg|
      return true if msg.text.include? text
    end
    false
  end


  # Is the "Tournament pending" dialog visible?
  def tournament_pending?
    return false if not @gametype.in [:sng, :tournament]
    return true if modal_contains?(Tournament_Pending_Text)  # :header
    false
  end

  def tournament_paused?
    return false if not @gametype.in [:sng, :tournament]
    return true if modal_contains?(Tournament_Paused_Text)  # :body
    false
  end

  def tournament_busted_out?
    return false if not @gametype.in [:sng, :tournament]
    return true  if modal_contains?(Tournament_Busted_Out_Text)  # :body
    false
  end

  # Is the "Tournament finished" dialog visible?
  def tournament_finished?
    return false if not @gametype.in [:sng, :tournament]
    return true  if modal_contains?(Tournament_Finished_Text)  # :header
    false
  end





  # TODO: cleanup/improve
  def check_messages
    return if not modal_dialogs_present?
    headers  = @driver.eles(".modal-header")
    messages = @driver.eles(".modal-body")
    check    = []

    # Check dialog headers
    headers.each.with_index { |header, i|
      next if header.text.include? Tournament_Pending_Text
      next if header.text.include? Tournament_Finished_Text
      next if messages[i].text.include? "Buy in"
      # Idle Notification
      # 
      log_debug("Found dialog with title: #{header.text}")
      check << i  if header.text.include? "Important Message"
    }

    # Log anything interesting
    check.each { |i|
      next if messages[i].text.include? Tournament_Paused_Text
      next if messages[i].text.include? Tournament_Busted_Out_Text
      log("Dialog: " + messages[i].text)
     ## TODO: Check for "Unable to sit so soon after unseating."  and set sitdown timer
    }

    # Close the dialogs.
    @driver.eles(".close").each { |ele| ele.click() }
  end


  def decide
    # Two second minimum delay between actions
    return if @driver.nil?
    return delay 0.5.seconds if unavailable?(:decide, 2.seconds)
    @last_decision = Time.new

    return terminate("Strangely, we're now in the lobby instead of at the table") if @driver.title.downcase.include? "lobby"

    if Game.tourney?
      # Log tourney_paused? warnings if paused longer than 10 seconds, every 10 seconds.
      @tournament_paused_timestamp = nil  if not tournament_paused?
      if tournament_paused?
        if @tournament_paused_timestamp.kind_of? Time
          if (@tournament_paused_timestamp - Time.new) >= 10.seconds
            @tournament_paused_timestamp = Time.new
            log_warning "The tournament has been paused for 10 seconds."
          end
        else
          @tournament_paused_timestamp ||= Time.new
        end
        return

      elsif tournament_busted_out?
        log_end "We've busted out of the tournament. :("
        return kill

      elsif tournament_finished?
        log_end "Tournament finished."
        return kill
      end
    end # Game.tourney?



    return buy_in         if waiting_for_buy_in?
    return tourney_rebuy  if waiting_for_tourney_rebuy?

    check_cards()             # checks for duplicates, makes sure everyone has the correct number of cards visible, etc.
    check_sitdown_controls()  # checks for any lingering sitdown buttons
    check_table_controls()    # checks for anything out of place
    check_messages()          # checks for error/info dialogs

    return buy_in         if waiting_for_buy_in?
    return tourney_rebuy  if waiting_for_tourney_rebuy?


    if not Game.sitting? and @was_sitting
      @was_sitting = false
      log_error("Strangely, we are no longer sitting.")
      log_info("Attempting to sit down again.")
      sitdown
      return;
    end


    # Log changes in playercount
    if Game.playercount != @previous_playercount
      @previous_playercount = Game.playercount
      log_info("There are now #{@previous_playercount} players") if not Game.only_player?
    end

    # Nothing to do ...
    if Game.only_player?
      chat(:lonely) if rand(1000) < 3
      if @only_player_timestamp.kind_of?(Time) and not @gametype == :tournament
        if (Time.new - @only_player_timestamp) > 5.minutes
          log_info "We've been the only player for five minutes."
          kill
        end
      end

      return if @only_player_timestamp
      @only_player_timestamp = Time.new
      log_info("We're the only player.")
      return
    elsif @only_player_timestamp
      @only_player_timestamp = false
    end
    
    chat(:general) if rand(100)<3 and not Game.only_player?
    log_hand_state  # log if hand state has changed (id, stage)
    if our_turn?
      log_info("It is our turn")
      chat(:turn) if rand(100)<30
      random_action
      chat if rand(100)<30
    end
    delay 2.seconds  # Sleep a bit
  end


  def let_page_load
    Wait.upto(30.seconds).for { @driver.execute_script("return document.readyState") == "complete" }
  rescue StandardError => e
    return terminate("Page failed to load within 30 seconds.", e)
  end


  def delay(duration)
    @sleeping = true
    sleep(duration)
    @sleeping = false
  end



## driver utility functions

  def prevent_navigation_popups
    log_info("Preventing 'Are you sure?' dialogs")
    let_page_load()    # Wait for page to load
    delay 0.5.seconds  # wait for javascript to complete
    # Kill onbeforeunload event handler
    @driver.execute_script("window.onbeforeunload=null;")
  end


  def do_login(again=false)
    log("Logging in as: #{@username}" + (again==:again ? " (again)" : ""))

    increase_log_indent
      log_debug("Entering username (#{@username})");  ele = @driver.ele("#username");  ele.clear();  ele.send_keys(@username)
      log_debug("Entering password (#{@password})");  ele = @driver.ele("#password");  ele.clear();  ele.send_keys(@password)
      log_debug("Submitting");  ele.submit()

    if @browser != :safari # Not supported.
      log_debug("Setting selenium page_load timeout (10 sec)")
      @driver.manage.timeouts.page_load = 10
    end

    decrease_log_indent
  end



  def waiting_for_hand_resolution
    Game.stage == :winner
  end


  def waiting_for_tourney_rebuy?
    @gametype == :tournament and (@driver.ele_exists?(".no") or @driver.ele_exists?(".yes"))
  end
  def tourney_rebuy
    return if not @gametype == :tournament
    choices = []
    choices << ".no"  if @driver.ele_exists?(".no")
    choices << ".yes" if @driver.ele_exists?(".yes")

    return if choices.empty?  # Shouldn't happen.
    if choices.sample == ".yes"
      log("Buying back into tournament.")
      @driver.ele(".yes").click()
    else
      log("Lost! and I don't want to rebuy.  Exiting Tournament :(")
      @driver.ele(".no").click()
    end
  end


  def waiting_for_buy_in?; @driver.ele_exists?(".buyin"); end
  def buy_in
    begin
      return if not waiting_for_buy_in?
      log("Buying in")
      Wait.upto(10.seconds).for { @driver.ele ".buyin" }

      @driver.ele(".buyin").click()
      # sitdown if sitdown_button_exists?
    rescue StandardError => e
      log_info("Buyin button doesn't exist")  if not waiting_for_buy_in?
      return terminate("Cannot buy in.", e)
    end
  end


  def our_turn_via_controls?
    !@driver.ele_visible?(".autoUserAction_container")  and  driver.ele_exists?(".player_timer")  and  @driver.ele_available?("#btnPass.primary")
    # !@driver.ele_visible?(".autoUserAction_container")  and  driver.ele_exists? ".player_timer"
    # @driver.ele_available?("#btnPass.primary")  and  driver.ele_exists? ".player_timer"
  end
  def our_turn?
    via_controls   = our_turn_via_controls?
    via_javascript = Game.our_turn?

    trace = [:our_turn?]

    # not our turn
    return false if not (via_javascript or via_controls)
    return true  if via_javascript and via_controls

    # technically our turn, but it's doing hand resolution, so there's nothing to do.
    # wait for a bit and check again; if it's still our turn, continue on.
    if waiting_for_hand_resolution
      begin
        trace.push :waiting_for_resolution
        log_info("Waiting for hand resolution")
        Wait.upto(30.seconds).until { not waiting_for_hand_resolution }
        via_javascript = Game.our_turn?
        
        return false if not via_javascript
        sleep 2.seconds if not our_turn_via_controls?
        via_controls = our_turn_via_controls?      
      rescue
        log_warning("our_turn?() timed out (30sec) waiting for hand resolution.  Is the hand frozen?")
        return false
      end
    end

    # Prevent edge-case wherein javascript hasn't updated either our turn flag or our controls yet
    # controls lagging behind javascript? let's wait a bit and try again.
    if via_javascript and not via_controls
      begin
        trace.push :via_js_not_controls
        Wait.upto(3.seconds).for { our_turn_via_controls? }
      rescue
        trace.push :did_not_appear_after_wait
        log_info("Controls did not appear after 5+ seconds.")
        log_info("Saving screenshot. (1)")
        filename = "./screenshots/controls ~ #{Time.new.asctime}.png"
        filename.gsub!(":",".") if OS == :windows
        @driver.save_screenshot filename
        log_info("- Fold:      #{driver.ele_exists?("#btnPass.default") ? "blue" : "grey"}")
        log_info("- Timer:     #{driver.ele_exists?(".player_timer") ? "visible" : "not visible"}  (Any timer)")
        log_info("- Container: #{@driver.ele_visible?(".autoUserAction_container") ? "visible" : "not visible"}")
        log_info("- via_js:    #{Game.our_turn?}")
        log_info("- via_ctrls: #{our_turn_via_controls?}")
        log_debug("- Trace:     #{trace}")
        # return false
      end
    end

    via_javascript = Game.our_turn?
    via_controls   = our_turn_via_controls?
    if not via_controls
      trace.push :not_via_controls_2
      log_info("Saving screenshot. (2)")
      @driver.save_screenshot "./screenshots/controls ~ #{Time.new.asctime}.png"
    end

    return false if not (via_javascript or via_controls)  # both false? not our turn.
    return true  if via_javascript and via_controls

    # javascript and controls still don't match up
    if not (via_javascript and via_controls)
      log_error("the controls indicate it's our turn, but javascript does not.") if via_controls
      log_error("javascript indicates it's our turn, but the controls do not.")  if via_javascript
      log_info("- Fold:      #{driver.ele_exists?("#btnPass.default") ? "blue" : "grey"}")
      log_info("- Timer:     #{driver.ele_exists?(".player_timer") ? "visible" : "not visible"}  (Any timer)")
      log_info("- Container: #{@driver.ele_visible?(".autoUserAction_container") ? "visible" : "not visible"}")
      log_info("- Stage:     #{Game.stage}")
      log_info("- via_js:    #{Game.our_turn?}")
      log_info("- via_ctrls: #{our_turn_via_controls?}")
      log_debug("- Trace:     #{trace}")
      log("Skipping turn.")
      Wait.upto(3.years).for { not Game.our_turn?         } if via_javascript
      Wait.upto(3.years).for { not our_turn_via_controls? } if via_controls
      return false;
    end

    return true
  end


  def wait_for_turn
    log_info("Waiting for turn...")
    Wait.upto(3.years).for { our_turn? or waiting_for_buy_in? or waiting_for_tourney_rebuy? }
  end


  def wait_for_end_of_turn
    log_info("Waiting for end of turn...")
    Wait.upto(3.years).until { not our_turn? }
  end


  # Bot Chatting
  # Text chats directly, Symbol specifies the message type (see chat.rb)
  # Leave blank for random
  def chat(text="", overridden=nil)
    return log_error("Missing Control: Cannot find chat box  (in chat())") if not @driver.ele_exists? "new_table_chat"
    return if unavailable?(:chat, 10.seconds) and not overridden

    # Blank? random message from either :general, :turn, or @last_action
    if text.empty?
      if rand(100)>5
        text = rand(100)<30 ? :turn : @last_action
      else
        text = :general
      end
    end

    # Symbol? Random of type
    if text.is_a? Symbol
      text = :general  if Chat[text].nil?
      # Not sitting?  Only general messages will make sense.
      text = :general  if not Game.sitting?
      text = :lonely   if Game.only_player?
      text = Chat[text].sample
    end

    log_info("Chatting: #{text}")
    ele = @driver.ele "new_table_chat"
    ele.clear()
    ele.send_keys(text)
    ele.send_keys(:return)
    # ele.submit()
  end


  # Add Shares system for weighting
  def get_available_actions
    {
      "#btnPass.primary"      => {:shares=>10, :id=>:fold,      :text=>"Folding :(" },
      "#btnCheck.primary"     => {:shares=>40, :id=>:check,     :text=>"Checking."  },
      "#btnCheckFold.primary" => {:shares=>2,  :id=>:checkfold, :text=>"Check/Fold" },
      "#btnCall.primary"      => {:shares=>40, :id=>:call,      :text=>"Calling!"   },
      "#btnCallAny.primary"   => {:shares=>10, :id=>:call,      :text=>"Calling Any"},
      "#btnRaise.primary"     => {:shares=>20, :id=>:raise,     :text=>"Raising ~"  },
      "#btnAllIn.primary"     => {:shares=>10, :id=>:allin,     :text=>"ALL CAPS IN!"}
    }.delete_if { |ele,desc| not @driver.ele_available? ele }
  end

  def random_action
    return if not Game.sitting?
    return if not our_turn?
    return if waiting_for_buy_in?
    return if waiting_for_tourney_rebuy?
    @last_turn = Time.new
    actions = get_available_actions()

    # 'Invisible buttons' and 'Not our turn' bugs
    if actions.empty?
      log_warning("It is our turn, but no buttons are available.")
      log_info("Waiting up to 5 seconds for them to appear, or for a buyin/rebuy dialog")
      # log_info("Waiting for hand resolution.")  if actions.empty?
      begin
        Wait.upto(5.seconds).for { @driver.ele_available?("#btnPass.primary") or waiting_for_buy_in? or waiting_for_tourney_rebuy? }

        return log_warning("Strangely, it is not our turn anymore. Skipping. (line #{__LINE__})") if not our_turn?
        return if waiting_for_buy_in?
        return if waiting_for_tourney_rebuy?

        # check if there are still no available buttons
        # and check the hand state -- hand might be frozen.

        # Sometimes: it would have been our turn, but we need to buy in again.

        # Should still be our turn, but assumptions often lead to trouble.
        # return if not our_turn?

        actions = get_available_actions()
        raise RuntimeError if actions.empty?
      rescue StandardError => e
        log_error("There are no available buttons.  Skipping turn.")
        Wait.upto(30.seconds).until { not our_turn? }
        return
      end
    end


    # Wait a random amount of time
    time_left = Game.player_timer
    if time_left > 3  and rand(100) < 30
      time_to_wait = rand(time_left-2)+1
      log("Waiting #{time_to_wait} seconds before acting (#{time_left} seconds remaining)")
      delay time_to_wait
    end


    # Pick random action (weighted using shares)
    keys           = actions.keys
    shares         = actions.values.collect{ |v| v[:shares] }
    selected_share = rand(shares.inject(:+)) # rand(0..total shares)
    selected_copy  = selected_share
    action         = nil
    # subtract shares in order until <= 0
    shares.each.with_index do |shares, i|
      selected_share -= shares
      if selected_share <= 0
        # use resulting index
        action = keys[i]
        @last_action = actions[keys[i]][:id]
        break
      end
    end


    return log_warning("Strangely, it is not our turn anymore. Skipping. (line #{__LINE__})") if not our_turn?


    # Should never happen.
    if (actions.nil? or actions.empty?)
      terminate("Actions array is blank/nil!  This should never happen.")
      infinite_loop()
      Kernel::exit()
    end

    # Also should never happen.
    if (action.nil? or actions[action].nil?)
      err  = "Internal error: Selected action is invalid.  This should never happen.\n" +
             "Selected share: #{selected_copy}  (after: #{selected_share})\n" +
             "shares:  #{shares}\n" +
             "keys:    #{keys}\n" +
             "action: '#{action}'\n"
      if actions.empty?
        err += "Available actions hash is empty."
      else
        err += "Hash of available actions:\n"
        actions.keys.each { |key| err += key.to_s + ": " + actions[key].to_s + "\n" }
      end
      terminate(err)
      infinite_loop()
      Kernel::exit()
    end

    display = "%-15s" % actions[action][:text] + "   " + "%-25s" % "(#{action})"
    display += "  -- " + "#{selected_copy} of (#{shares.inject(:+)}) #{shares}"  if Debug_Display_Shares
    log(display)

    # Invisible buttons bug
    log_error("It is NOT our turn!")                     if not our_turn?
    log_error("The #{action} button is invisible.")      if not @driver.ele_visible?(action)
    log_error("The #{action} button is disabled.")       if not @driver.ele_enabled?(action)
    log_error("The #{action} button is not displayed.")  if not @driver.ele_displayed?(action)

    ele = @driver.ele(action)
    ele.click()
  rescue StandardError => e
    infinite_loop e
  end



  def infinite_loop e=nil
    log_debug("Debug:  Paused via Infinite loop")

    if not e.nil?
      printf "\n\nError message:\n#{e.message}\n"
      printf "Stacktrace:\n"
      e.backtrace.each do |m|
        puts m.to_s
      end
    end

    while 1
      sleep
    end
  end
end
