# Name: Game
# Type: Support module
# File: game.rb
# Auth: Terra
# Desc: Provides utility functions by polling javascript for the game's state.
# Info: Set Game.bot (Broodling instance) and Game.driver before using


module Game
  extend self
  def self.bot=(broodling)
    raise ArgumentError, "Invalid class passed to Broodling::Game.bot= (Expected Broodling, got #{bot.class})" if not broodling.is_a? Broodling
    @bot = broodling
  end
  def self.driver=(driver)
    @bot.log_warning("Game.driver set to nil")  if driver.nil?
    @driver = driver
  end
  def self.var(var)
    @driver.execute_script("return #{var}")
  rescue StandardError => e
    @bot.log_warning("javascript error: #{e.message}")
    nil
  end

  def self.playersdata_keys
    @driver.execute_script("
      keys = [];
      for(player in game.players_data) {
        keys.push(player);
      }
      return keys;");
  end
  def game(var);               var("game."+var.to_s);         end
  def self.loaded?;            game("is_state_initialized");  end
  def self.playersdata;        game("players_data");          end
  def self.mykey;              game("md5");                   end
  def self.mydata;             playersdata.reject{|k,v| v["name"] != @username};    end # using playersdata[mykey] looks cleaner but is slower
  def self.stage;              game("hand_data.table_action").to_s.to_sym;          end # :pending :cards :flop :turn :river :winner :""
  def self.all_in?;            game("hand_data.is_allin");                          end
  def self.hand_in_progress?;  game("game_meta.is_hand_in_progress");               end
  def self.tourney?;           game("is_part_of_tournament")  or  game("game_meta.is_tournament");  end
  def self.sitting?;           game("is_user_seated");                              end
  def self.our_turn?;          game("is_my_turn");                                  end
  def self.player_timer;       game("player_action_time_remaining").to_f;           end  # 0..15
  def self.betting_round;      game("betting_round");                               end  # 0..3
  def self.my_cards;           mydata.each{ |k,v| v["cards"] };                     end
  def self.all_player_cards;   playersdata.collect{ |k,v| v["cards"] };             end
  def self.all_unique_cards?;  (community_cards << all_player_cards).flatten.reject{|c| c.in ["",nil]}.uniq?;                   end
  def self.community_cards;    game("hand_data.flop").to_a << game("hand_data.turn") << game("hand_data.river");        end
  def self.blinds;             {:small => game("hand_data.smallblind").to_f,  :big => game("hand_data.bigblind").to_f}; end
  def self.maxplayers;         game("game_meta.max_num_players").to_i;   end # int
  def self.playercount;        playersdata_keys.size;                    end # int
  def self.only_player?;       playercount == 1;                         end
  def self.free_seats;         maxplayers - playercount;                 end # int
  def self.pot;                game("getPotSum()").to_f;                 end # float
  def self.hand_id;            game("game_meta.gameplay_history_id");    end
  def self.table_id;           game("table_id");                         end
  def self.tourney_id;         game("game_meta.tournament_instance_id"); end
  def self.tourney_type;       game("tournament_meta.tournament_type");  end # SIT_N_GO, MULTI_TABLE
  def self.tabletype;          game("game_meta.table_type");             end # NO_LIMIT, POT_LIMIT, etc
end
