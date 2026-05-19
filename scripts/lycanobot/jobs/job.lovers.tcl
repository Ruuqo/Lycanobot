namespace eval lovers {

	variable nicks [list]
	
	set msg(fate) "Ton destin est lie a celui de %s. Votre but est de survivre ensemble."
	
	hook bind job start lovers [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set lover1 [[namespace parent]::pickfreenick 1]
      lappend [namespace parent]::jobbers $lover1
		set lover2 [[namespace parent]::pickfreenick 1]
      lappend [namespace parent]::jobbers $lover2
      set [namespace current]::nicks [list $lover1 $lover2]
      [namespace parent]::dlog "--> Amoureux: [join [set [namespace current]::nicks]]"
		putserv "PRIVMSG $lover1 :[format [set [namespace current]::msg(fate)] $lover2]"
		putserv "PRIVMSG $lover2 :[format [set [namespace current]::msg(fate)] $lover1]"
	}
	
	hook bind job clean lovers [namespace current]::clean
	proc clean {} {
		set [namespace current]::nicks [list]
		putlog "Role Amoureux decharge"
	}
	
	hook bind job kill lovers [namespace current]::kill
	proc kill {nick night} {
		if {[lsearch -nocase [set [namespace current]::nicks] $nick] != -1} {
			# La victime est l'un des amoureux.
			set [namespace current]::nicks [::utils::lremove [set [namespace current]::nicks] $nick -nocase]
			set stay [join [set [namespace current]::nicks]]
			putserv "PRIVMSG $nick :Tu viens de mourir; $stay te rejoint dans la tombe."
			putserv "PRIVMSG $stay :$nick est mort: ton coeur se brise, tu le suis dans la mort."
			set [namespace parent]::players [::utils::lremove [set [namespace parent]::players] $stay -nocase]
			set [namespace parent]::wolves [::utils::lremove [set [namespace parent]::wolves] $stay -nocase]
			if {[lsearch -nocase [set [namespace parent]::deadPlayers] $stay] == -1} {
				lappend [namespace parent]::deadPlayers $stay
			}
			catch {pushmode [set [namespace parent]::conf(chanDay)] -v $stay}
			if {[info exists [namespace parent]::curNight] && [set [namespace parent]::curNight] ne ""} {
				catch {pushmode [set [namespace parent]::curNight] -v $stay}
			}
			putserv "PRIVMSG [set [namespace parent]::conf(chanDay)] :$stay ne peut vivre sans $nick et meurt de chagrin."
			set [namespace current]::nicks [list]
		}
	}
	
	hook bind job postkill lovers [namespace current]::postkill
	proc postkill {} {
		if {[llength [set [namespace parent]::wolves]]==0 || [llength [::utils::ldiff [set [namespace parent]::players] [set [namespace parent]::wolves] -nocase]]==0} {
			# Victoire normale: rien a faire.
			return
		}
		if {[llength [set [namespace current]::nicks]]==2 && [llength [set [namespace parent]::players]]==2} {
			# Deux survivants amoureux: ils gagnent ensemble.
			set [namespace parent]::winner [lappend [namespace current]::nicks "Les amoureux sont les seuls survivants. L'amour triomphe de la malediction."]
		}
	}
	
   hook bind job nickChange lovers [namespace current]::nickChange
   proc nickChange {nick newnick} {
      set [namespace current]::nicks [::utils::lireplace [set [namespace current]::nicks] $nick $newnick]
   }
   
	putlog "Role Amoureux charge ([namespace current])"
}
