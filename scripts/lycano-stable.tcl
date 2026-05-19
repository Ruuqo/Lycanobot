# lycanobot 1.0.1
namespace eval lycanobot {
   # Configuration
   variable conf

   #### EDITABLE ####
   #
   # Channel used for the game
   set lg_main_channel "#thiercelieux"
   set conf(chanDay) $lg_main_channel

   # Default topic - Will be append with status & commands
   set conf(topic) "Les Loups-Garous de Thiercelieux"

   # Fixed wolves channel. The bot must already be present on it.
   set lg_wolves_channel "#nuit"
   set conf(chanNight) $lg_wolves_channel

   # Language selection
   set conf(lang) "fr"

   # delay to join game after !start in minutes
   set conf(wait) 10

   # Enable random night channel name
   # V2 keeps the wolves channel fixed and configurable.
   set conf(chanRand) 0

   # Length of the random string
   set conf(chanKey) 8

   # Separator between prefix and rand string
   set conf(chanSep) "_"

   #### EDIT WITH CARE
   #
   # Place of the outputed files (logs, html stats, ...)
   # Use absolute path or relative to eggdrop
   set conf(ofile) "databases/"
   # Default game mode
   set conf(mode) "stable"

   # Ratio of wolves
   set conf(wolves) 0.2

   # Users allowed to run sensitive game commands in addition to channel ops.
   # Values can be IRC nicks or Eggdrop handles.
   set conf(admins) ""

   # In-memory game ban list. Use !banjeu / !unbanjeu while the bot is running.
   set conf(gameBans) ""

   # Default timeout, in minutes, for private role actions.
   set conf(roleTimeout) 2

   # Cooldown, in seconds, for the public composition command.
   set conf(compositionCooldown) 60

   # Require the bot to be op or halfop on the wolves channel before a game starts.
   set conf(requireWolvesOp) 1

   # Require the bot to be op or halfop on the public channel before a game starts.
   set conf(requireMainOp) 1

   # Remove old random wolves channels left by previous versions from Eggdrop's
   # persistent channel list. The default pattern follows lg_wolves_channel_*.
   set conf(cleanLegacyNightChannels) 1
   set conf(legacyNightChannelPattern) ""

   # Command aliases. Keep the leading ! and separate aliases with spaces.
   set conf(cmdStart) "!partie !start !game"
   set conf(cmdJoin) "!jouer !play !join"
   set conf(cmdComplete) "!complet"
   set conf(cmdCancel) "!annuler !stop !reset"
   set conf(cmdComposition) "!composition !compo"
   set conf(cmdForceJoin) "!forcerjoin"
   set conf(cmdForceQuit) "!forcerquit"
   set conf(cmdBanGame) "!banjeu"
   set conf(cmdUnbanGame) "!unbanjeu"
   set conf(cmdBanListGame) "!banlistjeu"
   set conf(cmdStatus) "!status"
   set conf(cmdRoles) "!roles"
   set conf(cmdRules) "!regles !rules"
   set conf(cmdLegacyAdd) "!add"
   set conf(cmdVote) "!vote"
   set conf(cmdSeerCheck) "!qui"
   set conf(cmdRolePass) "!passe"

   # Turn debug on/off
   variable debug 1

   ### END OF SETTINGS ###
   # Do not edit anything below !

   ### LOADING ###
   variable rpath [file dirname [file normalize [info script]]]
   if {![file exists "${rpath}/lycanobot/core/lycanobot-[set [namespace current]::conf(mode)].tcl"]} {
      putlog "*** ABORTING *** Can't find lycanobot/core/lycanobot-[set [namespace current]::conf(mode)].tcl"
      return
   }
   source "${rpath}/lycanobot/core/lycanobot-[set [namespace current]::conf(mode)].tcl"
}
