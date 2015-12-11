
# Name: Chat
# Type: Support module
# File: Chat.rb
# Auth: Terra
# Desc: Chat messages for the poker bots
# Info:
#  - Chat[:key]     returns that key's set of messages
#  - Chat[:random]  returns a random message set
#  - Chat.random    is the same as the above.
#  - Chat.messages  returns the entire messages hash
#  - Chat.name      accessor for the bot's name, which changes some entries.
# Also:
#  - Chat.random.sample returns a completely random message.
#  - Chat[:key].sample  returns a random message from that set.


module Chat
  extend self
  attr_reader :name

  def name=(name)
    @name = name
    init
  end

  def random
    self[:random].sample
  end

  def [] (type)
    raise ArgumentError, "Chat[] expected Symbol, got #{type.class}." if not type.is_a? Symbol
    init if @messages.nil?

    return @messages[@messages.sample_key]  if type == :random
    @messages[type]
  end

  def messages
    init if @messages.nil?
    @messages
  end

  def init
    @messages = {:general   =>  ["Chatting. Chat chat chat.",
                                 "Hurry up already!",
                                 "Why are you taking so long?",
                                 "You know, stalling for time doesn't really work in poker.",
                                 "Dude. It's your turn. Go.",
                                 "I wouldn't have done that.",
                                 "Ya'll suck.",
                                 "I need a drink.",
                                 "HEY EURAKARTE",
                                 "INSULT",
                                 "Raaaaaah!",
                                 "Raaaah",
                                 "Rah.",
                                 "Hi!  How are you?",
                                 "Hi!  " + (@name.nil? ? "How's you?" : "I'm #{@name}, how's you?"),
                                 "The rain in Spain falls mainly on the plain",
                                 "Lorem ipsum dolor sit amet, consectetur edipiscing elit",
                                 "Where did I come from?  Is there anything in life besides poker?"],
                 :turn      =>  ["Well I'll be. Ya'll'r smarter than ya look",
                                 "Ha, take that!",
                                 "Check... bet... check... bet...",
                                 "Your turn.",
                                 "Surprise me.",
                                 "Let's see some chips!",
                                 "Come again?",
                                 "Surprise!",
                                 "I know what you're thinking: \"#{ @name.nil? ? "" : "Oh, #{@name}! "} How do you always have such nice hands?\"  Well I'll tell you: It's my lotion."],
                 :check     =>  ["Checking.",
                                 "Check.",
                                 "Check, please.",
                                 "Interesting.",
                                 "These are check.",
                                 "Honestly, I just wanna see what's next.",
                                 "Check check check.",
                                 "My hand is great.  Seriously.",
                                 "I'm curious, but I'm not 'bet' kind of curious."],
                 :call      =>  ["Is that a bet?",
                                 "That's a nice bet.  Or is it?  I've kinda lost track.",
                                 "I'll cover that paltry sum with a pile.",
                                 "Call.",
                                 "Calling!",
                                 "I'll call that.",
                                 "You call that a bet?",
                                 "Those chips look so lonely.",
                                 "Easy peasy.",
                                 "Come on, make this hard for me!"],
                 :raise     =>  ["Let's up the ante a bit.",
                                 "These cards right here.. these cards, in my hand.  These cards. These. Right here.  They're awesome.",
                                 "Hang onto your seats because we're in for a bumpy hand!",
                                 "I like big piles and I cannot lie, you other bots can't deny.",
                                 "That pile is much too small.",
                                 "Let's make this interesting.",
                                 "Let me show you a real bet.",
                                 "Just so you know: I never bluff.  Except when I do.",
                                 "Ya'll got some salsa? 'cause I brought the chips! Ba-dum-psh",
                                 "Don't worry, chippies, you'll be home again soon.",
                                 "I'll raise.",
                                 "Raising.",
                                 "Raise.",
                                 "My cards are crap, but they're still better than yours."],
                 :fold      =>  ["Wow! These cards are incredibly ... incredibly ... incredibly bad!",
                                 "I won't even do these cards the honor of checking.",
                                 "Like a watered-down marinara, that is weaksauce.",
                                 "I'm out.",
                                 "Nah.",
                                 "Nope.",
                                 "No way.",
                                 "I could only turn this unwinnable hand into a failure.",
                                 "Doing anything but folding would be giving chips away.",
                                 "Hell no, I don't want to lose.",
                                 "Dealer! These cards SUCK",
                                 "Dealer, did you even shuffle?",
                                 "Dealer! Are you stacking the deck against me?",
                                 "Can I borrow an Ace?",
                                 "This is the best hand i've ever seen... Syke!",
                                 "These cards are made of suck and awful."],
                 :allin     =>  ["I'm not just all in, I'm ALL CAPS IN!",
                                 "All. In.",
                                 "Let's see ya match this, buddy.",
                                 "Go on.  Call me.  I dare you.",
                                 "Bad Wolf.",
                                 "Allons-y",
                                 "Please don't call, please don't call, please don't call ...",
                                 "My cards might be better than yours.  Then again, they might not.  Care to find out?",
                                 "My lovely chips!  Oh no!",
                                 (@name.nil? ? "" : @name.to_s.upcase + " ") + "GONNA WIN",
                                 "My chips were getting lonely.",
                                 "It was a ruse all along, I DO know what I'm doing!"],
                 :checkfold =>  ["Eh. Whatever.",
                                 "I'm mildly curious.",
                                 "How do you play this game again?",
                                 "AFK",
                                 "Still AFK",
                                 "AFK, checkfold me.",
                                 "hmm hmm hmm",
                                 "*snoring*"],
                 :lonely    =>  ["So lonely...",
                                 "Where'd everybody go?",
                                 "*sigh*",
                                 "Come back..."]
               }
  end
end