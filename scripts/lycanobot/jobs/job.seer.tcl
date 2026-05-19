namespace eval seer {

	variable nick
   variable tries
   variable timerName "role_seer_timeout"
	
	hook bind job start seer [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set [namespace current]::nick [[namespace parent]::pickfreenick]
      [namespace parent]::dlog ">>> [set [namespace current]::nick] recoit le role Voyante"
		lappend [namespace parent]::jobbers [set [namespace current]::nick]
		putserv "PRIVMSG [set [namespace current]::nick] :Tu es la Voyante: chaque nuit, tu peux sonder l'ame d'un joueur."
      putserv "PRIVMSG [set [namespace current]::nick] :Agis avant que les loups ne choisissent leur victime."
	}
	
   hook bind job newnight seer [namespace current]::newnight
   proc newnight {night} {
      if {![info exists [namespace current]::nick]} { return }
      if {[[namespace parent]::isAlive [set [namespace current]::nick]]} {
         set [namespace current]::tries 0
         set targets [[namespace parent]::aliveList [set [namespace current]::nick]]
         putquick "PRIVMSG [set [namespace current]::nick] :Tape \002[[namespace parent]::primaryCommand cmdSeerCheck] <joueur>\002 ici pour savoir si ce joueur est loup-garou."
         putquick "PRIVMSG [set [namespace current]::nick] :Tu peux aussi taper \002[[namespace parent]::primaryCommand cmdRolePass]\002 pour ne rien faire cette nuit."
         putquick "PRIVMSG [set [namespace current]::nick] :Joueurs que tu peux sonder: $targets."
         foreach cmd [[namespace parent]::commandAliases cmdSeerCheck] {
            bind msgm - "*$cmd*" [namespace current]::whois
         }
         foreach cmd [[namespace parent]::commandAliases cmdRolePass] {
            bind msgm - "*$cmd*" [namespace current]::pass
         }
         [namespace parent]::registerGameTimer [set [namespace parent]::conf(roleTimeout)] [list [namespace current]::timeout $night] [set [namespace current]::timerName]
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

   proc timeout {night} {
      if {![info exists [namespace current]::tries] || [set [namespace current]::tries] == 0} {
         set [namespace current]::tries 1
         if {[info exists [namespace current]::nick] && [[namespace parent]::isAlive [set [namespace current]::nick]]} {
            putserv "PRIVMSG [set [namespace current]::nick] :Le temps est ecoule, tu passes ton tour."
         }
      }
      [namespace current]::cleanBinds
   }
   
   proc pass {nick uhost handle text} {
      set text [stripcodes * $text]
      if {![string match -nocase $nick [set [namespace current]::nick]]} {
         putserv "PRIVMSG $nick :Tu n'es pas la Voyante."
         return
      }
      lassign [split $text] cmd
      if {[[namespace current]::matchesCommand cmdRolePass $cmd]} {
         set [namespace current]::tries 1
         [namespace parent]::killTimerByName [set [namespace current]::timerName]
         putserv "PRIVMSG $nick :C'est note, tu passes cette nuit."
         [namespace current]::cleanBinds
      }
   }
   
   proc whois {nick uhost handle text} {
      set text [stripcodes * $text]
      if {![string match -nocase $nick [set [namespace current]::nick]]} {
         putserv "PRIVMSG $nick :Tu n'es pas la Voyante."
         return
      }
      lassign [split $text] cmd vnick
      if {![[namespace current]::matchesCommand cmdSeerCheck $cmd] || ($vnick eq "")} {
         putquick "PRIVMSG $nick :Je n'ai pas compris. Tape \002[[namespace parent]::primaryCommand cmdSeerCheck] <joueur>\002."
         return
      }
      if {[info exists [namespace current]::tries] && [set [namespace current]::tries] > 0} {
         putserv "PRIVMSG $nick :Tu as deja utilise ton don cette nuit."
         return
      }
      set [namespace current]::tries 1
      [namespace parent]::killTimerByName [set [namespace current]::timerName]
      if {![[namespace parent]::isAlive $vnick]} {
         putserv "PRIVMSG $nick :$vnick est mort ou ne joue pas. Ton pouvoir est tout de meme consomme."
         [namespace current]::cleanBinds
         return
      }
      if {![[namespace parent]::isWolf $vnick]} {
         putserv "PRIVMSG $nick :La vision est claire: \00303$vnick\003 n'est pas loup-garou."
      } else {
         putserv "PRIVMSG $nick :La vision se trouble: \00304$vnick\003 est loup-garou."
      }
      [namespace current]::cleanBinds
   }
   
   hook bind job nickChange seer [namespace current]::nickChange
   proc nickChange {nick newnick} {
      if {[string match -nocase $nick [set [namespace current]::nick]]} {
         set [namespace current]::nick $newnick
      }
   }
   
   hook bind job clean seer [namespace current]::clean
   proc clean {} {
      catch {unset [namespace current]::nick}
      catch {unset [namespace current]::tries}
      [namespace current]::cleanBinds
   }
   
   proc cleanBinds {} {
      [namespace parent]::killTimerByName [set [namespace current]::timerName]
      foreach b [binds "[namespace current]*"] {
         lassign $b t f k n c
         unbind $t $f $k $c
      }
   }

   proc matchesCommand {key cmd} {
      foreach alias [[namespace parent]::commandAliases $key] {
         if {[string equal -nocase $cmd $alias]} {
            return 1
         }
      }
      return 0
   }
}
