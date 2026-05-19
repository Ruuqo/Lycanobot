# lycanobot 1.0.1
namespace eval lycanobot {
   # Configuration
   variable conf

   #### EDITABLE ####
   #
   # Channel used for the game
   set conf(chanDay) "#thiercelieux"

   # Default topic - Will be append with status & commands
   set conf(topic) "Les Loups-Garous de Thiercelieux"

   # Prefix of the night channel 
   set conf(chanNight) "#nuit"

   # Language selection
   set conf(lang) "fr"

   # delay to join game after !start in minutes
   set conf(wait) 10

   # Enable random night channel name
   set conf(chanRand) 1

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
