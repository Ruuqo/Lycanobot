# Do not edit anything below !
namespace eval ::lycanobot {
   # package require json
   
   variable curNight
   variable inGame 0
   variable preGame 0
   variable players {}
   variable wolves {}
   variable temp
   variable voters {}
   variable gameIni
   variable jobbers {}
   variable winner {}
   variable isNight 0
   
   variable scriptname "LycanoBot"
   variable scriptversion 1.0.1
   
   if {[catch {package require hook}]} {
      putlog "WARNING : hook package required. The game will run in minimal version"
   }
   
   if {[catch {package require json}]} {
      putlog "WARNING : json package not detected, the game will use an alternative version"
      namespace eval ::json {
         proc json2dict {JSONtext} {
            string range [string trim [string trimleft [string map {\t {} \n {} \r {} , { } : { } \[ \{ \] \}} $JSONtext] {\uFEFF}]] 1 end-1
         }
      }
   }
   
   # Unload all components
   proc unload {type} {
      # remove binds
      foreach b [binds "[namespace current]*"] {
         lassign $b t f k n c
         unbind $t $f $k $c
      }
      # remove timers
      foreach t [list "ltend" "lthalf" "ltone"] {
         if {[lsearch -index 2 [timers] $t] != -1} {
            killtimer $t
         }
      }
      # delete namespace
      namespace delete [namespace current]
   }
  
   proc inigame {} {
      [namespace current]::dlog "Game initialization"
      if {![validchan [set [namespace current]::conf(chanDay)]]} {
         [namespace current]::dlog "--> Joining channel [set [namespace current]::conf(chanDay)]]"
         channel add [set [namespace current]::conf(chanDay)]
      }
      if {[set [namespace current]::conf(wait)] <= 2} {
         set [namespace current]::conf(wait) 2
      }
      [namespace current]::dlog "* Wait delay is [set [namespace current]::conf(wait)]"
      [namespace current]::i18n [set [namespace current]::conf(lang)] [namespace tail [namespace current]]
      [namespace current]::dlog "[set [namespace current]::scriptname] [set [namespace current]::scriptversion] loaded with [set [namespace current]::conf(lang)]"
      putlog "[set [namespace current]::scriptname] [set [namespace current]::scriptversion] loaded with [set [namespace current]::conf(lang)]"
      set topic "[set [namespace current]::conf(topic)] - [::msgcat::mc "Start game with \002%1\$s\002" [::msgcat::mc "!game"]]"
      if {[topic [set [namespace current]::conf(chanDay)]] ne $topic} {
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :$topic"
      }
      bind evnt - prerehash [namespace current]::unload
      bind evnt - prerestart [namespace current]::unload
      bind pub - [::msgcat::mc "!game"] [namespace current]::startGame
   }

   proc startGame {nick uhost handle chan args} {
      variable settings
      [namespace current]::dlog "--> Game started by $nick"
      if { [string tolower $chan] != [string tolower [set [namespace current]::conf(chanDay)]]} {
         [namespace current]::dlog "*** KO *** Bad channel $channel"
         return 0
      }
      if { ![botisop [set [namespace current]::conf(chanDay)]] && ![botishalfop [set [namespace current]::conf(chanDay)]] } {
         [namespace current]::dlog "*** KO *** I don't have required accesses"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "I need to be @ on %1\$s" [set [namespace current]::conf(chanDay)]]"
         return 0
      }
      set conf [join [lindex [split $args] 0]]
      if {$conf == ""} {
         set conf [set [namespace current]::conf(mode)]
      } else {
         set conf [string tolower $conf]
      }
      [namespace current]::dlog "* Game configuration is $conf"
      # Loading the .json file
      if {[catch {set fi [open [set [namespace current]::rpath]/lycanobot/lycanobot.json r]}]} {
         [namespace current]::dlog "*** KO *** Cannot load [set [namespace current]::rpath]/lycanobot/lycanobot.json"
         putserv "PRIVMSG $chan :[::msgcat::mc "Impossible to find %1\$s" [set [namespace current]::rpath]/lycanobot/lycanobot.json]"
         return 0
      }
      if {[catch {set settings [::json::json2dict [read -nonewline $fi]]}]} {
         [namespace current]::dlog "*** KO *** Bad format file in [set [namespace current]::rpath]/lycanobot/lycanobot.json (json2dict error)"
         putserv "PRIVMSG $chan :[::msgcat::mc "%1\$s is not in good format" "[set [namespace current]::rpath]/lycanobot/lycanobot.json"]"
         return 0
      }
      if {![dict exists $settings $conf]} {
         [namespace current]::dlog "*** KO *** Bad format file in [set [namespace current]::rpath]/lycanobot/lycanobot.json ($conf not found)"
         putserv "PRIVMSG $chan :[::msgcat::mc "%1\$s is not an available game type" $conf]"
         return 0
      }
      array set [namespace current]::gameIni [dict get $settings $conf]
      timer [set [namespace current]::conf(wait)] [list [namespace current]::endWaiting] 1 ltend
      [namespace current]::dlog "* Waiting for players during [set [namespace current]::conf(wait)] minutes"
      set halfwait [expr [set [namespace current]::conf(wait)]/2]
      if { $halfwait > 1} {
         timer $halfwait [list putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Only %1\$s minutes stays to register with \002%2\$s\002" $halfwait [::msgcat::mc "!play"]]"] 1 lthalf
         [namespace current]::dlog "* Advertising programmed in $halfwait minutes"
      }
      timer [expr [set [namespace current]::conf(wait)] - 1] [list putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Only one minute stays to register with \002%1\$s\002" [::msgcat::mc "!play"]]"] 1 ltone
      [namespace current]::dlog "* Last advertising programmed in [expr [set [namespace current]::conf(wait)] - 1] minutes"
      
      lappend [namespace current]::players $nick
      pushmode [set [namespace current]::conf(chanDay)] +v $nick
      set [namespace current]::preGame 1
      [namespace current]::dlog "* $nick added in players' list"
      set [namespace current]::master $nick
      putserv "TOPIC [set [namespace current]::conf(chanDay)] : [set [namespace current]::conf(topic)] - [::msgcat::mc "Game launched - Join the party by typing %1\$s" [::msgcat::mc "!play"]]"
      bind pub - [::msgcat::mc "!play"] [namespace current]::addPlayer
      bind pub - [::msgcat::mc "!complete"] [namespace current]::endWaitingManu
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "The game is launched, type \002%2\$s\002 to participate. End of registrations in %1\$s minutes" [set [namespace current]::conf(wait)] [::msgcat::mc "!play"]]"
      if {[info exists [namespace current]::conf(advertise)] && [set [namespace current]::conf(advertise)] ne ""} {
         [namespace current]::advertise [::msgcat::mc "A new game is waiting players on %1\$s" $chan]
      }
      
      # devel feature only - reserved to +n
      bind pub n "!add" [namespace current]::forceAdd
   }

   proc advertise {msg} {
      set chans [split [set [namespace current]::conf(advertise)] ","]
      foreach c $chans {
         set c [join $c]
         if {![validchan $c]} { continue }
         putserv "PRIVMSG $c :$msg"
      }
   }
         

   proc forceAdd {nick uhost handle chan text} {
      foreach p [split $text] {
         [namespace current]::addPlayer $p [getchanhost $p $chan] * $chan ""
      }
   }
   
   proc addPlayer {nick uhost handle chan text} {
      [namespace current]::dlog "--> $nick wants to play"
      if {[lsearch -nocase [set [namespace current]::players] $nick]!=-1} {
         [namespace current]::dlog "*** WARNING *** $nick already in players' list"
         putserv "PRIVMSG $chan :[::msgcat::mc "You're already in game, %1\$s" $nick]"
         return 0
      }
      lappend [namespace current]::players $nick
      [namespace current]::dlog "* New players' list : [join [set [namespace current]::players]]"
      pushmode [set [namespace current]::conf(chanDay)] +v $nick
   }

   # Manual stop of the wait for players
   proc endWaitingManu {nick uhost handle chan args} {
      [namespace current]::dlog "<-- Wait time stop invoked by $nick"
      if {$nick ne [set [namespace current]::master]} {
         [namespace current]::dlog "*** DENY *** $nick is not [set [namespace current]::master]"
         return 0
      }
      [namespace current]::dlog "*** OK *** : Gonna kill timers ltend, lthalf, ltone"
      foreach t [list "ltend" "lthalf" "ltone"] {
         if {[lsearch -index 2 [timers] $t] != -1} {
            [namespace current]::dlog "<-- Found $t, kill it"
            killtimer $t
         }
      }
      [namespace current]::endWaiting
   }

   # Stopping the wait for players
   # If not enough players, reset the game
   proc endWaiting {} {
      [namespace current]::dlog "* Global end of wait time"
      unbind pub - [::msgcat::mc "!play"] [namespace current]::addPlayer
      unbind pub - [::msgcat::mc "!complete"] [namespace current]::endWaitingManu
      unbind pub n "!add" [namespace current]::forceAdd
      set [namespace current]::preGame 0
      if { [set [namespace current]::gameIni(num_players)] > [llength [set [namespace current]::players]] } {
         [namespace current]::dlog "*** KO *** Not enough players : only [llength [set [namespace current]::players]] vs [set [namespace current]::gameIni(num_players)]"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "You need at least %1\$i players" [set [namespace current]::gameIni(num_players)]]"
         [namespace current]::cleanGame
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - [::msgcat::mc "Start game with \002%1\$s\002" [::msgcat::mc "!game"]]"
      } else {
         [namespace current]::dlog "--> Ok, game starting"
         set [namespace current]::inGame 1
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - [::msgcat::mc "Game in progress"]"
         [namespace current]::launchGame
      }
   }

   # Now, we really start the game.
   proc launchGame {} {
      [namespace current]::dlog "--> Real launching of the game in [set [namespace current]::conf(chanDay)]"
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Game is starting, I prepare the teams"]"
      pushmode [set [namespace current]::conf(chanDay)] +m
      if {[[namespace current]::makeNightChannel] ne ""} {
         [namespace current]::dlog "--> running makeWolves"
         [namespace current]::makeWolves
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Wolves have been choosed, beware !"]"
      }
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Every night in Thiercelieux, residents are devoured by ferocious werewolves"]"
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "During the day, the villagers organize themselves and find out who these monsters are..."]"
      [namespace current]::dlog "--> Loading jobs"
      [namespace current]::selectJobs
      set [namespace current]::inGame 1
      set [namespace current]::daycount 0
      set [namespace current]::nightcount 0
      bind pubm - "*!vote*" [namespace current]::pubmVote
      [namespace current]::itsNight
   }

   # Creating wolves
   proc makeWolves {} {
      set nbplayers [llength [set [namespace current]::players]]
      set nbv 0
      if {[info exists [namespace current]::gameIni(wolves)] && [string is list [set [namespace current]::gameIni(wolves)]]} {
         putlog "Got dict"
         foreach rng [dict keys [set [namespace current]::gameIni(wolves)]] {
            putlog "got $rng"
            regexp {(\d{1,})?(-)?(\d{1,})?} $rng - min sig max
            if {![info exists min]} { set min 0 }
            if {![info exists max]} { set max 999 }
            if {$nbplayers >= $min && $nbplayers <= $max} {
               set v [dict get [set [namespace current]::gameIni(wolves)] $rng]
               if {![string is integer $v] && $v<1.0} {
                  set nbv [expr floor($nbplayers * $v)]
               } elseif {[string is integer $v]} {
                  set nbv $v
               }
               break
            }
         }
      }
      if {$nbv == 0} {
         # arbitrary choice
         if {$nbplayers <= 10 } {
            set nbv 2
         } elseif { $nbplayers < 20 } {
            set nbv 3
         } else {
            set nbv [expr floor($nbplayers * [set [namespace current]::conf(wolves)])]
         }
      }
      [namespace current]::dlog "--> Waiting for $nbv wolves"
      for {set cur 0} { $cur < $nbv } { incr cur } {
         set free [::utils::ldiff [set [namespace current]::players] [set [namespace current]::wolves]]
         lappend [namespace current]::wolves [lindex $free [rand [llength $free]]]
         [namespace current]::dlog "Wolves are: [join [set [namespace current]::wolves]]"
      }
      foreach wolf [set [namespace current]::wolves] {
         [namespace current]::dlog "Now inviting $wolf to [set [namespace current]::curNight]"
         newchaninvite [set [namespace current]::curNight] $wolf $::botnick "It's a wolf" 0 sticky
         putserv "INVITE $wolf [set [namespace current]::curNight]"
         putquick "PRIVMSG $wolf :[::msgcat::mc "You're now a wolf, please join the night channel by typing \002/join %1\$s\002" [set [namespace current]::curNight]]"
      }
   }

   # Creating Night channel
   proc makeNightChannel {} {
      set [namespace current]::curNight [set [namespace current]::conf(chanNight)]
      if {[set [namespace current]::conf(chanRand)] == 1} {
         append [namespace current]::curNight [set [namespace current]::conf(chanSep)] [::utils::randKey [set [namespace current]::conf(chanKey)]]
      }
      channel add [set [namespace current]::curNight] {chanmode +ism}
      [namespace current]::dlog "Added [set [namespace current]::curNight] with +is mode"
      bind join - "[set [namespace current]::curNight] *" [namespace current]::wolfInChannel
      return [set [namespace current]::curNight]
   }


   proc wolfInChannel {nick uhost handle chan} {
      if {[isbotnick $nick]} { return }
      if {[lsearch -nocase [set [namespace current]::wolves] $nick] >=0} {
         pushmode [set [namespace current]::curNight] +v $nick
      } else {
         newchanban [set [namespace current]::curNight] [maskhost "${nick}!${uhost}" 7] $::botnick "Not a wolf"
         putkick [set [namespace current]::curNight] $nick [::msgcat::mc "Sorry but you're not allowed here"]
      }
   }
   
   # It's night, so players shut up
   # But wolves speak...
   proc itsNight {} {
      incr [namespace current]::nightcount
      set [namespace current]::isNight 1
      [namespace current]::dlog "-v- Night [set [namespace current]::nightcount] - Got [llength [set [namespace current]::players]] players and [llength [set [namespace current]::wolves]] wolves"
      [namespace current]::resetVotes
      set [namespace current]::round 0
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Night falls, the villagers fall asleep"]"
      [namespace current]::dlog "-v- Running night jobs"
      hook call job newnight [set [namespace current]::nightcount]
      foreach plr [chanlist [set [namespace current]::conf(chanDay)]] {
         pushmode [set [namespace current]::conf(chanDay)] -v $plr
      }
      putserv "PRIVMSG [set [namespace current]::curNight] :[::msgcat::mc "Wolves wake up"]"
      putserv "PRIVMSG [set [namespace current]::curNight] :[::msgcat::mc "Discuss among yourselves, and make your choice of victim with \002!vote <victim>\002"]"
      foreach wlv [set [namespace current]::wolves] {
         pushmode [set [namespace current]::curNight] +v $wlv
      }
   }

   # It's day, so wolves shut up and
   # alive players speaks
   proc itsDay {} {
      incr [namespace current]::daycount
      set [namespace current]::isNight 0
      [namespace current]::dlog "-^- Day [set [namespace current]::daycount] - Got [llength [set [namespace current]::players]] players and [llength [set [namespace current]::wolves]] wolves"
      [namespace current]::resetVotes
      set [namespace current]::round 0
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Day breaks, the villagers wake up"]"
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Discuss among yourselves, and designate the one you think being a wolf with \002!vote <wolf>\002"]"
      [namespace current]::dlog "-^- Running day jobs"
      hook call job newday [set [namespace current]::daycount]
      foreach wlv [chanlist [set [namespace current]::curNight]] {
         pushmode [set [namespace current]::curNight] -v $wlv
      }
      putserv "PRIVMSG [set [namespace current]::curNight] :[::msgcat::mc "The wolves return to the village"]"
      foreach plr [set [namespace current]::players] {
         pushmode [set [namespace current]::conf(chanDay)] +v $plr
      }
   }

   proc resetVotes {} {
      set [namespace current]::votes {}
      set [namespace current]::voters {}
      [namespace current]::dlog "*** RESET *** [llength [set [namespace current]::voters]] voters - [llength [set [namespace current]::votes]] votes"
   }

   # Randomize jobs, then call the assigner
   proc selectJobs {} {
      [namespace current]::dlog "--> Loading jobs if needed"
      foreach job [dict keys [set [namespace current]::gameIni(jobs)]] {
         set jobsrc [set [namespace current]::rpath]/lycanobot/jobs/job.${job}.tcl
         if {[file exists $jobsrc] && [file isfile $jobsrc] && [file readable $jobsrc]} {
            [namespace current]::dlog "*** PRELOAD *** job $job is loading from $jobsrc"
            [namespace current]::makeJob $job $jobsrc
         }
      }
      hook call job start
   }

   # Assign job to a player
   proc makeJob {job jfile} {
      set quot [dict get [set [namespace current]::gameIni(jobs)] $job]
      regexp {(\d{1,})(\+|-)?(\d{1,})?} $quot - min sig max
      if {[info exists min] && ($min>[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** WARN *** Not enough players ($min vs [llength [set [namespace current]::players]]), $job not loaded"
         return
      }
      if {![info exists sig] && ($min<[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** WARN *** Need exactly $min players, [llength [set [namespace current]::players]]) found, $job not loaded"
         return
      }
      if {[info exist sig] && ($sig eq "-") && [info exists max] && ($max<[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** WARN *** Too much players ($max vs [llength [set [namespace current]::players]]), $job not loaded"
         return
      }
      [namespace current]::dlog "--> Loading $jfile"
      source $jfile
   }

   # Game is ended, we clean everything
   proc cleanGame {} {
      [namespace current]::dlog "* Entering cleaning process"
      # Destroy the night channel
      if {[set [namespace current]::inGame] == 1} {
         [namespace current]::dlog "<-- Removing wolves channel [set [namespace current]::curNight]"
         unbind join - "[set [namespace current]::curNight] *" [namespace current]::wolfInChannel
         unbind pubm - "*!vote*" [namespace current]::pubmVote
         pushmode [set [namespace current]::curNight] -im
         foreach wlv [chanlist [set [namespace current]::curNight]] {
            if {$wlv eq $::botnick} { continue }
            putkick [set [namespace current]::curNight] $wlv "[::msgcat::mc "Game is over"]"
         }
         channel remove [set [namespace current]::curNight]
      }
      [namespace current]::dlog "<-- Removing player status in [set [namespace current]::conf(chanDay)]"
      foreach plr [chanlist [set [namespace current]::conf(chanDay)]] {
         pushmode [set [namespace current]::conf(chanDay)] -v $plr
      }
      pushmode [set [namespace current]::conf(chanDay)] -m
      # Clean the players list
      set [namespace current]::players {}
      set [namespace current]::wolves {}
      set [namespace current]::inGame 0
      set [namespace current]::preGame 0
      # remove all hooks:
      [namespace current]::dlog "<-- Unloading jobs (if needed)"
      hook call job clean
      hook forget job
      putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "The game is over for now, you can restart one with \002%1\$s\002" [::msgcat::mc "!game"]]"
      putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - [::msgcat::mc "Start game with \002%1\$s\002" [::msgcat::mc "!game"]]"
   }
   
   proc pubmVote {nick uhost handle chan text} {
      set text [stripcodes * $text]
      set text [join [lrange [split $text] 1 end]]
      [namespace current]::doVote $nick $uhost $handle $chan $text
   }
   
   proc doVote {nick uhost handle chan text} {
      set text [string trim $text]
      [namespace current]::dlog "/// VOTE /// $nick votes against $text"
      if {[set [namespace current]::inGame] == 0} {
         putserv "PRIVMSG $chan :[::msgcat::mc "A bit of patience"]"
         return 0
      }
      if {[set [namespace current]::isNight]==0 && [string match -nocase $chan [set [namespace current]::conf(chanDay)]]} {
         set votants [set [namespace current]::players]
      } elseif {[set [namespace current]::isNight]==1 && [string match -nocase $chan [set [namespace current]::curNight]]} {
         set votants [set [namespace current]::wolves]
      } else {
         [namespace current]::dlog "*** WARNING *** Vote in $chan - Waited in [set [namespace current]::conf(chanDay)] or [set [namespace current]::curNight]"
         return 0
      }
      
      if {[lsearch -nocase $votants $nick]==-1} {
         putserv "PRIVMSG $nick :[::msgcat::mc "Sorry, but you can't vote, you look dead"]"
         return 0
      }
      if {[llength [split $text]]>1} {
         putserv "PRIVMSG $chan :[::msgcat::mc "It's \002!vote someone\002 and nothing else"]"
         return 0
      }
      if {$text eq $nick} {
         putserv "PRIVMSG $chan :[::msgcat::mc "No \002%1\$s\002, you can't kill yourself" $nick]"
         return 0
      }
      if {[lsearch -nocase [set [namespace current]::players] $text]==-1} {
         putserv "PRIVMSG $chan :[::msgcat::mc "Difficult to vote for \002%1\$s\002 which seems dead" $text]"
         return 0
      }
      if {[lsearch -nocase [namespace current]::voters $nick]!=-1} {
         putserv "PRIVMSG $chan :[::msgcat::mc "You have already voted %1\$s, don't try to cheat" $nick]"
         return 0
      }
      if {[set [namespace current]::isNight] == 1 && [lsearch -nocase [set [namespace current]::wolves] $text]!=-1} {
         putserv "PRIVMSG $chan :[::msgcat::mc "Wolves do not eat each other."]"
         return 0
      }
      [namespace current]::dlog "Added $nick in voters"
      lappend [namespace current]::voters $nick
      if {![info exists [namespace current]::votes]} {
         set [namespace current]::votes {}
      }
      [namespace current]::dlog "Added $text in votes"
      lappend [namespace current]::votes $text
      [namespace current]::dlog "--- Got [llength [set [namespace current]::voters]] against [llength $votants] alive votants"
      if {[llength [set [namespace current]::voters]] == [llength $votants]} {
         putserv "PRIVMSG $chan :[::msgcat::mc "Everyone voted... Verdict..."]"
         set vict [[namespace current]::getWinner [set [namespace current]::votes]]
         if {$vict == -1} {
            if {[set [namespace current]::round] == 0} {
               incr [namespace current]::round
               putserv "PRIVMSG $chan :[::msgcat::mc "Oh oh, equality! We relaunch a voting phase"]"
               [namespace current]::resetVotes
            } else {
               putserv "PRIVMSG $chan :[::msgcat::mc "It's still a tie, there will be no casualties"]"
               if {[set [namespace current]::isNight] == 1} {
                  putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "By a happy coincidence, the wolves did not agree"]"
                  [namespace current]::itsDay
               } else {
                  [namespace current]::itsNight
               }
            }
         } else {
            set vict [[namespace current]::vict2nick $vict]
            putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Say goodbye to \002%1\$s\002" $vict]"
            [namespace current]::killVict $vict [set [namespace current]::isNight]
         }
      }
   }
   
   # Pick a free player. By default, only a citizen (no wolf)
   proc pickfreenick {{wolf 0}} {
      if {$wolf == 0} {
         set free [::utils::ldiff [set [namespace current]::players] [set [namespace current]::wolves] -nocase]
      } else {
         set free [set [namespace current]::players]
      }
      set free [::utils::ldiff $free [set [namespace current]::jobbers] -nocase]
      [namespace current]::dlog "*** FREENICK **** [join $free]"
      return [lindex $free [rand [llength $free]]]
   }

   proc vict2nick {vict} {
      set idv [lsearch -nocase [set [namespace current]::players] $vict]
      return [lindex [set [namespace current]::players] $idv]
   }
   
   proc killVict {nick night {quit 0}} {
      hook call job kill $nick $night
      set [namespace current]::players [::utils::lremove [set [namespace current]::players] $nick -nocase]
      set [namespace current]::wolves [::utils::lremove [set [namespace current]::wolves] $nick -nocase]
      hook call job postkill
      if {[llength [set [namespace current]::winner]]>0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "We have a winner: \00303%1\$s\003 !!!" [lindex [set [namespace current]::winner] 0]]"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[lindex [set [namespace current]::winner] 1]"
         [namespace current]::cleanGame
         return 0
      }
      if {[llength [set [namespace current]::wolves]]==0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "The \00303villagers\003 killed the last \00304wolf\003!!!"]"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "\002\00303Victory for the village!\003 Away with the wolves!\002"]"
         [namespace current]::cleanGame
         return 0
      } elseif {[llength [::utils::ldiff [set [namespace current]::players] [set [namespace current]::wolves] -nocase]]==0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "The \00304wolves\003 killed the last \00303villager\003!!!"]"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "\002\00304Defeat for the village!\003 Glory to bestiality!\002"]"
         [namespace current]::cleanGame
         return 0
      }
      if {$quit == 1} { return }
      if {$night == 1} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[::msgcat::mc "Wolves went after \002%1\$s\002, farewell :(" $nick]"
         [namespace current]::itsDay
      } else {
         [namespace current]::itsNight
      }
   }

   proc isAlive {nick} {
      if {[lsearch -nocase [set [namespace current]::players] $nick]==-1} {
         return 0
      } else {
         return 1
      }
   }

   proc isWolf {nick} {
      if {[lsearch -nocase [set [namespace current]::wolves] $nick]==-1} {
         return 0
      } else {
         return 1
      }
   }
   
   proc nickChange {nick uhost handle chan newnick} {
      set [namespace current]::players [::utils::lireplace [set [namespace current]::players] $nick $newnick]
      set [namespace current]::wolves [::utils::lireplace [set [namespace current]::wolves] $nick $newnick]
      set [namespace current]::jobbers [::utils::lireplace [set [namespace current]::jobbers] $nick $newnick]
   }
   bind nick - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickChange
   
   proc nickPart {nick uhost handle chan msg} {
      if {[set [namespace current]::preGame]==0 && [set [namespace current]::inGame]==0} {
         return
      }
      if {[set [namespace current]::preGame]==1} {
         set [namespace current]::players [::utils::lremove [set [namespace current]::players] $nick -nocase]
         return
      }
      if {[set [namespace current]::inGame]==1} {
         [namespace current]::killVict $nick 0 1
         return
      }
   }
   bind part - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickPart
   bind sign - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickPart
   
   bind pub - !rules [namespace current]::showrules
   proc showrules {nick uhost handle chan text} {
      if {$text eq "chan" && $handle ne "*"} {
         set target [set [namespace current]::conf(chanDay)]
      } else {
         set target $nick
      }
      # To do
   }
   
   # i18n part
   proc translate {msgfile {lang {}}} {
      putlog "$msgfile called for -${lang}-"
      if {$lang == ""} {set lang [string range [::msgcat::mclocale] 0 1] }
      if {[catch {open $msgfile r} fmsg]} {
         [namespace current]::dlog "*** KO *** Could not open $msgfile for reading\n$fmsg"
      } else {
         putlog "Loading $lang file from $msgfile"
         while {[gets $fmsg line] >= 0} {
            lappend ll $line
         }
         close $fmsg
         ::msgcat::mcmset $lang [join $ll]
         unset ll
      }
   }
   
   proc i18n {lang {bname ""}} {
      [namespace current]::dlog "# Loading $bname in $lang"
      if {$bname ne ""} {
         set bname "${bname}."
      }
      if {![catch {package require msgcat}]} {
         ::msgcat::mclocale en
         if {$lang != "" && [string tolower $lang] != "en"} {
            set lfile [set [namespace current]::rpath]/lycanobot/translations/${bname}$lang.msg
            if {[file exists $lfile]} {
               [namespace current]::dlog "*** OK *** Loaded $lfile"
               [namespace current]::translate $lfile $lang
            } else {
               [namespace current]::dlog "*** KO *** Can't find $lfile"
            }
            ::msgcat::mclocale $lang
            putlog "New language: [::msgcat::mc "english"]"
         }
      } else {
         namespace eval ::msgcat {
            proc mc {text {str ""} args} { return [format $text $str $args] }
         }
      }
   }
   
   proc getWinner {list1} {
      set unique [lsort -unique -nocase $list1]
      set tmp {}
      foreach l $unique {
         set score [llength [lsearch -all -inline -nocase $list1 $l]]
         lappend tmp $l $score
      }
      set tmp [lsort -stride 2 -index 1 -integer -decreasing $tmp]
      if {[lindex $tmp 3] == [lindex $tmp 1]} {
         return -1
      } else {
         return [lindex $tmp 0]
      }
   }
   
   proc dlog {data} {
      if {[set [namespace current]::debug] == 1} {
         set tchan [string range [set [namespace current]::conf(chanDay)] 1 end]
         set out [open "[set [namespace current]::conf(ofile)]${::botnick}.${tchan}.[clock format [clock seconds] -format "%Y%m%d"].log" a]
         puts $out "\[[clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]\] $data"
         close $out
      }
   }
   
   # Script initialisation
   source [set [namespace current]::rpath]/lycanobot/core/utils.tcl
   [namespace current]::inigame
}