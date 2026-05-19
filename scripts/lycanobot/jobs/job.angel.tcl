namespace eval angel {

	variable nick
	
	hook bind job start angel [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set [namespace current]::nick [[namespace parent]::pickfreenick]
      [namespace parent]::dlog ">>> got [set [namespace current]::nick] as Angel"
		lappend [namespace parent]::jobbers [set [namespace current]::nick]
		putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "You are the Angel: if you get killed the first day, you win."]"
	}

	hook bind job clean angel [namespace current]::clean
	proc clean {} {
		namespace forget [namespace current]
		putlog "Angel unloaded"
	}
	
	hook bind job newday angel [namespace current]::newday
	proc newday {day} {
		if {[info exists [namespace current]::nick] && $day == 1} {
			putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "Do not forget: if you are the victim on the day, you win."]"
		}
	}
	
	hook bind job kill angel [namespace current]::kill
	proc kill {nick night} {
      if {![info exists [namespace current]::nick]} {
         return
      }
		if {([set [namespace parent]::daycount]==1 || [set [namespace parent]::nightcount]==1) && [string tolower $nick] eq [string tolower [set [namespace current]::nick]]} {
			putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "You die, you win!"]"
			set [namespace parent]::winner [list $nick "[::msgcat::mc "You killed the Angel, he win the game."]"]
		} elseif {[set [namespace parent]::daycount]==1 && $night==0 && [string tolower $nick] ne [string tolower [set [namespace current]::nick]]} {
			putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "As Angel, you was not killed, you are now a simple citizen."]"
			set [namespace parent]::jobbers [::utils::lremove [set [namespace parent]::jobbers] $nick -nocase]
			unset [namespace current]::nick
		}
	}
	
   hook bind job nickChange angel [namespace current]::nickChange
   proc nickChange {nick newnick} {
      if {[info exists [namespace current]::nick] && [string tolower $nick] eq [string tolower [set [namespace current]::nick]]} {
         set [namespace current]::nick $newnick
      }
   }
   
	putlog "Job [namespace tail [namespace current]] loaded ([namespace current])"
}