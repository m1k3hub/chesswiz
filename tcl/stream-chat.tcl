# ======================================================================
# Stream chat, step 3 (docs/features/STREAMING_SPEC.md §5): reads the
# chat of the streamer's Twitch channel and feeds it to the Stream window
# and the overlay's chat block.
#
#   ::stream::chat::connect channel   join #channel (read-only, no sign-in)
#   ::stream::chat::disconnect
#   ::stream::chat::lines             {platform name colour text id user} ...
#   ::stream::chat::subscribe cmd     cmd is called after every change
#
# Twitch lets anyone read a channel's chat anonymously over IRC
# (nick justinfan<digits>), so reading needs no account. Messages that
# moderators delete, and all lines of users they time out or ban, are
# removed again (CLEARMSG / CLEARCHAT).
# ======================================================================

::util::source stream-chat

namespace eval ::stream::chat {

variable Host irc.chat.twitch.tv
variable Port 6667
variable Keep 50

variable Priv
array set Priv {
	chan {} channel {} state off lines {} subscribers {} retry 0 after {} buffer {}
	deadline {}
}

# connecting and joining must be done within this time (ms), else retry
variable JoinTimeout 30000


proc connect {channel} {
	variable Priv
	variable Host
	variable Port
	disconnect
	set channel [string tolower [string trimleft [string trim $channel] #]]
	if {![regexp {^[a-z0-9_]{1,25}$} $channel]} { error "invalid channel name" }
	set Priv(channel) $channel
	set Priv(state) connecting
	Notify
	if {[catch { socket -async $Host $Port } chan]} {
		Lost
		return
	}
	set Priv(chan) $chan
	fconfigure $chan -blocking 0 -buffering line -translation crlf -encoding utf-8
	fileevent $chan writable [namespace code [list Opened $chan]]
	variable JoinTimeout
	set Priv(deadline) [after $JoinTimeout [namespace code [list JoinTimedOut $chan]]]
}


proc JoinTimedOut {chan} {
	variable Priv
	set Priv(deadline) {}
	if {$chan eq $Priv(chan) && $Priv(state) ne "joined"} { Lost }
}


proc disconnect {} {
	variable Priv
	after cancel $Priv(after)
	set Priv(after) {}
	after cancel $Priv(deadline)
	set Priv(deadline) {}
	if {$Priv(chan) ne ""} { catch { close $Priv(chan) } }
	set Priv(chan) {}
	set Priv(state) off
	set Priv(retry) 0
	Notify
}


proc state {} {
	variable Priv
	return $Priv(state)
}


proc channel {} {
	variable Priv
	return $Priv(channel)
}


proc lines {} {
	variable Priv
	return $Priv(lines)
}


proc subscribe {cmd} {
	variable Priv
	if {$cmd ni $Priv(subscribers)} { lappend Priv(subscribers) $cmd }
}


proc Notify {} {
	variable Priv
	foreach cmd $Priv(subscribers) { catch { {*}$cmd } }
}


proc Opened {chan} {
	variable Priv
	if {$chan ne $Priv(chan)} { return }
	fileevent $chan writable {}
	if {[fconfigure $chan -error] ne ""} { Lost; return }
	if {[catch {
		puts $chan "CAP REQ :twitch.tv/tags twitch.tv/commands"
		puts $chan "NICK justinfan[expr {10000 + int(rand() * 89999)}]"
		puts $chan "JOIN #$Priv(channel)"
	}]} {
		Lost
		return
	}
	fileevent $chan readable [namespace code [list Readable $chan]]
}


proc Readable {chan} {
	variable Priv
	if {$chan ne $Priv(chan)} { catch { close $chan }; return }
	if {[catch { gets $chan line } n] || [eof $chan]} { Lost; return }
	if {$n >= 0} { handle $line }
}


proc Lost {} {
	variable Priv
	after cancel $Priv(deadline)
	set Priv(deadline) {}
	if {$Priv(chan) ne ""} { catch { close $Priv(chan) } }
	set Priv(chan) {}
	if {$Priv(channel) eq "" || $Priv(state) eq "off"} { return }
	# back off 2, 4, 8 ... 60 s
	set wait [expr {min(60, 2 ** min(6, [incr Priv(retry)]))}]
	set Priv(state) retrying
	Notify
	set Priv(after) [after [expr {1000 * $wait}] [namespace code [list Reconnect]]]
}


proc Reconnect {} {
	variable Priv
	set retry $Priv(retry)
	connect $Priv(channel)
	set Priv(retry) $retry
}


# One IRC line. Public so tests can replay recorded transcripts.
proc handle {line} {
	variable Priv
	lassign [Parse $line] tags prefix command params
	switch -- $command {
		PING {
			if {$Priv(chan) ne ""} { catch { puts $Priv(chan) "PONG :[lindex $params end]" } }
		}
		RECONNECT { Lost }
		366 - ROOMSTATE {
			if {$Priv(state) ne "joined"} {
				set Priv(state) joined
				set Priv(retry) 0
				after cancel $Priv(deadline)
				set Priv(deadline) {}
				Notify
			}
		}
		PRIVMSG {
			set user [lindex [split $prefix !] 0]
			set name [expr {[dict exists $tags display-name] && [dict get $tags display-name] ne ""
				? [dict get $tags display-name] : $user}]
			set colour [expr {[dict exists $tags color] ? [dict get $tags color] : ""}]
			set id [expr {[dict exists $tags id] ? [dict get $tags id] : ""}]
			set text [lindex $params end]
			# /me actions arrive as CTCP ACTION
			regexp {^\x01ACTION (.*)\x01$} $text -> text
			Add [dict create platform twitch name $name colour $colour text $text id $id user $user]
		}
		CLEARMSG {
			if {[dict exists $tags target-msg-id]} {
				Remove id [dict get $tags target-msg-id]
			}
		}
		CLEARCHAT {
			if {[llength $params] > 1} {
				Remove user [string tolower [lindex $params end]]
			} else {
				set Priv(lines) {}
				Notify
			}
		}
	}
}


proc Add {line} {
	variable Priv
	variable Keep
	lappend Priv(lines) $line
	if {[llength $Priv(lines)] > $Keep} { set Priv(lines) [lrange $Priv(lines) end-[expr {$Keep - 1}] end] }
	Notify
}


proc Remove {key value} {
	variable Priv
	set keep {}
	foreach l $Priv(lines) {
		if {[dict get $l $key] ne $value} { lappend keep $l }
	}
	if {[llength $keep] != [llength $Priv(lines)]} {
		set Priv(lines) $keep
		Notify
	}
}


# IRCv3 line -> {tags prefix command params}
proc Parse {line} {
	set tags [dict create]
	if {[string index $line 0] eq "@"} {
		set sp [string first " " $line]
		foreach pair [split [string range $line 1 $sp-1] ";"] {
			set eq [string first = $pair]
			if {$eq < 0} { dict set tags $pair ""; continue }
			dict set tags [string range $pair 0 $eq-1] \
				[string map {\\s " " \\: ; \\\\ \\ \\r "" \\n ""} [string range $pair $eq+1 end]]
		}
		set line [string range $line $sp+1 end]
	}
	set prefix ""
	if {[string index $line 0] eq ":"} {
		set sp [string first " " $line]
		set prefix [string range $line 1 $sp-1]
		set line [string range $line $sp+1 end]
	}
	set params {}
	set trailing [string first " :" $line]
	if {$trailing >= 0} {
		set head [string range $line 0 $trailing-1]
		set tail [string range $line $trailing+2 end]
	} else {
		set head $line
		set tail {}
	}
	set words [regexp -all -inline {\S+} $head]
	set command [lindex $words 0]
	set params [lrange $words 1 end]
	if {$trailing >= 0} { lappend params $tail }
	return [list $tags $prefix $command $params]
}

} ;# namespace ::stream::chat

# vi:set ts=4 sw=4:
