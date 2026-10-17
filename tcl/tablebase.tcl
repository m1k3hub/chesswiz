# ======================================================================
# Endgame tablebase results for the board position.
#
# With seven pieces or fewer on a standard board, the board shows the
# tablebase verdict and the best moves under the diagram:
#
#   Tablebase: White wins (mate in 17) - best h8=Q+, h8=R+
#
# The answer comes from local Syzygy tables when a folder of them is set
# and covers the position (probed in-process through Fathom,
# ::scidb::tb::probe), else from the Lichess tablebase server
# (https://tablebase.lichess.ovh/standard?fen=..., no login) when online
# lookups are allowed: asynchronously, debounced while moving through a
# game and cached per position; only the position is sent. The board's
# context menu turns it off (Options(enabled)), sets the folder
# (Options(local)) and allows or forbids the server (Options(online)).
# Local answers have distance to zeroing (DTZ), not distance to mate.
#
#   ::tablebase::positionChanged $canv   from ::application::board::update
#
# The pure helpers (pieceCount, summary, url) are covered by
# tests/test_app_tablebase.tcl.
# ======================================================================

::util::source tablebase

namespace eval ::tablebase {
namespace eval mc {

set Tablebase		"Tablebase"
set WhiteWins		"White wins"
set BlackWins		"Black wins"
set Draw			"Draw"
set CursedWin		"%s wins, but the 50-move rule draws"
set BlessedLoss	"%s loses, but the 50-move rule draws"
set MateIn			"mate in %d"
set Best			"best"
set Checkmate		"Checkmate"
set Stalemate		"Stalemate"
set Unavailable	"not available (%s)"
set Looking			"looking up..."
set ShowTablebase	"Show Tablebase Results"
set LocalFolder	"Tablebase Folder (Syzygy)..."
set OnlineLookup	"Look Up Online (lichess.org)"
set Local			"local"
set Dtz			"DTZ %d"

} ;# namespace mc

array set Options {
	enabled 1
	online 1
	local ""
}

variable MaxPieces 7
variable Delay 350
variable CacheSize 500

variable Cache [dict create]
variable Pending {}
variable Shown {}

} ;# namespace tablebase


# Called whenever the board position changes.
proc ::tablebase::positionChanged {canv} {
	variable Options
	variable Pending
	variable Delay
	variable MaxPieces

	after cancel $Pending
	set Pending {}

	set fen [Fen]
	if {!$Options(enabled) || $fen eq "" || [pieceCount $fen] > $MaxPieces} {
		Show $canv ""
		return
	}
	if {[pieceCount $fen] > [LocalLargest] && !$Options(online)} {
		Show $canv ""
		return
	}
	set Pending [after $Delay [list ::tablebase::Lookup $canv $fen]]
}


# The largest piece count the local tables cover (0 without tables); the
# folder is loaded on first use and when it changes.
proc ::tablebase::LocalLargest {} {
	variable Options
	variable LoadedFolder

	if {[llength [info commands ::scidb::tb::init]] == 0} { return 0 }
	if {![info exists LoadedFolder] || $LoadedFolder ne $Options(local)} {
		set LoadedFolder $Options(local)
		catch { ::scidb::tb::init $Options(local) }
	}
	return [::scidb::tb::largest]
}


# A local answer in the shape of the server's, with SAN moves; "" when the
# local tables do not cover the position.
proc ::tablebase::LocalAnswer {fen} {
	if {[pieceCount $fen] > [LocalLargest]} { return "" }
	if {[catch { ::scidb::tb::probe $fen } answer] || $answer eq ""} { return "" }
	set moves {}
	foreach m [dict get $answer moves] {
		set san [dict get $m uci]
		if {![catch { ::scidb::ai::moveFacts [dict get $m uci] $fen } facts]
		 && [regexp {"san":"([^"]+)"} $facts -> s]} { set san $s }
		lappend moves [dict replace $m san $san]
	}
	dict set answer moves $moves
	return $answer
}


proc ::tablebase::Fen {} {
	if {[catch { ::scidb::game::query variant? } variant] == 0 && $variant ni {Normal {}}} { return "" }
	if {[catch { ::scidb::pos::fen } fen]} { return "" }
	return $fen
}


proc ::tablebase::Lookup {canv fen} {
	variable Cache
	variable mc

	if {![winfo exists $canv] || [Fen] ne $fen} { return }
	set key [Key $fen]
	if {[dict exists $Cache $key]} {
		Show $canv [dict get $Cache $key] [SideToMove $fen]
		return
	}
	set local [LocalAnswer $fen]
	if {$local ne ""} {
		set text [summary $local [SideToMove $fen] 1]
		dict set Cache $key $text
		Show $canv $text
		return
	}
	variable Options
	if {!$Options(online)} { Show $canv ""; return }
	Show $canv "$mc::Tablebase: $mc::Looking"
	::application::download::Get [url $fen] [list ::tablebase::Answer $canv $fen]
}


# Board menu: choose the folder of Syzygy tables.
proc ::tablebase::chooseFolder {parent} {
	variable Options
	variable mc
	set dir [tk_chooseDirectory -parent $parent -title $mc::LocalFolder -mustexist 1 \
		-initialdir [expr {$Options(local) ne "" ? $Options(local) : [file normalize ~]}]]
	if {$dir eq ""} { return }
	set Options(local) $dir
	set ::tablebase::Cache [dict create]
	LocalLargest
	toggle
}


proc ::tablebase::Answer {canv fen result} {
	variable Cache
	variable CacheSize
	variable mc

	if {![dict get $result ok]} {
		set text "$mc::Tablebase: [format $mc::Unavailable [dict get $result error]]"
		if {[winfo exists $canv] && [Fen] eq $fen} { Show $canv $text }
		return
	}
	if {[catch { package require json; ::json::json2dict [dict get $result data] } answer]} {
		return
	}
	set text [summary $answer [SideToMove $fen]]
	if {[dict size $Cache] >= $CacheSize} { set Cache [dict create] }
	dict set Cache [Key $fen] $text
	if {[winfo exists $canv] && [Fen] eq $fen} { Show $canv $text }
}


# The label under the board; an empty text hides it.
proc ::tablebase::Show {canv text args} {
	variable Shown

	if {![winfo exists $canv]} { return }
	set w $canv.tablebase
	if {$text eq ""} {
		if {[winfo exists $w]} { place forget $w }
		set Shown {}
		return
	}
	if {![winfo exists $w]} {
		ttk::label $w -padding {6 1}
	}
	$w configure -text $text
	place $w -in $canv -relx 0.5 -rely 1.0 -anchor s -y -2
	set Shown $text
}


proc ::tablebase::toggle {} {
	variable Options
	if {!$Options(enabled)} {
		after cancel $::tablebase::Pending
		catch { Show $::application::board::Vars(widget:frame) "" }
	} else {
		catch { positionChanged $::application::board::Vars(widget:frame) }
	}
}


# ----------------------------------------------------------------------
# Pure helpers.
# ----------------------------------------------------------------------

proc ::tablebase::url {fen} {
	return "https://tablebase.lichess.ovh/standard?fen=[string map {" " _} $fen]"
}


# Pieces (kings included) in the FEN's board field.
proc ::tablebase::pieceCount {fen} {
	return [regexp -all {[KQRBNPkqrbnp]} [lindex $fen 0]]
}


proc ::tablebase::SideToMove {fen} {
	return [expr {[lindex $fen 1] eq "b" ? "b" : "w"}]
}


# The position part of the FEN (the clocks do not change the verdict).
proc ::tablebase::Key {fen} {
	return [join [lrange $fen 0 3] " "]
}


# One line out of the server's answer (a dict from its JSON), for the side
# to move <stm> (w/b). The verdict is the side to move's category; the best
# moves are those that leave the opponent in the worst category, shortest
# win (or longest loss) first.
proc ::tablebase::summary {answer stm {local 0}} {
	variable mc

	set head [expr {$local ? "$mc::Tablebase ($mc::Local)" : $mc::Tablebase}]
	if {[dict exists $answer checkmate] && [dict get $answer checkmate] eq "true"} {
		return "$head: $mc::Checkmate"
	}
	if {[dict exists $answer stalemate] && [dict get $answer stalemate] eq "true"} {
		return "$head: $mc::Stalemate"
	}
	set category [expr {[dict exists $answer category] ? [dict get $answer category] : "unknown"}]
	set mover [expr {$stm eq "w" ? "White" : "Black"}]
	set other [expr {$stm eq "w" ? "Black" : "White"}]
	switch -- $category {
		win - maybe-win		{ set verdict [set mc::${mover}Wins] }
		loss - maybe-loss	{ set verdict [set mc::${other}Wins] }
		draw				{ set verdict $mc::Draw }
		cursed-win			{ set verdict [format $mc::CursedWin $mover] }
		blessed-loss		{ set verdict [format $mc::BlessedLoss $mover] }
		default				{ return "" }
	}
	set dtm [expr {[dict exists $answer dtm] ? [dict get $answer dtm] : "null"}]
	if {[string is integer -strict $dtm] && $dtm != 0 && $category in {win loss}} {
		append verdict " ([format $mc::MateIn [expr {abs($dtm)}]])"
	} elseif {$local && [dict exists $answer dtz] && [dict get $answer dtz] > 0 && $category in {win loss}} {
		append verdict " ([format $mc::Dtz [dict get $answer dtz]])"
	}

	# rank moves by the opponent's resulting category, then by distance
	set rank {loss 0 maybe-loss 1 blessed-loss 2 draw 3 cursed-win 4 maybe-win 5 win 6 unknown 7}
	set moves {}
	if {[dict exists $answer moves]} {
		foreach m [dict get $answer moves] {
			set c [expr {[dict exists $m category] ? [dict get $m category] : "unknown"}]
			if {![dict exists $rank $c]} { set c unknown }
			set d [expr {[dict exists $m dtm] && [string is integer -strict [dict get $m dtm]] \
				? [dict get $m dtm] : ([dict exists $m dtz] && [string is integer -strict [dict get $m dtz]] \
				? [dict get $m dtz] : 0)}]
			# opponent loses: mate soonest; otherwise resist longest
			set r [dict get $rank $c]
			lappend moves [list $r [expr {$r <= 2 ? -abs($d) : abs($d)}] [dict get $m san]]
		}
	}
	if {![llength $moves]} { return "$head: $verdict" }
	set moves [lsort -integer -index 0 [lsort -integer -decreasing -index 1 $moves]]
	set bestRank [lindex $moves 0 0]
	set best {}
	foreach m $moves {
		if {[lindex $m 0] != $bestRank || [llength $best] >= 3} { break }
		lappend best [lindex $m 2]
	}
	return "$head: $verdict - $mc::Best [join $best {, }]"
}


proc ::tablebase::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::tablebase::WriteOptions

# vi:set ts=3 sw=3:
