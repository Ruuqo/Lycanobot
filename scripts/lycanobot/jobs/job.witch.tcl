namespace eval witch {

	variable nick
	
	hook bind job start witch [namespace current]::start
	proc start {} {
		[namespace parent]::i18n [set [namespace parent]::conf(lang)] "job.[namespace tail [namespace current]]"
		set [namespace current]::nick [[namespace parent]::pickfreenick]
		lappend [namespace parent]::jobbers [set [namespace current]::nick]
		putserv "PRIVMSG [set [namespace current]::nick] :Tu es la Sorciere. Ton pouvoir sera active dans une prochaine etape."
	}
	
	hook bind job newnight witch [namespace current]::newnight
	proc newnight {night} {
		# TODO
	}
	
}
