namespace eval seer {

	variable nick
   variable tries
	
	hook bind job start seer [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set [namespace current]::nick [[namespace parent]::pickfreenick]
      [namespace parent]::dlog ">>> got [set [namespace current]::nick] as Seer"
		lappend [namespace parent]::jobbers [set [namespace current]::nick]
		putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "You are the Seer: each night, you can reveal the real identity of a player."]"
      putserv "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "Think to do this each night before the werewolves kill someone..."]"
	}
	
	hook bind job newnight seer [namespace current]::newnight
	proc newnight {night} {
      if {[[namespace parent]::isAlive [set [namespace current]::nick]]} {
         set [namespace current]::tries 0
         putquick "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "Type \002%1\$s \00303player\003\002 in this window to know if \00303player\003 is a werewolf or not" [::msgcat::mc "!whois"]]"
         putquick "PRIVMSG [set [namespace current]::nick] :[::msgcat::mc "Or use \002%1\$s\002 to pass for this night" [::msgcat::mc "!pass"]]"
         bind msgm - "*[::msgcat::mc "!whois"]*" [namespace current]::whois
         bind msgm - "*[::msgcat::mc "!pass"]*" [namespace current]::pass
      }
	}

   hook bind job kill seer [namespace current]::kill
   proc kill {nick night} {
      [namespace current]::cleanBinds
   }

   hook bind job newday seer [namespace current]::newday
   proc newday {day} {
      [namespace current]::cleanBinds
   }
   
   proc pass {nick uhost handle text} {
      set text [stripcodes * $text]
      if {![string match -nocase $nick [set [namespace current]::nick]]} {
         putserv "PRIVMSG $nick :[msgcat::mc "Well, you don't seem to be the Seer."]"
         return
      }
      lassign [split $text] cmd
      if {[string match -nocase $cmd [::msgcat::mc "!pass"]]} {
         set [namespace current]::tries 1
         putserv "PRIVMSG $nick :[msgcat::mc "Ok, it's recorded"]"
      }
   }
   
   proc whois {nick uhost handle text} {
      set text [stripcodes * $text]
      if {![string match -nocase $nick [set [namespace current]::nick]]} {
         putserv "PRIVMSG $nick :[msgcat::mc "Well, you don't seem to be the Seer."]"
         return
      }
      lassign [split $text] cmd vnick
      if {(![string match -nocase $cmd [::msgcat::mc "!whois"]]) || ($vnick eq "")} {
         putquick "PRIVMSG $nick :[::msgcat::mc "Sorry, I didn't understand. Type \002%1\$s \00303player\003\002" [::msgcat::mc "!whois"]]"
         return
      }
      if {[info exists [namespace current]::tries] && [set [namespace current]::tries] > 0} {
         putserv "PRIVMSG $nick :[::msgcat::mc "You already reveal someone this night, don't cheat please"]"
         return
      }
      set [namespace current]::tries 1
      if {![[namespace parent]::isAlive $vnick]} {
         putserv "PRIVMSG $nick :[msgcat::mc "Well... %1\$s is dead or not a player, you've lost a trick." $vnick]"
         return
      }
      if {![[namespace parent]::isWolf $vnick]} {
         putserv "PRIVMSG $nick :[::msgcat::mc "Good news: \00303%1\$s\003 is a villager, you can trust him." $vnick]"
      } else {
         putserv "PRIVMSG $nick :[::msgcat::mc "Oh oh... \00304%1\$s\003 is a werewolf, beware of him." $vnick]"
      }
   }
   
   hook bind job nickChange seer [namespace current]::nickChange
   proc nickChange {nick newnick} {
      if {[string match -nocase $nick [set [namespace current]::nick]]} {
         set [namespace current]::nick $newnick
      }
   }
   
   hook bind job clean seer [namespace current]::clean
   proc clean {} {
      unset [namespace current]::nick
      [namespace current]::cleanBinds
   }
   
   proc cleanBinds {} {
      foreach b [binds "[namespace current]*"] {
         lassign $b t f k n c
         unbind $t $f $k $c
      }
   }
}
