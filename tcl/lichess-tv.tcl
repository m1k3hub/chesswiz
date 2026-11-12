# ======================================================================
# Lichess TV & Broadcasts tab (::lichess::tv).
# Tab "Lichess TV" in the Chesswiz Online window:
# - Channel list (::lichess::api::tvChannels).
# - Watch a channel (::lichess::api::tvFeed) or watch a game ID
#   (::lichess::api::streamGameMoves) on a read-only ::online::view.
# - Top broadcasts list (::lichess::api::broadcastsTop).
# - Follow a live broadcast round (::lichess::api::broadcastRoundStream)
#   receiving {type pgn text <pgn>} per game and displaying the games
#   and moves on the read-only board.
# ======================================================================

::util::source lichess-tv

package require Tcl 8.5
package require Tk 8.5

namespace eval ::lichess::tv {
namespace eval mc {

set TabTitle				"Lichess TV"
set ChannelsGroup			"TV channels"
set RefreshChannels		"Refresh channels"
set WatchChannel			"Watch channel"
set WatchGameGroup		"Watch game by ID"
set GameIdLabel			"Game ID:"
set WatchGame				"Watch game"
set StopWatching			"Stop watching"
set BroadcastsGroup		"Live broadcasts"
set RefreshBroadcasts	"Refresh broadcasts"
set RoundIdLabel			"Round ID:"
set FollowRound			"Follow round"
set BroadcastGames		"Round games"
set WatchingChannel		"Watching Lichess TV: %s"
set WatchingGame			"Watching game %s"
set FollowingRound		"Following broadcast round %s (%d games)"
set StreamClosed			"Lichess TV stream closed."
set LoadingChannels		"Loading TV channels…"
set LoadingBroadcasts	"Loading top broadcasts…"
set EnterGameId			"Enter a Lichess game ID first."
set EnterRoundId			"Enter or select a broadcast round ID first."

} ;# namespace mc

array set Priv {
	tab				{}
	view				{}
	statusText		{}
	channels			{}
	selectedChannel {}
	gameId			{}
	roundId			{}
	streamHandle	{}
	streamKind		{}
	streamSerial	0
	followKey		{}
	broadcasts		{}
	roundGames		{}
	currentFen		{}
	whiteCard		{}
	blackCard		{}
}

} ;# namespace ::lichess::tv


proc ::lichess::tv::open {{parent .application}} {
	variable Priv
	variable mc

	set tab [::online::window::tab lichess-tv $mc::TabTitle]
	::online::window::select lichess-tv
	if {[info exists Priv(widget:top)] && [winfo exists $Priv(widget:top)]} {
		return $tab
	}
	set Priv(selectedChannel) $::lichess::Options(tvChannel)
	set Priv(roundId) $::lichess::Options(broadcastRound)
	set Priv(tab) $tab

	set top [ttk::frame $tab.top]
	pack $top -fill both -expand yes
	set Priv(widget:top) $top

	set left [ttk::frame $top.left]
	set right [ttk::frame $top.right]
	grid $left -row 0 -column 0 -sticky nsew -padx {0 8}
	grid $right -row 0 -column 1 -sticky nsew
	grid columnconfigure $top 0 -weight 2
	grid columnconfigure $top 1 -weight 3
	grid rowconfigure $top 0 -weight 1

	# TV channels section
	set cf [ttk::labelframe $left.channels -text $mc::ChannelsGroup -padding 6]
	set ctree [ttk::treeview $cf.tree -height 6 -selectmode browse \
		-columns {channel player rating gameId} -show headings]
	$ctree heading channel -text "Channel"
	$ctree heading player -text "Player"
	$ctree heading rating -text "Rating"
	$ctree heading gameId -text "Game"
	$ctree column channel -width 95 -anchor w
	$ctree column player -width 120 -stretch 1 -anchor w
	$ctree column rating -width 55 -anchor e
	$ctree column gameId -width 75 -anchor w
	bind $ctree <<TreeviewSelect>> [namespace code OnSelectChannel]
	bind $ctree <Double-1> [namespace code WatchSelectedChannel]
	pack $ctree -fill both -expand yes -pady {0 4}
	set Priv(widget:channels) $ctree

	set cbtns [ttk::frame $cf.btns]
	ttk::button $cbtns.refresh -text $mc::RefreshChannels \
		-command [namespace code RefreshChannels]
	ttk::button $cbtns.watch -text $mc::WatchChannel \
		-command [namespace code WatchSelectedChannel]
	ttk::button $cbtns.stop -text $mc::StopWatching \
		-command [namespace code StopStream]
	pack $cbtns.refresh $cbtns.watch $cbtns.stop -side left -padx {0 4}
	pack $cbtns -fill x
	pack $cf -fill both -expand yes -pady {0 6}

	# Watch by game ID section
	set gf [ttk::labelframe $left.game -text $mc::WatchGameGroup -padding 6]
	ttk::label $gf.lbl -text $mc::GameIdLabel
	ttk::entry $gf.entry -width 16 -textvariable [namespace current]::Priv(gameId)
	ttk::button $gf.btn -text $mc::WatchGame -command [namespace code WatchGame]
	bind $gf.entry <Return> [namespace code WatchGame]
	grid $gf.lbl -row 0 -column 0 -sticky w
	grid $gf.entry -row 0 -column 1 -sticky ew -padx 4
	grid $gf.btn -row 0 -column 2 -sticky e
	grid columnconfigure $gf 1 -weight 1
	pack $gf -fill x -pady {0 6}

	# Broadcasts section
	set bf [ttk::labelframe $left.broadcasts -text $mc::BroadcastsGroup -padding 6]
	set btree [ttk::treeview $bf.tree -height 5 -selectmode browse \
		-columns {tour round roundId} -show headings]
	$btree heading tour -text "Broadcast"
	$btree heading round -text "Round"
	$btree heading roundId -text "Round ID"
	$btree column tour -width 150 -stretch 1 -anchor w
	$btree column round -width 110 -anchor w
	$btree column roundId -width 80 -anchor w
	bind $btree <<TreeviewSelect>> [namespace code OnSelectBroadcast]
	bind $btree <Double-1> [namespace code FollowBroadcastRound]
	pack $btree -fill both -expand yes -pady {0 4}
	set Priv(widget:broadcasts) $btree

	set bform [ttk::frame $bf.form]
	ttk::button $bform.refresh -text $mc::RefreshBroadcasts \
		-command [namespace code RefreshBroadcasts]
	ttk::label $bform.rlbl -text $mc::RoundIdLabel
	ttk::entry $bform.rentry -width 12 -textvariable [namespace current]::Priv(roundId)
	ttk::button $bform.follow -text $mc::FollowRound \
		-command [namespace code FollowBroadcastRound]
	pack $bform.refresh -side left -padx {0 6}
	pack $bform.rlbl -side left
	pack $bform.rentry -side left -padx 4
	pack $bform.follow -side left
	pack $bform -fill x -pady {0 4}

	set gtree [ttk::treeview $bf.games -height 4 -selectmode browse \
		-columns {white black result moves} -show headings]
	$gtree heading white -text "White"
	$gtree heading black -text "Black"
	$gtree heading result -text "Result"
	$gtree heading moves -text "Moves"
	$gtree column white -width 110 -anchor w
	$gtree column black -width 110 -anchor w
	$gtree column result -width 55 -anchor center
	$gtree column moves -width 80 -stretch 1 -anchor w
	bind $gtree <<TreeviewSelect>> [namespace code OnSelectRoundGame]
	pack $gtree -fill both -expand yes
	set Priv(widget:roundGames) $gtree
	pack $bf -fill both -expand yes

	# Right column: embedded read-only ::online::view
	set viewPath $right.view
	::online::view::create $viewPath [namespace code ViewAction] {}
	::online::view::spectator $viewPath
	pack $viewPath -fill both -expand yes
	set Priv(view) $viewPath

	ttk::label $tab.status -anchor w -justify left -wraplength 700 \
		-textvariable [namespace current]::Priv(statusText)
	pack $tab.status -side bottom -fill x -pady {6 0}

	# no stream may outlive the tab, or run behind a closed window
	bind $top <Destroy> [namespace code { if {"%W" eq $Priv(widget:top)} { StopStream } }]
	bind [winfo toplevel $tab] <<OnlineWindowHidden>> +[namespace code StopStream]

	RefreshChannels
	RefreshBroadcasts
	return $tab
}


proc ::lichess::tv::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		::online::view::status $Priv(view) $text
	}
	::online::window::status $text
}


proc ::lichess::tv::ViewAction {action args} {
	variable Priv
	switch -- $action {
		close { StopStream }
	}
}


proc ::lichess::tv::StopStream {} {
	variable Priv
	variable mc
	if {$Priv(streamHandle) ne ""} {
		set h $Priv(streamHandle)
		set Priv(streamHandle) {}
		set Priv(streamKind) {}
		# the close is reported later; by then another stream may be running
		incr Priv(streamSerial)
		catch { ::lichess::api::close $h }
		Status $mc::StreamClosed
	}
}


# ======================================================================
# TV channels & tvFeed / streamGameMoves
# ======================================================================

proc ::lichess::tv::RefreshChannels {} {
	variable mc
	if {![llength [info commands ::lichess::api::tvChannels]]} { return 0 }
	Status $mc::LoadingChannels
	::lichess::api::tvChannels [namespace code OnChannels]
	return 1
}


proc ::lichess::tv::OnChannels {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load TV channels."}]
		return
	}
	set data [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(channels) $data
	if {![info exists Priv(widget:channels)] || ![winfo exists $Priv(widget:channels)]} { return }
	set tree $Priv(widget:channels)
	$tree delete [$tree children {}]
	if {[catch {dict size $data}]} { return }
	dict for {ch info} $data {
		if {[catch {dict size $info}]} { continue }
		set player "?"
		if {[dict exists $info user name]} {
			set player [dict get $info user name]
			if {[dict exists $info user title] && [dict get $info user title] ni {"" null}} {
				set player "[dict get $info user title] $player"
			}
		}
		set rating [expr {[dict exists $info rating] ? [dict get $info rating] : ""}]
		set gid [expr {[dict exists $info gameId] ? [dict get $info gameId] : ""}]
		$tree insert {} end -id $ch -values [list $ch $player $rating $gid]
	}
	RestoreSelection $tree selectedChannel tvChannel
}


proc ::lichess::tv::OnSelectChannel {} {
	variable Priv
	if {![info exists Priv(widget:channels)] || ![winfo exists $Priv(widget:channels)]} { return }
	set sel [$Priv(widget:channels) selection]
	if {[llength $sel]} {
		set ch [lindex $sel 0]
		set Priv(selectedChannel) $ch
		set ::lichess::Options(tvChannel) $ch
		if {[dict exists $Priv(channels) $ch gameId]} {
			set Priv(gameId) [dict get $Priv(channels) $ch gameId]
		}
	}
}


proc ::lichess::tv::WatchSelectedChannel {{channel ""}} {
	variable Priv
	variable mc
	if {$channel ne ""} { set Priv(selectedChannel) $channel }
	set ch [string trim $Priv(selectedChannel)]
	if {$ch eq ""} { set ch "best" }
	set ::lichess::Options(tvChannel) $ch
	StopStream
	set Priv(streamKind) tvFeed
	Status [format $mc::WatchingChannel $ch]
	set Priv(streamHandle) [::lichess::api::tvFeed $ch \
		[namespace code [list OnTvEvent [incr Priv(streamSerial)]]]]
	return $Priv(streamHandle)
}


proc ::lichess::tv::OnTvEvent {serial event} {
	variable Priv
	variable mc
	if {$serial != $Priv(streamSerial)} { return }
	if {[dict exists $event type] && [dict get $event type] eq "closed"} {
		set Priv(streamHandle) {}
		set Priv(streamKind) {}
		Status $mc::StreamClosed
		return
	}
	set t [expr {[dict exists $event t] ? [dict get $event t] : \
		[dict exists $event type] ? [dict get $event type] : ""}]
	set d [expr {[dict exists $event d] ? [dict get $event d] : $event}]
	switch -- $t {
		featured {
			set white [dict create name "?"]
			set black [dict create name "?"]
			if {[dict exists $d players]} {
				foreach p [dict get $d players] {
					if {[catch {dict size $p}]} { continue }
					set col [expr {[dict exists $p color] ? [dict get $p color] : ""}]
					set card [dict create name "?"]
					if {[dict exists $p user name]} { dict set card name [dict get $p user name] }
					if {[dict exists $p user title]} { dict set card title [dict get $p user title] }
					if {[dict exists $p rating]} { dict set card rating [dict get $p rating] }
					if {$col eq "white"} { set white $card }
					if {$col eq "black"} { set black $card }
				}
			}
			set Priv(whiteCard) $white
			set Priv(blackCard) $black
			if {[dict exists $d id]} { set Priv(gameId) [dict get $d id] }
			set fen [NormalizeFen [expr {[dict exists $d fen] ? [dict get $d fen] : "startpos"}]]
			set Priv(currentFen) $fen
			if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
				::online::view::setGame $Priv(view) $white $black $fen {}
			}
		}
		fen {
			ApplyFenUpdate $d
		}
	}
}


proc ::lichess::tv::WatchGame {{gameId ""}} {
	variable Priv
	variable mc
	if {$gameId ne ""} { set Priv(gameId) $gameId }
	set id [string trim $Priv(gameId)]
	if {$id eq ""} {
		Status $mc::EnterGameId
		return 0
	}
	StopStream
	set Priv(streamKind) gameMoves
	Status [format $mc::WatchingGame $id]
	set Priv(streamHandle) [::lichess::api::streamGameMoves $id \
		[namespace code [list OnGameMoveEvent [incr Priv(streamSerial)]]]]
	return $Priv(streamHandle)
}


proc ::lichess::tv::OnGameMoveEvent {serial event} {
	variable Priv
	variable mc
	if {$serial != $Priv(streamSerial)} { return }
	if {[dict exists $event type] && [dict get $event type] eq "closed"} {
		set Priv(streamHandle) {}
		set Priv(streamKind) {}
		Status $mc::StreamClosed
		return
	}
	if {[dict exists $event players] || [dict exists $event id]} {
		set white [dict create name "?"]
		set black [dict create name "?"]
		if {[dict exists $event players white]} {
			set pw [dict get $event players white]
			if {[dict exists $pw user name]} { dict set white name [dict get $pw user name] }
			if {[dict exists $pw user title]} { dict set white title [dict get $pw user title] }
			if {[dict exists $pw rating]} { dict set white rating [dict get $pw rating] }
		}
		if {[dict exists $event players black]} {
			set pb [dict get $event players black]
			if {[dict exists $pb user name]} { dict set black name [dict get $pb user name] }
			if {[dict exists $pb user title]} { dict set black title [dict get $pb user title] }
			if {[dict exists $pb rating]} { dict set black rating [dict get $pb rating] }
		}
		set Priv(whiteCard) $white
		set Priv(blackCard) $black
		set fen [NormalizeFen [expr {[dict exists $event fen] ? [dict get $event fen] : \
			[dict exists $event initialFen] ? [dict get $event initialFen] : "startpos"}]]
		set Priv(currentFen) $fen
		set ucis {}
		if {[dict exists $event moves] && [dict get $event moves] ne ""} {
			set ucis [regexp -all -inline {\S+} [dict get $event moves]]
		}
		if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
			if {[llength $ucis]} {
				::online::view::setGame $Priv(view) $white $black startpos $ucis
				set Priv(currentFen) [::online::view::fen $Priv(view)]
			} else {
				::online::view::setGame $Priv(view) $white $black $fen {}
			}
		}
		return
	}
	if {[dict exists $event fen]} {
		ApplyFenUpdate $event
	}
}


proc ::lichess::tv::NormalizeFen {fen} {
	if {$fen eq "" || $fen eq "startpos"} {
		return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	}
	set parts [regexp -all -inline {\S+} $fen]
	if {[llength $parts] == 2} {
		return "[lindex $parts 0] [lindex $parts 1] KQkq - 0 1"
	}
	if {[llength $parts] == 4} {
		return "$fen 0 1"
	}
	return $fen
}


proc ::lichess::tv::ApplyFenUpdate {d} {
	variable Priv
	set fen [NormalizeFen [dict get $d fen]]
	set Priv(currentFen) $fen
	if {$Priv(view) eq "" || ![::online::view::exists $Priv(view)]} { return }
	if {[dict exists $d lm] && [dict get $d lm] ne ""} {
		if {[::online::view::addMove $Priv(view) [dict get $d lm]]} {
			set Priv(currentFen) [::online::view::fen $Priv(view)]
		} else {
			::online::view::setGame $Priv(view) $Priv(whiteCard) $Priv(blackCard) $fen {}
		}
	} else {
		::online::view::setGame $Priv(view) $Priv(whiteCard) $Priv(blackCard) $fen {}
	}
	if {[dict exists $d wc] && [dict exists $d bc]} {
		set stm [lindex $fen 1]
		::online::view::clocks $Priv(view) \
			[expr {int([dict get $d wc] * 1000)}] \
			[expr {int([dict get $d bc] * 1000)}] \
			[expr {$stm in {w b} ? $stm : "w"}] 1
	}
}


# ======================================================================
# Broadcasts & broadcastRoundStream (pgnStream)
# ======================================================================

proc ::lichess::tv::RefreshBroadcasts {} {
	variable mc
	if {![llength [info commands ::lichess::api::broadcastsTop]]} { return 0 }
	Status $mc::LoadingBroadcasts
	::lichess::api::broadcastsTop [namespace code OnBroadcasts]
	return 1
}


proc ::lichess::tv::OnBroadcasts {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} { return }
	set data [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(broadcasts) $data
	if {![info exists Priv(widget:broadcasts)] || ![winfo exists $Priv(widget:broadcasts)]} { return }
	set tree $Priv(widget:broadcasts)
	$tree delete [$tree children {}]

	set items {}
	if {![catch {dict size $data}] && [dict exists $data active]} {
		set items [dict get $data active]
	} elseif {![catch {llength $data}]} {
		set items $data
	}
	foreach item $items {
		if {[catch {dict size $item}]} { continue }
		set tourName [expr {[dict exists $item tour name] ? [dict get $item tour name] : \
			[dict exists $item name] ? [dict get $item name] : "Broadcast"}]
		set roundName [expr {[dict exists $item round name] ? [dict get $item round name] : ""}]
		set rid [expr {[dict exists $item round id] ? [dict get $item round id] : \
			[dict exists $item id] ? [dict get $item id] : ""}]
		if {$rid ne ""} {
			$tree insert {} end -id $rid -values [list $tourName $roundName $rid]
		}
	}
	RestoreSelection $tree roundId broadcastRound
}


proc ::lichess::tv::OnSelectBroadcast {} {
	variable Priv
	if {![info exists Priv(widget:broadcasts)] || ![winfo exists $Priv(widget:broadcasts)]} { return }
	set sel [$Priv(widget:broadcasts) selection]
	if {[llength $sel]} {
		set Priv(roundId) [lindex $sel 0]
	}
}


proc ::lichess::tv::FollowBroadcastRound {{roundId ""}} {
	variable Priv
	variable mc
	if {$roundId ne ""} { set Priv(roundId) $roundId }
	set rid [string trim $Priv(roundId)]
	if {$rid eq ""} {
		Status $mc::EnterRoundId
		return 0
	}
	set ::lichess::Options(broadcastRound) $rid
	StopStream
	set Priv(roundGames) {}
	if {[info exists Priv(widget:roundGames)] && [winfo exists $Priv(widget:roundGames)]} {
		$Priv(widget:roundGames) delete [$Priv(widget:roundGames) children {}]
	}
	set Priv(streamKind) broadcastRound
	Status [format $mc::FollowingRound $rid 0]
	set Priv(followKey) {}
	set Priv(streamHandle) [::lichess::api::broadcastRoundStream $rid \
		[namespace code [list OnBroadcastPgn [incr Priv(streamSerial)] $rid]]]
	return $Priv(streamHandle)
}


proc ::lichess::tv::OnBroadcastPgn {serial rid event} {
	variable Priv
	variable mc
	if {$serial != $Priv(streamSerial)} { return }
	if {[dict exists $event type] && [dict get $event type] eq "closed"} {
		set Priv(streamHandle) {}
		set Priv(streamKind) {}
		Status $mc::StreamClosed
		return
	}
	if {![dict exists $event type] || [dict get $event type] ne "pgn"} { return }
	set text [expr {[dict exists $event text] ? [dict get $event text] : ""}]
	if {[string trim $text] eq ""} { return }

	set parsed [ParseBroadcastPgn $text]
	set key "[dict get $parsed white]|[dict get $parsed black]"
	set updated 0
	set newList {}
	foreach g $Priv(roundGames) {
		if {"[dict get $g white]|[dict get $g black]" eq $key} {
			lappend newList $parsed
			set updated 1
		} else {
			lappend newList $g
		}
	}
	if {!$updated} { lappend newList $parsed }
	set Priv(roundGames) $newList

	if {[info exists Priv(widget:roundGames)] && [winfo exists $Priv(widget:roundGames)]} {
		set tree $Priv(widget:roundGames)
		$tree delete [$tree children {}]
		set idx 0
		foreach g $Priv(roundGames) {
			$tree insert {} end -id $idx -values [list \
				[dict get $g white] [dict get $g black] \
				[dict get $g result] [join [dict get $g sans] " "]]
			if {"[dict get $g white]|[dict get $g black]" eq $Priv(followKey)} {
				set Priv(reselecting) 1
				$tree selection set $idx
			}
			incr idx
		}
	}
	if {$Priv(followKey) eq ""} { set Priv(followKey) $key }
	if {$key eq $Priv(followKey)} { ShowRoundGame $parsed }
	Status [format $mc::FollowingRound $rid [llength $Priv(roundGames)]]
}


proc ::lichess::tv::ParseBroadcastPgn {pgn} {
	set tags [dict create White "?" Black "?" Result "*" FEN "startpos"]
	set bodyLines {}
	foreach line [split $pgn \n] {
		if {[regexp {^\s*\[(\w+)\s+"(.*)"\]\s*$} $line -> k v]} {
			dict set tags $k $v
		} else {
			lappend bodyLines $line
		}
	}
	set body [join $bodyLines " "]
	regsub -all {\{[^\}]*\}} $body { } body
	while {[regsub -all {\([^()]*\)} $body { } body]} {}
	regsub -all {\$[0-9]+|[0-9]+\.(\.\.)?} $body { } body

	set fen [NormalizeFen [dict get $tags FEN]]
	set curFen $fen
	set ucis {}
	set sans {}
	foreach tok [regexp -all -inline {\S+} $body] {
		if {$tok in {* 1-0 0-1 1/2-1/2}} { break }
		set clean [string trimright $tok !?+#]
		set facts [::online::view::Facts $tok $curFen]
		if {$facts eq ""} { set facts [::online::view::Facts $clean $curFen] }
		if {$facts eq ""} { break }
		lappend ucis [dict get $facts uci]
		lappend sans [dict get $facts san]
		set curFen [dict get $facts fenAfter]
	}
	return [dict create \
		white [dict get $tags White] \
		black [dict get $tags Black] \
		result [dict get $tags Result] \
		startFen $fen \
		fen $curFen \
		ucis $ucis \
		sans $sans \
		pgn $pgn]
}


proc ::lichess::tv::OnSelectRoundGame {} {
	variable Priv
	if {![info exists Priv(widget:roundGames)] || ![winfo exists $Priv(widget:roundGames)]} { return }
	set sel [$Priv(widget:roundGames) selection]
	if {![llength $sel]} { return }
	set idx [lindex $sel 0]
	if {[string is integer -strict $idx] && $idx >= 0 && $idx < [llength $Priv(roundGames)]} {
		set g [lindex $Priv(roundGames) $idx]
		set key "[dict get $g white]|[dict get $g black]"
		# the list re-selects the followed game after each update
		if {$key eq $Priv(followKey) && [info exists Priv(reselecting)]} { unset Priv(reselecting); return }
		unset -nocomplain Priv(reselecting)
		set Priv(followKey) $key
		ShowRoundGame $g
	}
}


proc ::lichess::tv::ShowRoundGame {gameDict} {
	variable Priv
	set wcard [dict create name [dict get $gameDict white]]
	set bcard [dict create name [dict get $gameDict black]]
	set Priv(whiteCard) $wcard
	set Priv(blackCard) $bcard
	set Priv(currentFen) [dict get $gameDict fen]
	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		::online::view::setGame $Priv(view) $wcard $bcard \
			[dict get $gameDict startFen] [dict get $gameDict ucis]
	}
}

# vi:set ts=3 sw=3:


# Restore only a selection, never a stream. Missing/corrupt IDs use the first
# offered row (or no selection when the server offers nothing).
proc ::lichess::tv::RestoreSelection {tree field option} {
	variable Priv
	set rows [$tree children {}]
	set saved $::lichess::Options($option)
	if {$saved ni $rows} { set saved [lindex $rows 0] }
	set Priv($field) $saved
	set ::lichess::Options($option) $saved
	if {$saved ne ""} {
		$tree selection set [list $saved]
		$tree see $saved
	}
}
