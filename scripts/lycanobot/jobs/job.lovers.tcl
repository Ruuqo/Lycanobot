namespace eval lovers {

	variable nicks [list]
	
	set msg(fate) "Your fate is tied to that of %1\$s. Your goal is to survive together."
	
	hook bind job start lovers [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set lover1 [[namespace parent]::pickfreenick 1]
      lappend [namespace parent]::jobbers $lover1
		set lover2 [[namespace parent]::pickfreenick 1]
      lappend [namespace parent]::jobbers $lover2
      set [namespace current]::nicks [list $lover1 $lover2]
      [namespace parent]::dlog "--> Lovers are [join [set [namespace current]::nicks]]"
		set [namespace parent]::jobbers [concat [set [namespace parent]::jobbers] [set [namespace current]::nicks]]
		putserv "PRIVMSG $lover1 :[::msgcat::mc [set [namespace current]::msg(fate)] $lover2]"
		putserv "PRIVMSG $lover2 :[::msgcat::mc [set [namespace current]::msg(fate)] $lover1]"
	}
	
	hook bind job clean lovers [namespace current]::clean
	proc clean {} {
		namespace forget [namespace current]
		putlog "Lovers unloaded"
	}
	
	hook bind job kill lovers [namespace current]::kill
	proc kill {nick night} {
		if {[lsearch -nocase [set [namespace current]::nicks] $nick] != -1} {
			# Victim is one of the lovers
			set [namespace current]::nicks [::utils::lreplace [set [namespace current]::nicks] $nick -nocase]
			set stay [join [set [namespace current]::nicks]]
			putserv "PRIVMSG $nick :[::msgcat::mc "You have just been killed, %1\$s decides to join you in death." $stay]"
			putserv "PRIVMSG $stay :[::msgcat::mc "%1\$s is dead, you kill yourself." $nick]"
			set [namespace parent]::players [::utils::lremove [set [namespace parent]::players] $stay -nocase]
			set [namespace parent]::wolves [::utils::lreplace [set [namespace parent]::wolves] $stay -nocase]
			putserv "PRIVMSG [set [namespace parent]::conf(chanDay)] :[::msgcat::mc "%1\$s cannot live without %2\$s and commits suicide." $stay $nick]"
			set [namespace current]::nicks [list]
		}
	}
	
	hook bind job postkill lovers [namespace current]::postkill
	proc postkill {} {
		if {[llength [set [namespace parent]::wolves]]==0 || [llength [::utils::ldiff [set [namespace parent]::players] [set [namespace parent]::wolves] -nocase]]==0} {
			# normal victory occures, do nothing
			return
		}
		if {[llength [set [namespace current]::nicks]]==2 && [llength [set [namespace parent]::players]==2]} {
			# 2 players, 2 lovers, they win
			set [namespace parent]::winner [lappend [namespace current]::nicks [::msgcat::mc "The lovers are the only survivors! Love is stronger than anything."]]
		}
	}
	
   hook bind job nickChange angel [namespace current]::nickChange
   proc nickChange {nick newnick} {
      set [namespace current]::nicks [::utils::lireplace [set [namespace current]::nicks] $nick $newnick]
   }
   
	putlog "lovers.job loaded ([namespace current])"
}
