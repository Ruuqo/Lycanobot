namespace eval angel {

	variable nick
	
	hook bind job start angel [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set [namespace current]::nick [[namespace parent]::pickfreenick]
      [namespace parent]::dlog ">>> [set [namespace current]::nick] recoit le role Ange"
		lappend [namespace parent]::jobbers [set [namespace current]::nick]
		putserv "PRIVMSG [set [namespace current]::nick] :Tu es l'Ange: si tu meurs lors de la premiere nuit ou du premier jour, tu gagnes seul."
	}

	hook bind job clean angel [namespace current]::clean
	proc clean {} {
		catch {unset [namespace current]::nick}
		putlog "Role Ange decharge"
	}
	
	hook bind job newday angel [namespace current]::newday
	proc newday {day} {
		if {[info exists [namespace current]::nick] && $day == 1} {
			putserv "PRIVMSG [set [namespace current]::nick] :N'oublie pas: si le village te condamne aujourd'hui, tu gagnes."
		}
	}
	
	hook bind job kill angel [namespace current]::kill
	proc kill {nick night} {
      if {![info exists [namespace current]::nick]} {
         return
      }
		if {([set [namespace parent]::daycount]==1 || [set [namespace parent]::nightcount]==1) && [string tolower $nick] eq [string tolower [set [namespace current]::nick]]} {
			putserv "PRIVMSG [set [namespace current]::nick] :Tu meurs au bon moment: tu remportes la partie."
			set [namespace parent]::winner [list $nick "L'Ange a ete tue trop tot: il remporte la partie."]
		} elseif {[set [namespace parent]::daycount]==1 && $night==0 && [string tolower $nick] ne [string tolower [set [namespace current]::nick]]} {
			putserv "PRIVMSG [set [namespace current]::nick] :Tu n'as pas ete sacrifie a temps: tu redeviens simple villageois."
			set [namespace parent]::jobbers [::utils::lremove [set [namespace parent]::jobbers] [set [namespace current]::nick] -nocase]
			unset [namespace current]::nick
		}
	}
	
   hook bind job nickChange angel [namespace current]::nickChange
   proc nickChange {nick newnick} {
      if {[info exists [namespace current]::nick] && [string tolower $nick] eq [string tolower [set [namespace current]::nick]]} {
         set [namespace current]::nick $newnick
      }
   }
   
	putlog "Role [namespace tail [namespace current]] charge ([namespace current])"
}
