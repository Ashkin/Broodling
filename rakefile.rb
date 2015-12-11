# Brood Rakefile

task :default => :help

task :help do |t|
  printf "\n" +
         "Brood is our browser testing system. Using 'rake bot' creates a Broodling\n" + 
         "that will navigate the site and play games automatically until killed, or\n" +
         "it crashes. The bot also logs errors it finds, as well as every action it\n" +
         "has taken so whatever bugs should be reproducable later.\n" + 
         " -- Log directory: brood/logs/*.log\n" +
         "\n\n" +
         "To use the defaults, run:  rake bot\n" +
         "To specify params,   run:  rake bot param=val param=val ...\n" +
         "\n" +
         "Available params:\n" +
         "  url        \| base url to use.  Defaults to https://test.realgaming.com\n" +
         "  browser    \| firefox, chrome, safari, opera, ie    # Default: firefox\n" +
         "  moneytype  \| money,   free                         # Default: free\n" +
         "  gametype   \| ring,    sng,    tournament           # Default: ring\n" +
         "  gameid     \| (integer) table/tournament id         # Default: (random)\n" +
         "  username   \| leave blank for random  bot (1-98)\n" +
         "  password   \| leave blank for default bot password (test1)\n" +
         "\n\n" +
         "Example:  rake bot gametype=tournament gameid=12 moneytype=money\n"
end




task :bot, :args do |t, args|
  # You can specify defaults here.
  # Saves a bit of typing.
  args.with_defaults({
    :gametype  => :ring,
    :moneytype => :free
  })
  
  args   = args.to_hash
  params = ""

  vars = %w[ browser url moneytype gametype gameid username password ]
  vars.each{ |v|
    next if ENV[v].to_s.empty?
    ENV[v] = "\"#{ENV[v]}\""   if ENV[v].include? " "  # Allow quotes
    args[v.to_sym] = ENV[v]
  }

  # hash -> "k:v k:v"
  args.each { |k,v| params += "#{k}:#{v} " }
  params.strip!

  exec "ruby brood.rb #{params}"
end