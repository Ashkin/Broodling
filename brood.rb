# Name: Brood
# Type: Bot Handler
# File: Brood.rb
# Auth: Terra
# Desc: This acts as the handler for a Broodling bot.


require './broodling.rb'

class ParamError < StandardError; end

module Brood
  def self.init(opts={})
    @bot = Broodling.new(opts)

    @bot.init()
    while true
      sleep 0.5
      if not @bot.alive
        @bot.save_log
        @bot.reset
      end
    end

  rescue ParamError => e
    printf "\n\n"
    printf "Paramater Error:"
    printf e.message
    printf "\n\n"
    Kernel::exit()

  rescue Interrupt => i
    printf "\n"  # console displays a ^C
    @bot.log_end "Caught Interrupt. Exiting."
    @bot.kill
    @bot.save_log
    printf "\n\n\n"
    Kernel::exit()

  rescue StandardError => e
    if @bot.nil? or @bot.driver.nil?
      printf "Error message:\n#{e.message}"
      printf "\n\nStacktrace:\n"
      e.backtrace.each do |m|
        printf m.to_s
      end
      Kernel::exit()
    end


    @bot.log_fatal("Caught an unhandled error. Shutting down bot.")
    @bot.log_info("- Mode: #{@bot.mode}")

    if not @bot.driver.nil?
      @bot.log_info("- Title: #{@bot.driver.title}") rescue @bot.log_info("- Title: n/a (browser closed?)")
      @bot.standup  rescue @bot.log_info("Standup failed")
      @bot.logout   rescue @bot.log_info("Logout failed (browser closed?)")
    else
      @bot.log_info("- WebDriver is nil.")
    end

    @bot.log_fatal("Error message:\n#{e.message}")
    @bot.log_raw("\n\nStacktrace:\n")
    e.backtrace.each do |m|
      @bot.log_raw(m.to_s)
    end

    @bot.save_log
    @bot.driver::quit  rescue nil
    Kernel::exit()
  end

end

# If we've been included, skip the rest
Kernel::exit() if $0 != __FILE__

# Otherwise, convert any passed k:v args to a hash
params = {}
ARGV.each { |argh|
  next if not argh.include? ":"
  k,*v = argh.split(":")  # key is left of first :,  value is the rest
  v    = v.join(":")      # convert to string / rejoin with :'s if needed (ex: url)
  v    = nil if v.empty?  # nil if blank

  # Convert to proper types and formats
  if k.in %w[ browser moneytype gametype ]
    v.gsub!(/:/,"")
    v = v.to_sym
  end
  v = v.to_i   if k == "gameid"

  # Add to params hash
  params[k.to_sym] = v
}

# Launch bot
Brood::init(params)
