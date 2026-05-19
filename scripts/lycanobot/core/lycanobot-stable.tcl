# Do not edit anything below !
namespace eval ::lycanobot {
   # package require json
   
   variable curNight
   variable inGame 0
   variable preGame 0
   variable players {}
   variable deadPlayers {}
   variable wolves {}
   variable temp
   variable voters {}
   variable gameIni
   variable jobbers {}
   variable winner {}
   variable isNight 0
   variable phase "idle"
   variable gameBans {}
   variable gameTimers {}
   variable compositionLast 0
   variable narration
   
   variable scriptname "LycanoBot"
   variable scriptversion 1.0.1
   
   if {[catch {package require hook}]} {
      putlog "ATTENTION : le paquet hook est requis. Le jeu tournera en version minimale."
   }

   if {[llength [info commands ::hook::bind]] == 0} {
      namespace eval ::hook {
         variable hooks
         proc bind {group event name callback} {
            variable hooks
            lappend hooks($group,$event) [list $name $callback]
         }
         proc call {group event args} {
            variable hooks
            if {![info exists hooks($group,$event)]} { return }
            foreach entry $hooks($group,$event) {
               set callback [lindex $entry 1]
               catch {uplevel #0 [list $callback {*}$args]} err
            }
         }
         proc forget {group} {
            variable hooks
            foreach key [array names hooks "$group,*"] {
               unset hooks($key)
            }
         }
      }
   }

   if {[llength [info commands ::hook]] == 0} {
      proc ::hook {subcmd args} {
         set cmd ::hook::$subcmd
         if {[llength [info commands $cmd]] == 0} {
            return -code error "sous-commande hook inconnue: $subcmd"
         }
         return [$cmd {*}$args]
      }
   }
   
   if {[catch {package require json}]} {
      putlog "ATTENTION : paquet json introuvable, utilisation du parseur de secours."
      namespace eval ::json {
         proc json2dict {JSONtext} {
            string range [string trim [string trimleft [string map {\t {} \n {} \r {} , { } : { } \[ \{ \] \}} $JSONtext] {\uFEFF}]] 1 end-1
         }
      }
   }

   proc configDefault {key value} {
      if {![info exists [namespace current]::conf($key)]} {
         set [namespace current]::conf($key) $value
      }
   }

   proc initV2Config {} {
      [namespace current]::configDefault admins ""
      [namespace current]::configDefault gameBans ""
      [namespace current]::configDefault roleTimeout 2
      [namespace current]::configDefault compositionCooldown 60
      [namespace current]::configDefault requireWolvesOp 1
      [namespace current]::configDefault requireMainOp 1
      [namespace current]::configDefault cleanLegacyNightChannels 1
      [namespace current]::configDefault legacyNightChannelPattern ""
      [namespace current]::configDefault cmdStart "!partie !start !game"
      [namespace current]::configDefault cmdJoin "!jouer !play !join"
      [namespace current]::configDefault cmdComplete "!complet"
      [namespace current]::configDefault cmdCancel "!annuler !stop !reset"
      [namespace current]::configDefault cmdComposition "!composition !compo"
      [namespace current]::configDefault cmdForceJoin "!forcerjoin"
      [namespace current]::configDefault cmdForceQuit "!forcerquit"
      [namespace current]::configDefault cmdBanGame "!banjeu"
      [namespace current]::configDefault cmdUnbanGame "!unbanjeu"
      [namespace current]::configDefault cmdBanListGame "!banlistjeu"
      [namespace current]::configDefault cmdStatus "!status"
      [namespace current]::configDefault cmdRoles "!roles"
      [namespace current]::configDefault cmdRules "!regles !rules"
      [namespace current]::configDefault cmdLegacyAdd "!add"
      [namespace current]::configDefault cmdVote "!vote"
      [namespace current]::configDefault cmdSeerCheck "!qui"
      [namespace current]::configDefault cmdRolePass "!passe"
      # Le salon des loups est fixe en V2. Ancienne cle gardee par compatibilite.
      set [namespace current]::conf(chanRand) 0
      set [namespace current]::gameBans [split [set [namespace current]::conf(gameBans)]]
   }

   proc cleanupLegacyNightChannels {} {
      if {![set [namespace current]::conf(cleanLegacyNightChannels)]} {
         return
      }
      set fixed [string tolower [set [namespace current]::conf(chanNight)]]
      set pattern [set [namespace current]::conf(legacyNightChannelPattern)]
      if {$pattern eq ""} {
         set pattern "[set [namespace current]::conf(chanNight)]_*"
      }
      foreach chan [channels] {
         if {[string tolower $chan] eq $fixed} {
            continue
         }
         if {[string match -nocase $pattern $chan]} {
            [namespace current]::dlog "--> Suppression de l'ancien salon loup persistant: $chan"
            catch {channel remove $chan}
         }
      }
   }

   proc cleanupWolvesChannel {} {
      set chans [list [set [namespace current]::conf(chanNight)]]
      if {[info exists [namespace current]::curNight] && [set [namespace current]::curNight] ne ""} {
         lappend chans [set [namespace current]::curNight]
      }
      foreach chan [lsort -unique -nocase $chans] {
         catch {unbind join - "$chan *" [namespace current]::wolfInChannel}
         if {![validchan $chan] || ![botonchan $chan]} {
            continue
         }
         [namespace current]::dlog "<-- Nettoyage de la taniere $chan"
         foreach nick [chanlist $chan] {
            if {[isbotnick $nick]} {
               continue
            }
            catch {pushmode $chan -v $nick}
            if {[catch {putkick $chan $nick "La partie est terminee. La taniere se referme."} err]} {
               [namespace current]::dlog "*** ATTENTION *** Kick impossible sur $chan pour $nick: $err"
            }
         }
      }
   }

   proc initNarration {} {
      variable narration
      array set narration {
         wait_start {
            "La place du village s'anime: inscriptions ouvertes pendant %s minutes. Tapez \002%s\002 pour entrer dans la ronde."
            "Le crieur sonne la cloche: il reste %s minutes pour rejoindre avec \002%s\002."
            "Les torches s'allument autour de la halle. Fin des inscriptions dans %s minutes; tapez \002%s\002 pour jouer."
         }
         wait_half {
            "Plus que %s minutes pour rejoindre la partie avec \002%s\002."
            "Le sablier descend: encore %s minutes pour s'inscrire avec \002%s\002."
            "Dernier appel proche: %s minutes restantes pour entrer au village avec \002%s\002."
         }
         wait_one {
            "Plus qu'une minute pour rejoindre avec \002%s\002."
            "La cloche sonnera dans une minute: \002%s\002 pour les retardataires."
            "Une derniere minute avant la fermeture des portes: \002%s\002."
         }
         game_prepare {
            "La partie commence. Je prepare les cartes et les destins."
            "Le village retient son souffle: les roles sont distribues."
            "Les ombres se placent. Je prepare les camps."
         }
         wolves_chosen {
            "Les loups ont ete designes. Que le village prenne garde."
            "La malediction a choisi ses crocs cette nuit."
            "Des regards changent dans la foule: les loups connaissent leur meute."
         }
         intro_night {
            "Chaque nuit, Thiercelieux risque de perdre l'un des siens."
            "Quand la lune monte, les betes cherchent une proie."
            "Sous les toits sombres, les loups guettent les imprudents."
         }
         intro_day {
            "Au matin, les villageois devront demasquer les monstres."
            "Le jour venu, la parole du village deviendra une arme."
            "Quand l'aube reviendra, il faudra accuser, convaincre et voter."
         }
         night_start {
            "La nuit tombe, les villageois ferment leurs volets."
            "Le clocher se tait: Thiercelieux s'endort."
            "Les lanternes s'eteignent une a une. La nuit commence."
         }
         wolves_wake {
            "Loups-garous, ouvrez les yeux."
            "La meute s'eveille dans la taniere."
            "Les crocs sortent de l'ombre: aux loups de parler."
         }
         wolves_vote {
            "Choisissez votre victime avec \002%s <victime>\002."
            "Debattez entre vous, puis designez une proie avec \002%s <victime>\002."
            "La taniere murmure: votez avec \002%s <victime>\002."
         }
         day_start {
            "Le jour se leve, et le village compte ses survivants."
            "L'aube perce enfin; les portes s'ouvrent avec prudence."
            "Les coqs chantent sur un village inquiet."
         }
         day_vote {
            "Debattez, puis designez un suspect avec \002%s <pseudo>\002."
            "La justice du village attend vos voix: \002%s <pseudo>\002."
            "Cherchez le loup cache parmi vous, puis votez avec \002%s <pseudo>\002."
         }
         wolves_sleep {
            "Les loups regagnent le village, museau bas et sourire cache."
            "La meute se disperse avant l'aube."
            "Les ombres quittent la taniere et reprennent visage humain."
         }
         all_voted {
            "Toutes les voix sont tombees. Le verdict approche..."
            "Le vote est clos. Le village retient son souffle..."
            "Plus personne ne parle: le compte des voix commence..."
         }
         vote_tie_retry {
            "Egalite au conseil. Le village doit revoter."
            "Les voix se partagent; nul ne tombe encore. On reprend le vote."
            "La foule hesite. Un nouveau tour de vote est necessaire."
         }
         vote_tie_none {
            "Nouvelle egalite. Personne ne sera livre au gibet."
            "Le conseil s'enlise: aucune victime aujourd'hui."
            "Les voix restent partagees. Le village epargne tout le monde cette fois."
         }
         wolves_tie_none {
            "Par miracle, les loups ne se sont pas accordes."
            "La taniere s'est disputee; aucune proie ne tombe."
            "Les crocs ont hesite, et le village respire encore."
         }
         verdict {
            "Que chacun fasse ses adieux a \002%s\002."
            "\002%s\002 est designe par le destin du village."
            "Le nom tombe comme une sentence: \002%s\002."
         }
         night_death {
            "Les loups se sont jetes sur \002%s\002. Que son nom reste dans les memoires."
            "A l'aube, on retrouve \002%s\002 marque par les crocs."
            "\002%s\002 n'a pas survecu a la nuit."
         }
         village_win {
            "\002\00303Victoire du village !\003 Les derniers hurlements s'eteignent.\002"
            "\002\00303Le village triomphe !\003 Les loups ne hanteront plus ces rues.\002"
            "\002\00303Thiercelieux est sauve !\003 Les villageois repoussent la malediction.\002"
         }
         wolves_win {
            "\002\00304Defaite du village !\003 Les loups regnent sur Thiercelieux.\002"
            "\002\00304La meute l'emporte !\003 Les dernieres lanternes s'eteignent.\002"
            "\002\00304Les loups gagnent !\003 Le village tombe dans leurs griffes.\002"
         }
         game_over {
            "La partie s'acheve. Une nouvelle chasse pourra commencer avec \002%s\002."
            "Le village se disperse. Pour rouvrir les portes: \002%s\002."
            "La chronique se referme pour l'instant. Relance possible avec \002%s\002."
         }
         cancel {
            "La partie est annulee. Le village reprend son souffle."
            "La cloche sonne la fin de l'assemblee: partie annulee."
            "Les torches sont eteintes avant le drame. Partie annulee."
         }
      }
   }

   proc narrate {target key args} {
      variable narration
      if {[info exists narration($key)]} {
         set variants $narration($key)
         set msg [lindex $variants [rand [llength $variants]]]
      } else {
         set msg $key
      }
      if {[llength $args] > 0} {
         set msg [format $msg {*}$args]
      }
      putserv "PRIVMSG $target :$msg"
   }

   proc listHas {items needle} {
      return [expr {[lsearch -nocase $items $needle] != -1}]
   }

   proc bindPubAliases {aliases flags callback} {
      set done {}
      foreach cmd $aliases {
         set cmd [string trim $cmd]
         if {$cmd eq "" || [[namespace current]::listHas $done $cmd]} { continue }
         catch {unbind pub $flags $cmd $callback}
         bind pub $flags $cmd $callback
         lappend done $cmd
      }
   }

   proc unbindPubAliases {aliases flags callback} {
      set done {}
      foreach cmd $aliases {
         set cmd [string trim $cmd]
         if {$cmd eq "" || [[namespace current]::listHas $done $cmd]} { continue }
         catch {unbind pub $flags $cmd $callback}
         lappend done $cmd
      }
   }

   proc startAliases {} {
      return [split [set [namespace current]::conf(cmdStart)]]
   }

   proc joinAliases {} {
      return [split [set [namespace current]::conf(cmdJoin)]]
   }

   proc completeAliases {} {
      return [split [set [namespace current]::conf(cmdComplete)]]
   }

   proc cancelAliases {} {
      return [split [set [namespace current]::conf(cmdCancel)]]
   }

   proc compositionAliases {} {
      return [split [set [namespace current]::conf(cmdComposition)]]
   }

   proc commandAliases {key} {
      return [split [set [namespace current]::conf($key)]]
   }

   proc primaryCommand {key} {
      return [lindex [[namespace current]::commandAliases $key] 0]
   }

   proc bindVoteCommand {} {
      set done {}
      foreach cmd [[namespace current]::commandAliases cmdVote] {
         set cmd [string trim $cmd]
         if {$cmd eq "" || [[namespace current]::listHas $done $cmd]} { continue }
         catch {unbind pubm - "*$cmd*" [namespace current]::pubmVote}
         bind pubm - "*$cmd*" [namespace current]::pubmVote
         lappend done $cmd
      }
   }

   proc unbindVoteCommand {} {
      set done {}
      foreach cmd [[namespace current]::commandAliases cmdVote] {
         set cmd [string trim $cmd]
         if {$cmd eq "" || [[namespace current]::listHas $done $cmd]} { continue }
         catch {unbind pubm - "*$cmd*" [namespace current]::pubmVote}
         lappend done $cmd
      }
   }

   proc bindPregameCommands {} {
      [namespace current]::bindPubAliases [[namespace current]::joinAliases] - [namespace current]::addPlayer
      [namespace current]::bindPubAliases [[namespace current]::completeAliases] - [namespace current]::endWaitingManu
   }

   proc unbindPregameCommands {} {
      [namespace current]::unbindPubAliases [[namespace current]::joinAliases] - [namespace current]::addPlayer
      [namespace current]::unbindPubAliases [[namespace current]::completeAliases] - [namespace current]::endWaitingManu
      [namespace current]::unbindPubAliases [[namespace current]::commandAliases cmdLegacyAdd] n [namespace current]::forceAdd
   }

   proc isGameAdmin {nick handle} {
      if {$handle ne "*" && ![catch {matchattr $handle n} ok] && $ok} {
         return 1
      }
      set admins [split [set [namespace current]::conf(admins)]]
      return [expr {[[namespace current]::listHas $admins $nick] || ($handle ne "*" && [[namespace current]::listHas $admins $handle])}]
   }

   proc isChannelOperator {nick chan} {
      if {[catch {isop $nick $chan} op]} { set op 0 }
      if {[catch {ishalfop $nick $chan} halfop]} { set halfop 0 }
      if {[catch {ischanadmin $nick $chan} chanadmin]} { set chanadmin 0 }
      if {[catch {isowner $nick $chan} owner]} { set owner 0 }
      return [expr {$op || $halfop || $chanadmin || $owner}]
   }

   proc botCanModerateChannel {chan} {
      if {[catch {botisop $chan} op]} { set op 0 }
      if {[catch {botishalfop $chan} halfop]} { set halfop 0 }
      return [expr {$op || $halfop}]
   }

   proc canModerateGame {nick handle chan} {
      return [expr {[[namespace current]::isChannelOperator $nick $chan] || [[namespace current]::isGameAdmin $nick $handle]}]
   }

   proc requireModerator {nick handle chan} {
      if {[[namespace current]::canModerateGame $nick $handle $chan]} { return 1 }
      putserv "PRIVMSG $chan :Commande reservee aux operateurs du salon ou aux admins du jeu."
      return 0
   }

   proc isGameBanned {nick} {
      return [[namespace current]::listHas [set [namespace current]::gameBans] $nick]
   }

   proc killTimerByName {name} {
      foreach t [timers] {
         if {[lindex $t 2] eq $name} {
            killtimer $name
         }
      }
   }

   proc registerGameTimer {minutes command name} {
      [namespace current]::killTimerByName $name
      timer $minutes $command 1 $name
      if {![[namespace current]::listHas [set [namespace current]::gameTimers] $name]} {
         lappend [namespace current]::gameTimers $name
      }
   }

   proc cleanupGameTimers {} {
      foreach t [concat [list "ltend" "lthalf" "ltone"] [set [namespace current]::gameTimers]] {
         [namespace current]::killTimerByName $t
      }
      set [namespace current]::gameTimers {}
   }

   proc ensureGameChannels {chan} {
      set day [set [namespace current]::conf(chanDay)]
      set night [set [namespace current]::conf(chanNight)]
      if {![validchan $day] || ![botonchan $day]} {
         putserv "PRIVMSG $chan :Je ne suis pas present sur le salon public $day."
         return 0
      }
      if {![validchan $night] || ![botonchan $night]} {
         putserv "PRIVMSG $chan :La taniere $night est indisponible. Partie refusee."
         return 0
      }
      if {[set [namespace current]::conf(requireMainOp)] && ![[namespace current]::botCanModerateChannel $day]} {
         putserv "PRIVMSG $chan :Je dois etre op ou halfop sur $day pour gerer le village."
         return 0
      }
      if {[set [namespace current]::conf(requireWolvesOp)] && ![[namespace current]::botCanModerateChannel $night]} {
         putserv "PRIVMSG $chan :Je dois etre op ou halfop sur $night pour gerer les loups."
         return 0
      }
      return 1
   }

   proc loadGameSettings {{conf ""}} {
      if {$conf eq ""} {
         set conf [set [namespace current]::conf(mode)]
      }
      if {[catch {set fi [open [set [namespace current]::rpath]/lycanobot/lycanobot.json r]}]} {
         return -code error "Impossible de trouver [set [namespace current]::rpath]/lycanobot/lycanobot.json"
      }
      set raw [read -nonewline $fi]
      close $fi
      if {[catch {set settings [::json::json2dict $raw]}]} {
         return -code error "Le fichier lycanobot.json n'est pas dans un format valide"
      }
      if {![dict exists $settings $conf]} {
         return -code error "$conf n'est pas un type de partie disponible"
      }
      return [dict get $settings $conf]
   }

   proc countWolvesFor {nbplayers wolvesConf} {
      set nbv 0
      if {![catch {dict keys $wolvesConf} ranges]} {
         foreach rng $ranges {
            regexp {(\d{1,})?(-)?(\d{1,})?} $rng - min sig max
            if {![info exists min] || $min eq ""} { set min 0 }
            if {![info exists max] || $max eq ""} { set max 999 }
            if {$nbplayers >= $min && $nbplayers <= $max} {
               set v [dict get $wolvesConf $rng]
               if {[string is double -strict $v] && ![string is integer -strict $v] && $v<1.0} {
                  set nbv [expr {int(floor($nbplayers * $v))}]
               } elseif {[string is integer -strict $v]} {
                  set nbv $v
               }
               break
            }
         }
      }
      if {$nbv == 0} {
         if {[string is double -strict $wolvesConf] && ![string is integer -strict $wolvesConf] && $wolvesConf<1.0} {
            set nbv [expr {int(floor($nbplayers * $wolvesConf))}]
         } elseif {[string is integer -strict $wolvesConf]} {
            set nbv $wolvesConf
         } elseif {$nbplayers <= 10 } {
            set nbv 2
         } elseif { $nbplayers < 20 } {
            set nbv 3
         } else {
            set nbv [expr {int(floor($nbplayers * [set [namespace current]::conf(wolves)]))}]
         }
      }
      if {$nbv < 1} {
         set nbv 1
      }
      if {$nbplayers > 1 && $nbv >= $nbplayers} {
         set nbv [expr {$nbplayers - 1}]
      }
      return $nbv
   }

   proc compositionText {{public 0}} {
      if {[array exists [namespace current]::gameIni] && [info exists [namespace current]::gameIni(num_players)]} {
         set data [array get [namespace current]::gameIni]
      } else {
         set data [[namespace current]::loadGameSettings]
      }
      array set comp $data
      set nbplayers [llength [set [namespace current]::players]]
      if {$nbplayers == 0} {
         set nbplayers $comp(num_players)
      }
      set nbwolves [[namespace current]::countWolvesFor $nbplayers $comp(wolves)]
      set jobs {}
      if {[info exists comp(jobs)]} {
         foreach job [dict keys $comp(jobs)] {
            lappend jobs $job
         }
      }
      set roleText "aucun role special active"
      if {[llength $jobs] > 0} {
         set roleText [join $jobs {, }]
      }
      return "Composition prevue: minimum $comp(num_players) joueurs, $nbwolves loup(s) pour $nbplayers joueur(s), roles possibles: $roleText. Les attributions restent secretes."
   }
   
   # Unload all components
   proc unload {type} {
      # remove binds
      foreach b [binds "[namespace current]*"] {
         lassign $b t f k n c
         unbind $t $f $k $c
      }
      # remove timers
      [namespace current]::cleanupGameTimers
      # delete namespace
      namespace delete [namespace current]
   }
  
   proc inigame {} {
      [namespace current]::initV2Config
      [namespace current]::initNarration
      [namespace current]::dlog "Initialisation de la partie"
      [namespace current]::cleanupLegacyNightChannels
      if {![validchan [set [namespace current]::conf(chanDay)]]} {
         [namespace current]::dlog "--> Joining channel [set [namespace current]::conf(chanDay)]]"
         channel add [set [namespace current]::conf(chanDay)]
      }
      if {[set [namespace current]::conf(wait)] <= 2} {
         set [namespace current]::conf(wait) 2
      }
      [namespace current]::dlog "* Delai d'inscription: [set [namespace current]::conf(wait)]"
      [namespace current]::i18n [set [namespace current]::conf(lang)] [namespace tail [namespace current]]
      [namespace current]::dlog "[set [namespace current]::scriptname] [set [namespace current]::scriptversion] charge en [set [namespace current]::conf(lang)]"
      putlog "[set [namespace current]::scriptname] [set [namespace current]::scriptversion] charge en [set [namespace current]::conf(lang)]"
      set topic "[set [namespace current]::conf(topic)] - Demarrez une partie avec \002[[namespace current]::primaryCommand cmdStart]\002"
      if {[topic [set [namespace current]::conf(chanDay)]] ne $topic} {
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :$topic"
      }
      bind evnt - prerehash [namespace current]::unload
      bind evnt - prerestart [namespace current]::unload
      [namespace current]::bindPubAliases [[namespace current]::startAliases] - [namespace current]::startGame
      [namespace current]::bindPubAliases [[namespace current]::cancelAliases] - [namespace current]::cancelGame
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdForceJoin] - [namespace current]::forceJoin
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdForceQuit] - [namespace current]::forceQuit
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdBanGame] - [namespace current]::banGameUser
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdUnbanGame] - [namespace current]::unbanGameUser
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdBanListGame] - [namespace current]::showGameBanList
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdStatus] - [namespace current]::showStatus
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdRoles] - [namespace current]::showRoles
      [namespace current]::bindPubAliases [[namespace current]::compositionAliases] - [namespace current]::showComposition
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdRules] - [namespace current]::showrules
   }

   proc startGame {nick uhost handle chan args} {
      [namespace current]::dlog "--> Partie lancee par $nick"
      if { [string tolower $chan] != [string tolower [set [namespace current]::conf(chanDay)]]} {
         [namespace current]::dlog "*** KO *** Bad channel $chan"
         return 0
      }
      if {[set [namespace current]::preGame] == 1 || [set [namespace current]::inGame] == 1} {
         putserv "PRIVMSG $chan :Une partie est deja en attente ou en cours."
         return 0
      }
      if {[[namespace current]::isGameBanned $nick]} {
         putserv "PRIVMSG $chan :$nick, tu ne peux pas lancer de partie."
         return 0
      }
      if {[set [namespace current]::conf(requireMainOp)] && ![[namespace current]::botCanModerateChannel [set [namespace current]::conf(chanDay)]] } {
         [namespace current]::dlog "*** KO *** Droits IRC insuffisants pour le bot"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :Je dois etre op ou halfop sur [set [namespace current]::conf(chanDay)]."
         return 0
      }
      if {![[namespace current]::ensureGameChannels $chan]} {
         return 0
      }
      set conf [join [lindex [split $args] 0]]
      if {$conf == ""} {
         set conf [set [namespace current]::conf(mode)]
      } else {
         set conf [string tolower $conf]
      }
      [namespace current]::dlog "* Configuration de partie: $conf"
      if {[catch {set gameSettings [[namespace current]::loadGameSettings $conf]} err]} {
         [namespace current]::dlog "*** KO *** $err"
         putserv "PRIVMSG $chan :$err"
         return 0
      }
      array set [namespace current]::gameIni $gameSettings
      [namespace current]::registerGameTimer [set [namespace current]::conf(wait)] [list [namespace current]::endWaiting] ltend
      [namespace current]::dlog "* Waiting for players during [set [namespace current]::conf(wait)] minutes"
      set halfwait [expr [set [namespace current]::conf(wait)]/2]
      if { $halfwait > 1} {
         [namespace current]::registerGameTimer $halfwait [list [namespace current]::narrate [set [namespace current]::conf(chanDay)] wait_half $halfwait [[namespace current]::primaryCommand cmdJoin]] lthalf
         [namespace current]::dlog "* Advertising programmed in $halfwait minutes"
      }
      [namespace current]::registerGameTimer [expr [set [namespace current]::conf(wait)] - 1] [list [namespace current]::narrate [set [namespace current]::conf(chanDay)] wait_one [[namespace current]::primaryCommand cmdJoin]] ltone
      [namespace current]::dlog "* Last advertising programmed in [expr [set [namespace current]::conf(wait)] - 1] minutes"
      
      lappend [namespace current]::players $nick
      pushmode [set [namespace current]::conf(chanDay)] +v $nick
      set [namespace current]::preGame 1
      set [namespace current]::phase "attente"
      [namespace current]::dlog "* $nick added in players' list"
      set [namespace current]::master $nick
      putserv "TOPIC [set [namespace current]::conf(chanDay)] : [set [namespace current]::conf(topic)] - Partie lancee - Rejoignez avec [[namespace current]::primaryCommand cmdJoin]"
      [namespace current]::bindPregameCommands
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] wait_start [set [namespace current]::conf(wait)] [[namespace current]::primaryCommand cmdJoin]
      if {[info exists [namespace current]::conf(advertise)] && [set [namespace current]::conf(advertise)] ne ""} {
         [namespace current]::advertise "Une nouvelle partie attend des joueurs sur $chan"
      }
      
      # Fonction de developpement conservee, reservee aux owners Eggdrop (+n).
      [namespace current]::bindPubAliases [[namespace current]::commandAliases cmdLegacyAdd] n [namespace current]::forceAdd
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
      if {[set [namespace current]::preGame] != 1} {
         putserv "PRIVMSG $chan :Aucune inscription n'est ouverte."
         return 0
      }
      if {[[namespace current]::isGameBanned $nick]} {
         putserv "PRIVMSG $chan :$nick, tu ne peux pas rejoindre cette partie."
         return 0
      }
      if {[lsearch -nocase [set [namespace current]::players] $nick]!=-1} {
         [namespace current]::dlog "*** ATTENTION *** $nick deja dans la liste des joueurs"
         putserv "PRIVMSG $chan :Tu es deja inscrit, $nick."
         return 0
      }
      lappend [namespace current]::players $nick
      [namespace current]::dlog "* New players' list : [join [set [namespace current]::players]]"
      pushmode [set [namespace current]::conf(chanDay)] +v $nick
   }

   proc forceJoin {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      if {[set [namespace current]::preGame] != 1 || [set [namespace current]::inGame] == 1} {
         putserv "PRIVMSG $chan :[[namespace current]::primaryCommand cmdForceJoin] fonctionne seulement avant le demarrage."
         return 0
      }
      set target [string trim [lindex [split $text] 0]]
      if {$target eq ""} {
         putserv "PRIVMSG $chan :Usage: [[namespace current]::primaryCommand cmdForceJoin] <pseudo>"
         return 0
      }
      [namespace current]::addPlayer $target [getchanhost $target $chan] * $chan ""
   }

   proc forceQuit {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      if {[set [namespace current]::preGame] != 1 || [set [namespace current]::inGame] == 1} {
         putserv "PRIVMSG $chan :[[namespace current]::primaryCommand cmdForceQuit] fonctionne seulement avant le demarrage."
         return 0
      }
      set target [string trim [lindex [split $text] 0]]
      if {$target eq ""} {
         putserv "PRIVMSG $chan :Usage: [[namespace current]::primaryCommand cmdForceQuit] <pseudo>"
         return 0
      }
      if {[lsearch -nocase [set [namespace current]::players] $target] == -1} {
         putserv "PRIVMSG $chan :$target n'est pas inscrit."
         return 0
      }
      set [namespace current]::players [::utils::lremove [set [namespace current]::players] $target -nocase]
      pushmode [set [namespace current]::conf(chanDay)] -v $target
      putserv "PRIVMSG $chan :$target quitte la partie."
   }

   proc banGameUser {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      set target [string trim [lindex [split $text] 0]]
      if {$target eq ""} {
         putserv "PRIVMSG $chan :Usage: [[namespace current]::primaryCommand cmdBanGame] <pseudo>"
         return 0
      }
      if {![[namespace current]::listHas [set [namespace current]::gameBans] $target]} {
         lappend [namespace current]::gameBans $target
      }
      if {[set [namespace current]::preGame] == 1} {
         set [namespace current]::players [::utils::lremove [set [namespace current]::players] $target -nocase]
         pushmode [set [namespace current]::conf(chanDay)] -v $target
      }
      putserv "PRIVMSG $chan :$target est interdit de jeu."
   }

   proc unbanGameUser {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      set target [string trim [lindex [split $text] 0]]
      if {$target eq ""} {
         putserv "PRIVMSG $chan :Usage: [[namespace current]::primaryCommand cmdUnbanGame] <pseudo>"
         return 0
      }
      set [namespace current]::gameBans [::utils::lremove [set [namespace current]::gameBans] $target -nocase]
      putserv "PRIVMSG $chan :$target peut de nouveau jouer."
   }

   proc showGameBanList {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      if {[llength [set [namespace current]::gameBans]] == 0} {
         putserv "PRIVMSG $chan :Aucun utilisateur interdit de jeu."
      } else {
         set banText [join [set [namespace current]::gameBans] {, }]
         putserv "PRIVMSG $chan :Interdits de jeu: $banText"
      }
   }

   proc cancelGame {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      if {[set [namespace current]::preGame] == 0 && [set [namespace current]::inGame] == 0} {
         putserv "PRIVMSG $chan :Aucune partie a annuler."
         return 0
      }
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] cancel
      [namespace current]::cleanGame
   }

   proc showStatus {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      set phase [set [namespace current]::phase]
      set alive [llength [set [namespace current]::players]]
      set wolves [llength [set [namespace current]::wolves]]
      set dead 0
      if {[info exists [namespace current]::deadPlayers]} {
         set dead [llength [set [namespace current]::deadPlayers]]
      }
      set timers {}
      foreach t [timers] {
         if {[[namespace current]::listHas [concat [list "ltend" "lthalf" "ltone"] [set [namespace current]::gameTimers]] [lindex $t 2]]} {
            lappend timers [lindex $t 2]
         }
      }
      set timerText "aucun"
      if {[llength $timers]} {
         set timerText [join $timers {, }]
      }
      putserv "PRIVMSG $chan :Statut: $phase | vivants: $alive | morts: $dead | loups vivants: $wolves | timers: $timerText"
   }

   proc showRoles {nick uhost handle chan text} {
      if {![[namespace current]::requireModerator $nick $handle $chan]} { return 0 }
      if {[catch {set msg [[namespace current]::compositionText]} err]} {
         putserv "PRIVMSG $chan :$err"
      } else {
         putserv "PRIVMSG $chan :$msg"
      }
   }

   proc showComposition {nick uhost handle chan text} {
      if {[string tolower $chan] ne [string tolower [set [namespace current]::conf(chanDay)]]} {
         return 0
      }
      set now [clock seconds]
      set delay [set [namespace current]::conf(compositionCooldown)]
      set elapsed [expr {$now - [set [namespace current]::compositionLast]}]
      if {$elapsed < $delay} {
         set left [expr {$delay - $elapsed}]
         putserv "PRIVMSG $chan :La composition vient d'etre consultee. Patiente encore $left seconde(s)."
         return 0
      }
      if {[catch {set msg [[namespace current]::compositionText 1]} err]} {
         putserv "PRIVMSG $chan :$err"
         return 0
      }
      set [namespace current]::compositionLast $now
      putserv "PRIVMSG $chan :$msg"
   }

   # Manual stop of the wait for players
   proc endWaitingManu {nick uhost handle chan args} {
      [namespace current]::dlog "<-- Wait time stop invoked by $nick"
      if {$nick ne [set [namespace current]::master] && ![[namespace current]::canModerateGame $nick $handle $chan]} {
         [namespace current]::dlog "*** DENY *** $nick is not [set [namespace current]::master]"
         return 0
      }
      [namespace current]::dlog "*** OK *** : Gonna kill timers ltend, lthalf, ltone"
      [namespace current]::cleanupGameTimers
      [namespace current]::endWaiting
   }

   # Stopping the wait for players
   # If not enough players, reset the game
   proc endWaiting {} {
      [namespace current]::dlog "* Global end of wait time"
      [namespace current]::unbindPregameCommands
      [namespace current]::cleanupGameTimers
      set [namespace current]::preGame 0
      if { [set [namespace current]::gameIni(num_players)] > [llength [set [namespace current]::players]] } {
         [namespace current]::dlog "*** KO *** Not enough players : only [llength [set [namespace current]::players]] vs [set [namespace current]::gameIni(num_players)]"
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :Il faut au moins [set [namespace current]::gameIni(num_players)] joueurs pour ouvrir les portes de Thiercelieux."
         [namespace current]::cleanGame
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - Demarrez une partie avec \002[[namespace current]::primaryCommand cmdStart]\002"
      } else {
         [namespace current]::dlog "--> Ok, game starting"
         set [namespace current]::inGame 1
         set [namespace current]::phase "demarrage"
         putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - Partie en cours"
         [namespace current]::launchGame
      }
   }

   # Now, we really start the game.
   proc launchGame {} {
      [namespace current]::dlog "--> Real launching of the game in [set [namespace current]::conf(chanDay)]"
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] game_prepare
      pushmode [set [namespace current]::conf(chanDay)] +m
      if {[[namespace current]::makeNightChannel] eq ""} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :La taniere est indisponible, la partie est annulee."
         [namespace current]::cleanGame
         return 0
      }
      [namespace current]::dlog "--> running makeWolves"
      [namespace current]::makeWolves
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] wolves_chosen
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] intro_night
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] intro_day
      [namespace current]::dlog "--> Loading jobs"
      [namespace current]::selectJobs
      set [namespace current]::inGame 1
      set [namespace current]::daycount 0
      set [namespace current]::nightcount 0
      set [namespace current]::phase "nuit"
      [namespace current]::bindVoteCommand
      [namespace current]::itsNight
   }

   # Creating wolves
   proc makeWolves {} {
      set nbplayers [llength [set [namespace current]::players]]
      set nbv [[namespace current]::countWolvesFor $nbplayers [set [namespace current]::gameIni(wolves)]]
      [namespace current]::dlog "--> Waiting for $nbv wolves"
      for {set cur 0} { $cur < $nbv } { incr cur } {
         set free [::utils::ldiff [set [namespace current]::players] [set [namespace current]::wolves]]
         lappend [namespace current]::wolves [lindex $free [rand [llength $free]]]
         [namespace current]::dlog "Wolves are: [join [set [namespace current]::wolves]]"
      }
      foreach wolf [set [namespace current]::wolves] {
         [namespace current]::dlog "Now inviting $wolf to [set [namespace current]::curNight]"
         newchaninvite [set [namespace current]::curNight] $wolf $::botnick "Loup-garou" 0 sticky
         putserv "INVITE $wolf [set [namespace current]::curNight]"
         putquick "PRIVMSG $wolf :Tu es loup-garou. Rejoins la taniere avec \002/join [set [namespace current]::curNight]\002."
      }
   }

   # Attaching the fixed wolves channel.
   proc makeNightChannel {} {
      set [namespace current]::curNight [set [namespace current]::conf(chanNight)]
      if {![validchan [set [namespace current]::curNight]] || ![botonchan [set [namespace current]::curNight]]} {
         [namespace current]::dlog "*** KO *** Wolves channel [set [namespace current]::curNight] unavailable"
         return ""
      }
      [namespace current]::dlog "Using fixed wolves channel [set [namespace current]::curNight]"
      bind join - "[set [namespace current]::curNight] *" [namespace current]::wolfInChannel
      return [set [namespace current]::curNight]
   }


   proc wolfInChannel {nick uhost handle chan} {
      if {[isbotnick $nick]} { return }
      if {[lsearch -nocase [set [namespace current]::wolves] $nick] >=0} {
         pushmode [set [namespace current]::curNight] +v $nick
      } else {
         newchanban [set [namespace current]::curNight] [maskhost "${nick}!${uhost}" 7] $::botnick "Pas dans la meute"
         putkick [set [namespace current]::curNight] $nick "La taniere est reservee aux loups."
      }
   }
   
   # It's night, so players shut up
   # But wolves speak...
   proc itsNight {} {
      incr [namespace current]::nightcount
      set [namespace current]::isNight 1
      set [namespace current]::phase "nuit"
      [namespace current]::dlog "-v- Night [set [namespace current]::nightcount] - Got [llength [set [namespace current]::players]] players and [llength [set [namespace current]::wolves]] wolves"
      [namespace current]::resetVotes
      set [namespace current]::round 0
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] night_start
      [namespace current]::dlog "-v- Running night jobs"
      hook call job newnight [set [namespace current]::nightcount]
      foreach plr [chanlist [set [namespace current]::conf(chanDay)]] {
         pushmode [set [namespace current]::conf(chanDay)] -v $plr
      }
      [namespace current]::narrate [set [namespace current]::curNight] wolves_wake
      [namespace current]::narrate [set [namespace current]::curNight] wolves_vote [[namespace current]::primaryCommand cmdVote]
      foreach wlv [set [namespace current]::wolves] {
         pushmode [set [namespace current]::curNight] +v $wlv
      }
   }

   # It's day, so wolves shut up and
   # alive players speaks
   proc itsDay {} {
      incr [namespace current]::daycount
      set [namespace current]::isNight 0
      set [namespace current]::phase "jour"
      [namespace current]::dlog "-^- Day [set [namespace current]::daycount] - Got [llength [set [namespace current]::players]] players and [llength [set [namespace current]::wolves]] wolves"
      [namespace current]::resetVotes
      set [namespace current]::round 0
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] day_start
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] day_vote [[namespace current]::primaryCommand cmdVote]
      [namespace current]::dlog "-^- Running day jobs"
      hook call job newday [set [namespace current]::daycount]
      foreach wlv [chanlist [set [namespace current]::curNight]] {
         pushmode [set [namespace current]::curNight] -v $wlv
      }
      [namespace current]::narrate [set [namespace current]::curNight] wolves_sleep
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
      set min ""
      set sig ""
      set max ""
      if {![regexp {(\d{1,})(\+|-)?(\d{1,})?} $quot - min sig max]} {
         [namespace current]::dlog "*** WARN *** Invalid role quota for $job: $quot"
         return
      }
      if {[info exists min] && ($min>[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** ATTENTION *** Pas assez de joueurs ($min vs [llength [set [namespace current]::players]]), role $job ignore"
         return
      }
      if {$sig eq "" && ($min<[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** ATTENTION *** Il faut exactement $min joueurs, [llength [set [namespace current]::players]] trouves, role $job ignore"
         return
      }
      if {$sig eq "-" && $max ne "" && ($max<[llength [set [namespace current]::players]])} {
         [namespace current]::dlog "*** ATTENTION *** Trop de joueurs ($max vs [llength [set [namespace current]::players]]), role $job ignore"
         return
      }
      [namespace current]::dlog "--> Loading $jfile"
      source $jfile
   }

   # La partie est terminee, on nettoie tout.
   proc cleanGame {} {
      [namespace current]::dlog "* Entering cleaning process"
      [namespace current]::cleanupGameTimers
      [namespace current]::unbindPregameCommands
      [namespace current]::unbindVoteCommand
      [namespace current]::dlog "<-- Unloading jobs (if needed)"
      catch {hook call job clean}
      catch {hook forget job}
      [namespace current]::cleanupWolvesChannel
      [namespace current]::dlog "<-- Removing player status in [set [namespace current]::conf(chanDay)]"
      foreach plr [chanlist [set [namespace current]::conf(chanDay)]] {
         pushmode [set [namespace current]::conf(chanDay)] -v $plr
      }
      pushmode [set [namespace current]::conf(chanDay)] -m
      # Clean the players list
      set [namespace current]::players {}
      set [namespace current]::deadPlayers {}
      set [namespace current]::wolves {}
      set [namespace current]::voters {}
      set [namespace current]::votes {}
      set [namespace current]::jobbers {}
      set [namespace current]::winner {}
      set [namespace current]::inGame 0
      set [namespace current]::preGame 0
      set [namespace current]::isNight 0
      set [namespace current]::phase "idle"
      catch {unset [namespace current]::curNight}
      catch {array unset [namespace current]::gameIni}
      [namespace current]::narrate [set [namespace current]::conf(chanDay)] game_over [[namespace current]::primaryCommand cmdStart]
      putserv "TOPIC [set [namespace current]::conf(chanDay)] :[set [namespace current]::conf(topic)] - Demarrez une partie avec \002[[namespace current]::primaryCommand cmdStart]\002"
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
         putserv "PRIVMSG $chan :Un peu de patience, le conseil n'est pas encore ouvert."
         return 0
      }
      if {[set [namespace current]::isNight]==0 && [string match -nocase $chan [set [namespace current]::conf(chanDay)]]} {
         set votants [set [namespace current]::players]
      } elseif {[set [namespace current]::isNight]==1 && [string match -nocase $chan [set [namespace current]::curNight]]} {
         set votants [set [namespace current]::wolves]
      } else {
         [namespace current]::dlog "*** ATTENTION *** Vote dans $chan - attendu dans [set [namespace current]::conf(chanDay)] ou [set [namespace current]::curNight]"
         return 0
      }
      
      if {[lsearch -nocase $votants $nick]==-1} {
         putserv "PRIVMSG $nick :Tu ne peux pas voter: tu n'es pas parmi les vivants autorises."
         return 0
      }
      if {[llength [split $text]]>1} {
         putserv "PRIVMSG $chan :La forme attendue est \002[[namespace current]::primaryCommand cmdVote] <pseudo>\002, rien de plus."
         return 0
      }
      if {$text eq $nick} {
         putserv "PRIVMSG $chan :Non \002$nick\002, on ne vote pas contre soi-meme."
         return 0
      }
      if {[lsearch -nocase [set [namespace current]::players] $text]==-1} {
         putserv "PRIVMSG $chan :Impossible de voter contre \002$text\002: il n'est pas vivant dans cette partie."
         return 0
      }
      if {[lsearch -nocase [set [namespace current]::voters] $nick]!=-1} {
         putserv "PRIVMSG $chan :$nick, ton vote est deja inscrit."
         return 0
      }
      if {[set [namespace current]::isNight] == 1 && [lsearch -nocase [set [namespace current]::wolves] $text]!=-1} {
         putserv "PRIVMSG $chan :Les loups ne se devorent pas entre eux."
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
         [namespace current]::narrate $chan all_voted
         set vict [[namespace current]::getWinner [set [namespace current]::votes]]
         if {$vict == -1} {
            if {[set [namespace current]::round] == 0} {
               incr [namespace current]::round
               [namespace current]::narrate $chan vote_tie_retry
               [namespace current]::resetVotes
            } else {
               [namespace current]::narrate $chan vote_tie_none
               if {[set [namespace current]::isNight] == 1} {
                  [namespace current]::narrate [set [namespace current]::conf(chanDay)] wolves_tie_none
                  [namespace current]::itsDay
               } else {
                  [namespace current]::itsNight
               }
            }
         } else {
            set vict [[namespace current]::vict2nick $vict]
            [namespace current]::narrate [set [namespace current]::conf(chanDay)] verdict $vict
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
      if {[lsearch -nocase [set [namespace current]::deadPlayers] $nick] == -1} {
         lappend [namespace current]::deadPlayers $nick
      }
      set [namespace current]::players [::utils::lremove [set [namespace current]::players] $nick -nocase]
      set [namespace current]::wolves [::utils::lremove [set [namespace current]::wolves] $nick -nocase]
      hook call job postkill
      if {[llength [set [namespace current]::winner]]>0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :Victoire particuliere: \00303[lindex [set [namespace current]::winner] 0]\003."
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :[lindex [set [namespace current]::winner] 1]"
         [namespace current]::cleanGame
         return 0
      }
      if {[llength [set [namespace current]::wolves]]==0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :Les \00303villageois\003 ont elimine le dernier \00304loup\003."
         [namespace current]::narrate [set [namespace current]::conf(chanDay)] village_win
         [namespace current]::cleanGame
         return 0
      } elseif {[llength [::utils::ldiff [set [namespace current]::players] [set [namespace current]::wolves] -nocase]]==0} {
         putserv "PRIVMSG [set [namespace current]::conf(chanDay)] :Les \00304loups\003 ont terrasse le dernier \00303villageois\003."
         [namespace current]::narrate [set [namespace current]::conf(chanDay)] wolves_win
         [namespace current]::cleanGame
         return 0
      }
      if {$quit == 1} { return }
      if {$night == 1} {
         [namespace current]::narrate [set [namespace current]::conf(chanDay)] night_death $nick
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
      hook call job nickChange $nick $newnick
   }
   bind nick - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickChange
   
   proc nickPart {nick uhost handle chan msg} {
      if {[set [namespace current]::preGame]==0 && [set [namespace current]::inGame]==0} {
         return
      }
      if {[set [namespace current]::preGame]==1} {
         set [namespace current]::players [::utils::lremove [set [namespace current]::players] $nick -nocase]
         pushmode [set [namespace current]::conf(chanDay)] -v $nick
         return
      }
      if {[set [namespace current]::inGame]==1} {
         [namespace current]::killVict $nick 0 1
         return
      }
   }
   bind part - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickPart
   bind sign - "[set [namespace current]::conf(chanDay)] *" [namespace current]::nickPart
   
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
      putlog "$msgfile appele pour -${lang}-"
      if {$lang == ""} {set lang [string range [::msgcat::mclocale] 0 1] }
      if {[catch {open $msgfile r} fmsg]} {
         [namespace current]::dlog "*** KO *** Impossible d'ouvrir $msgfile en lecture\n$fmsg"
      } else {
         putlog "Chargement du fichier $lang depuis $msgfile"
         while {[gets $fmsg line] >= 0} {
            lappend ll $line
         }
         close $fmsg
         ::msgcat::mcmset $lang [join $ll]
         unset ll
      }
   }
   
   proc i18n {lang {bname ""}} {
      [namespace current]::dlog "# Chargement de $bname en $lang"
      if {$bname ne ""} {
         set bname "${bname}."
      }
      if {![catch {package require msgcat}]} {
         ::msgcat::mclocale fr
         if {$lang != ""} {
            set lfile [set [namespace current]::rpath]/lycanobot/translations/${bname}$lang.msg
            if {[file exists $lfile]} {
               [namespace current]::dlog "*** OK *** Fichier charge: $lfile"
               [namespace current]::translate $lfile $lang
            } else {
               [namespace current]::dlog "*** KO *** Fichier introuvable: $lfile"
            }
            ::msgcat::mclocale $lang
            putlog "Langue chargee: $lang"
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
