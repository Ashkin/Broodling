# Broodling #
#### An autonomous poker bot for automated frontend and stress testing ####
> The name is a reference to the Zerg Broodlings from Starcraft -- small and effective creatures, if short-lived.

Sample logs and screenshots are in [/logs](https://github.com/Ashkin/Broodling/tree/master/logs) and [/screenshots](https://github.com/Ashkin/Broodling/tree/master/screenshots), respectively.  You can see an example of two bots running side-by-side in [concurrent.png](https://github.com/Ashkin/Broodling/blob/master/concurrent.png); it's pre-flop, so there is no visible card spread.

----------------------------------------------------

## Background ##
> The project remains unfinished as the company and I parted ways due to financial issues before its completion.

**This bot was very effective, both as an automated testing tool and as a flashy way of showing off to investors.**

I wrote this bot for Real Gaming, an online casino, as a way to automatically check for issues with both the website and the game itself.  It's written in Ruby and uses Selenium to interact directly with a browser.  In this way, the bot simulates a user navigating through the site and playing in games, encountering any issues an end-user would.  Populating a game or tournament with bots would allow us to watch the backend for any abnormalities, as well as see any javascript, frontend or gameplay issues the bots may uncover.

Whenever a bot discovers something amiss, it logs the event (with color-coded onscreen output), complete with relevant state data, and it saves a browser screenshot as well.  The bot's log allowed us to recreate the event, and the screenshot showed any frontend issues, such as missing buttons or other UI elements.  The table and hand ID (visible in both log and screenshot) allowed us to review the hand in question, further helping to locate any game or backend issues.

*Originally, brood.rb acted as a handler for multiple bots with threading planned; this was later revised in favor of a single-bot approach for aesthetic reasons (multiple logs visible concurrently); for reasons unknown they requested I keep the bot handler.*

## Launching ##
I wrote a rakefile to simplify launching bots (and allow them to be run via batch file or script), and made it as user-friendly as I could.

**To run a bot using default values, simply type:**

        rake bot

**If you want to specify custom params, the format is:**

        rake bot param=val param=val

**for example:**

        rake bot browser=chrome gametype=tournament url=https://staging.realgaming.com

**The available params are as follows:**
* url        --- the base url to use; defaults to https://test.realgaming.com
* browser    --- firefox (default), chrome, safari, opera, ie
* moneytype  --- free (default), money
* gametype   --- ring (default), sng, tournament
* gameid     --- (integer) table/tournament id;  picks a random game unless this is specified
* username   --- leave blank to use a random bot (bot #1-98)
* password   --- leave blank to use the default bot password (test1)

