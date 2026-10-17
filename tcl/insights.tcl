# ======================================================================
# ::insights -- a personal report over one player's games in a database.
#
# The player list's context menu and the player card open it with
# "Insights...".  For one player it answers, from the game headers only:
# how they score overall and with each colour, by opening family and by
# single opening, against which opponent strength, by year and by game
# length, where the losses come from, and in which openings with enough
# games they score worst.  Like the prep report and the opponent dossier
# it reads the numbers out of the database; nothing is inferred.
#
# The report has three layers:
#   the pure core    aggregate(): records in, numbers out; every score
#                    is an integer in hundredths of a percent (8500 is
#                    85.00%, as ::scidb::db::get playerStats reports),
#                    so no float ever reaches a test or the window.
#                    Covered by tests/test_app_insights.tcl.
#   the collector    collect(): streams the player's game headers out
#                    of the database in idle chunks.  Header data only
#                    (no game is loaded), so large databases stay
#                    responsive; the window shows the progress.
#   the window       show(): sections with tables (ttk::treeview) and
#                    percentage bars (canvas).  Double-clicking an
#                    opening row filters the game list to those games
#                    (in the database switcher, as the dossier does).
#
# A record is {white black result eco opening whiteElo blackElo date
# plies termination}; plies are half-moves, ratings may be negative
# (a rating not written in the game itself, see ::scidb::db::get
# gameInfo) or empty, and date is the game's date ("1993.??.??").
# ======================================================================

::util::source insights

package require Tcl 8.5
package require Tk 8.5

namespace eval insights {
namespace eval mc {

set Show					"Insights..."
set Title				"Insights: %s"
set Player				"Player"
set Database				"Database"
set Games				"Games"
set Score					"Score"
set Record				"W-D-L"
set SectionColour		"Score by colour"
set SectionFamily		"Results by opening family"
set SectionOpenings		"Top openings"
set SectionStrength		"Results by opponent strength"
set SectionYear			"Results by year"
set SectionLength		"Results by game length"
set SectionWeakest		"Weakest openings"
set SectionReasons		"Loss reasons"
set ColColour			"Colour"
set ColFamily			"Family"
set ColEco				"ECO"
set ColOpening			"Opening"
set ColYear				"Year"
set ColStrength			"Opponent"
set ColLength			"Length"
set ColWins				"Wins"
set ColDraws				"Draws"
set ColLosses			"Losses"
set ColGames				"Games"
set ColScore				"Score %"
set ColLossRate			"Loss %"
set ColCount				"Losses"
set ColReason			"Reason"
set Overall				"Overall"
set White					"As White"
set Black					"As Black"
set Band(weaker200)		"Opponent weaker by more than 200"
set Band(weaker50)		"Opponent weaker by 50-200"
set Band(even)			"Opponent within 50"
set Band(stronger50)		"Opponent stronger by 50-200"
set Band(stronger200)		"Opponent stronger by more than 200"
set Band(unknown)			"Rating unknown"
set Length(short)		"Short (under 30 moves)"
set Length(medium)		"Medium (30-60 moves)"
set Length(long)			"Long (more than 60 moves)"
set NoEco					"(no ECO code)"
set WeakestHint			"Openings with at least %s games, lowest score first."
set NoGames				"%s has no games in this database."
set Collecting			"Reading %s of %s games..."
set Collected				"%s games, %s decided, %s without result."
set Refresh				"Refresh"
set OpenInSwitcher		"Open Selected Opening In Switcher"
set NoSelection			"Select an opening row first."

} ;# namespace mc

array set Options {
	weakest:min-games	5
	top:openings		10
	weakest:lines		5
}

# the wins / draws / losses segments of a bar (canvas -fill colors)
variable BarColors {seagreen gray56 indianred}

variable CollectCounter 0

array set Data {}
array set Collect {}

} ;# namespace insights


proc ::insights::show {parent base variant playerIndex} {
	variable Data
	variable mc

	if {$playerIndex < 0} { return }
	if {[catch { ::scidb::db::get playerKey $base $variant $playerIndex } playerKey]} { return }
	set name [lindex $playerKey 0]

	set dlg [DialogName $base $variant $playerIndex]
	if {![winfo exists $dlg]} {
		set Data($dlg,base) $base
		set Data($dlg,variant) $variant
		set Data($dlg,playerIndex) $playerIndex
		set Data($dlg,playerKey) $playerKey
		set Data($dlg,playerName) $name
		set Data($dlg,token) 0
		set Data($dlg,gamesText) {}
		set Data($dlg,scoreText) {}
		set Data($dlg,recordText) {}
		set Data($dlg,status) {}
		BuildWindow $dlg $parent
	}

	wm deiconify $dlg
	raise $dlg
	focus $dlg
	Refresh $dlg
	return $dlg
}


# Read the database again (the Refresh button, and every time the window
# is asked for).  A running collection is cancelled first, so no stale
# records can arrive after a refresh.
proc ::insights::Refresh {dlg} {
	variable Data
	variable CollectCounter

	if {![winfo exists $dlg]} { return }
	CancelCollect $Data($dlg,token)
	set token [incr CollectCounter]
	set Data($dlg,token) $token
	set Data($dlg,result) {}
	set Data($dlg,gamesText) {}
	set Data($dlg,scoreText) {}
	set Data($dlg,recordText) {}
	set Data($dlg,status) {}

	collect $Data($dlg,base) $Data($dlg,variant) $Data($dlg,playerIndex) \
		-token $token \
		-progress [namespace code [list Progress $dlg]] \
		-done [namespace code [list CollectDone $dlg $token]] \
		;
}


proc ::insights::Progress {dlg done total} {
	variable Data
	variable mc

	if {![winfo exists $dlg]} { return }
	set Data($dlg,status) [format $mc::Collecting \
		[::locale::formatNumber $done] [::locale::formatNumber $total]]
}


# One report out of the collected records; a collection that was
# cancelled by a refresh is dropped by its token.
proc ::insights::CollectDone {dlg token result} {
	variable Data
	variable mc

	if {![winfo exists $dlg]} { return }
	if {$token != $Data($dlg,token)} { return }
	set Data($dlg,token) 0

	if {![dict get $result ok]} {
		set Data($dlg,status) [dict get $result error]
		return
	}

	set report [aggregate [dict get $result records] $Data($dlg,playerName)]
	set Data($dlg,result) $report

	set games [dict get $report games]
	if {$games == 0} {
		set Data($dlg,gamesText) 0
		set Data($dlg,status) [format $mc::NoGames $Data($dlg,playerName)]
	} else {
		lassign [dict get $report overall] _ wins draws losses _ score _
		set Data($dlg,gamesText) [::locale::formatNumber $games]
		set Data($dlg,scoreText) "[formatPercent $score]%"
		set Data($dlg,recordText) [formatWdl $wins $draws $losses]
		set Data($dlg,status) [format $mc::Collected \
			[::locale::formatNumber $games] \
			[::locale::formatNumber [dict get $report decided]] \
			[::locale::formatNumber [dict get $report unknown]]]
	}

	Populate $dlg $report
}


# ======================================================================
# Data: stream the player's game headers out of the database.
# ======================================================================

# ::insights::collect $base $variant $playerIndex ?-chunk N? ?-progress CMD?
#   ?-done CMD?
# Searches the player's games into a scratch view (as the prep report
# does) and walks it in idle chunks of -chunk games, reading each
# game's header only.  -progress gets "<done> <total>", -done gets
# {ok 1 records RECORDS} or {ok 0 error MESSAGE}.  The view is closed
# before -done runs.  No game is ever loaded whole.  -token names the
# run so the caller can cancel exactly it; a fresh one is taken when
# none is given.
proc ::insights::collect {base variant playerIndex args} {
	variable Collect
	variable CollectCounter

	array set opts [list -chunk 1000 -progress {} -done {} -token {}]
	array set opts $args
	if {$opts(-chunk) < 1} { set opts(-chunk) 1 }

	if {[string length $opts(-token)]} {
		set token $opts(-token)
	} else {
		set token [incr CollectCounter]
	}
	set Collect($token,base) $base
	set Collect($token,variant) $variant
	set Collect($token,chunk) $opts(-chunk)
	set Collect($token,progress) $opts(-progress)
	set Collect($token,done) $opts(-done)
	set Collect($token,records) {}
	set Collect($token,index) 0
	set Collect($token,total) 0
	set Collect($token,view) -1
	set Collect($token,after) {}

	if {[catch {
		set view [::scidb::view::new $base $variant unused unused unused unused master slave]
		set Collect($token,view) $view
		::scidb::view::search $base $variant $view null none [list player $playerIndex]
		set Collect($token,total) [::scidb::view::count games $base $variant $view]
	} message]} {
		FinishCollect $token [list ok 0 error $message]
		return $token
	}

	if {$Collect($token,total) == 0} {
		FinishCollect $token [list ok 1 records {}]
	} else {
		set Collect($token,after) [after idle [namespace code [list CollectChunk $token]]]
	}
	return $token
}


proc ::insights::CollectChunk {token} {
	variable Collect

	if {![info exists Collect($token,base)]} { return }	;# cancelled
	set last [expr {$Collect($token,index) + $Collect($token,chunk)}]
	if {$last > $Collect($token,total)} { set last $Collect($token,total) }

	set base $Collect($token,base)
	set variant $Collect($token,variant)
	set view $Collect($token,view)
	for {set index $Collect($token,index)} {$index < $last} {incr index} {
		lappend Collect($token,records) [Record $base $variant $view $index]
	}
	set Collect($token,index) $last

	if {[llength $Collect($token,progress)]} {
		{*}$Collect($token,progress) $last $Collect($token,total)
	}

	if {$last < $Collect($token,total)} {
		set Collect($token,after) [after idle [namespace code [list CollectChunk $token]]]
	} else {
		FinishCollect $token [list ok 1 records $Collect($token,records)]
	}
}


proc ::insights::FinishCollect {token result} {
	variable Collect

	if {![info exists Collect($token,base)]} { return }
	if {$Collect($token,view) >= 0} {
		catch { ::scidb::view::close $Collect($token,base) $Collect($token,variant) $Collect($token,view) }
	}
	set done $Collect($token,done)
	FreeCollect $token
	if {[llength $done]} { after 0 [list {*}$done $result] }
}


proc ::insights::CancelCollect {token} {
	variable Collect

	if {$token == 0} { return }
	catch { after cancel $Collect($token,after) }
	if {[info exists Collect($token,view)] && $Collect($token,view) >= 0} {
		catch { ::scidb::view::close $Collect($token,base) $Collect($token,variant) $Collect($token,view) }
	}
	FreeCollect $token
}


proc ::insights::FreeCollect {token} {
	variable Collect

	foreach key [array names Collect $token,*] { unset Collect($key) }
}


# One game header as a record {white black result eco opening whiteElo
# blackElo date plies termination}.  The length column is full moves
# (see ::scidb::db::get gameInfo) and records count half-moves; the
# opening column is a list whose first part is the opening's name.
proc ::insights::Record {base variant view index} {
	set info [::scidb::db::get gameInfo $index $view $base $variant -ratings {Elo Elo}]
	return [list \
		[::gamestable::column $info white] \
		[::gamestable::column $info black] \
		[::gamestable::column $info result] \
		[string trim [::gamestable::column $info eco]] \
		[lindex [::gamestable::column $info opening] 0] \
		[::gamestable::column $info whiteRating1] \
		[::gamestable::column $info blackRating1] \
		[::gamestable::column $info date] \
		[expr {2*[::gamestable::column $info length]}] \
		[::gamestable::column $info termination]]
}


# ======================================================================
# The pure core: records in, one report dict out.
#
# The report dict, all counts integers, scores in hundredths of a
# percent (8500 = 85.00%):
#   games N decided N unknown N
#   overall {overall W D L games score loss}
#   white {white W D L games score loss}     (only with white games)
#   black {black W D L games score loss}     (only with black games)
#   families {{A W D L games score loss} ...}        A-E, "?" last
#   openings {{ECO NAME W D L games score loss} ...}  top -top-openings
#   weakest  {{ECO NAME W D L games score loss} ...} lowest score first
#   bands {{band W D L games score loss} ...} weakest to strongest, "?" last
#   years {{YEAR W D L games score loss} ...} newest first, "?" last
#   lengths {{short|medium|long W D L games score loss} ...}
#   lossReasons {{REASON LOSSES} ...}        most losses first
# Rows with no games are left out (overall is always present).
# ======================================================================

proc ::insights::aggregate {records player args} {
	variable Options

	array set opts [list \
		-min-games $Options(weakest:min-games) \
		-top-openings $Options(top:openings) \
		-weakest-lines $Options(weakest:lines)]
	array set opts $args

	array set acc {}
	array set names {}
	array set reasons {}

	set games 0
	set acc(overall) {0 0 0 0}

	foreach record $records {
		lassign $record white black result eco opening whiteElo blackElo date plies termination
		if {$white eq $player} {
			set side white
			set ownElo $whiteElo
			set oppElo $blackElo
		} elseif {$black eq $player} {
			set side black
			set ownElo $blackElo
			set oppElo $whiteElo
		} else {
			continue
		}
		incr games
		set outcome [resultFor $result $side]

		Bump acc overall $outcome
		Bump acc $side $outcome
		Bump acc family:[ecoFamily $eco] $outcome
		Bump acc band:[eloBand $ownElo $oppElo] $outcome
		Bump acc year:[yearOf $date] $outcome
		Bump acc length:[lengthBucket [moveCount $plies]] $outcome

		if {$outcome eq "loss"} {
			set reason [string trim $termination]
			if {$reason eq ""} { set reason "?" }
			if {[info exists reasons($reason)]} {
				incr reasons($reason)
			} else {
				set reasons($reason) 1
			}
		}

		set eco [string trim $eco]
		if {$eco ne "" && $eco ne "?"} {
			Bump acc opening:$eco $outcome
			if {![info exists names($eco)] && [string length [string trim $opening]]} {
				set names($eco) [string trim $opening]
			}
		}
	}

	set report [dict create \
		games $games \
		decided [Decided $acc(overall)] \
		unknown [expr {$games - [Decided $acc(overall)]}] \
		overall [Row overall $acc(overall)]]

	foreach side {white black} {
		if {[info exists acc($side)]} { dict set report $side [Row $side $acc($side)] }
	}

	set families {}
	foreach family {A B C D E} {
		if {[info exists acc(family:$family)]} {
			lappend families [Row $family $acc(family:$family)]
		}
	}
	if {[info exists acc(family:?)]} { lappend families [Row ? $acc(family:?)] }
	dict set report families $families

	dict set report openings [Openings acc names $opts(-top-openings) 0 0]
	dict set report weakest [Openings acc names $opts(-weakest-lines) 1 $opts(-min-games)]

	set bands {}
	foreach band {weaker200 weaker50 even stronger50 stronger200 unknown} {
		if {[info exists acc(band:$band)]} {
			lappend bands [Row $band $acc(band:$band)]
		}
	}
	dict set report bands $bands

	set years {}
	foreach year [lsort -decreasing [array names acc year:*]] {
		if {$year eq "year:?"} { continue }
		lappend years [Row [string range $year 5 end] $acc($year)]
	}
	if {[info exists acc(year:?)]} { lappend years [Row ? $acc(year:?)] }
	dict set report years $years

	set lengths {}
	foreach length {short medium long} {
		if {[info exists acc(length:$length)]} {
			lappend lengths [Row $length $acc(length:$length)]
		}
	}
	dict set report lengths $lengths

	set lossReasons {}
	foreach reason [array names reasons] { lappend lossReasons [list $reason $reasons($reason)] }
	set lossReasons [lsort -index 0 $lossReasons]
	set lossReasons [lsort -integer -decreasing -index 1 $lossReasons]
	dict set report lossReasons $lossReasons

	return $report
}


# The two opening tables.  <weakest> 1 orders by score (the weakest
# openings) and drops rows with fewer than <min-games> games, 0 orders
# by games (the top openings) and keeps everything.
proc ::insights::Openings {accName namesName limit weakest minGames} {
	upvar 1 $accName acc
	upvar 1 $namesName names

	if {$limit <= 0} { return {} }

	set rows {}
	foreach key [lsort -dictionary [array names acc opening:*]] {
		set eco [string range $key 8 end]
		set name [expr {[info exists names($eco)] ? $names($eco) : ""}]
		lassign $acc($key) wins draws losses games
		lappend rows [list $eco $name $wins $draws $losses $games \
			[score100 $wins $draws $losses] [lossRate100 $wins $draws $losses]]
	}

	# ties keep the ECO order of the pass before
	set rows [lsort -integer -index 5 -decreasing $rows]
	if {$weakest} {
		set kept {}
		foreach row $rows {
			if {[lindex $row 5] >= $minGames} { lappend kept $row }
		}
		set rows [lsort -integer -index 6 $kept]
	}

	return [lrange $rows 0 [expr {$limit - 1}]]
}


# One game into one bucket {wins draws losses games} of array <accName>.
proc ::insights::Bump {accName key outcome} {
	upvar 1 $accName acc

	if {![info exists acc($key)]} { set acc($key) {0 0 0 0} }
	lassign $acc($key) wins draws losses games
	incr games
	switch -- $outcome {
		win		{ incr wins }
		draw		{ incr draws }
		loss		{ incr losses }
	}
	set acc($key) [list $wins $draws $losses $games]
}


proc ::insights::Row {key stats} {
	lassign $stats wins draws losses games
	return [list $key $wins $draws $losses $games \
		[score100 $wins $draws $losses] [lossRate100 $wins $draws $losses]]
}


proc ::insights::Decided {stats} {
	lassign $stats wins draws losses
	return [expr {$wins + $draws + $losses}]
}


# The opening family of an ECO code: its first letter, or "?" when the
# game has no ECO code.
proc ::insights::ecoFamily {eco} {
	set family [string toupper [string index [string trim $eco] 0]]
	if {$family ni {A B C D E}} { return "?" }
	return $family
}


# Full moves in a game of <plies> half-moves.
proc ::insights::moveCount {plies} {
	if {![string is integer -strict $plies]} { return 0 }
	return [expr {($plies + 1) / 2}]
}


# short (under 30 moves), medium (30-60), long (more than 60).
proc ::insights::lengthBucket {moves} {
	if {$moves < 30} { return short }
	if {$moves <= 60} { return medium }
	return long
}


# Which opponent-strength band a game belongs to: the opponent's rating
# against the player's own in that game.  Either rating missing means
# no band can be told.
proc ::insights::eloBand {own opponent} {
	set own [ratingValue $own]
	set opponent [ratingValue $opponent]
	if {$own <= 0 || $opponent <= 0} { return unknown }
	set diff [expr {$opponent - $own}]
	if {$diff < -200} { return weaker200 }
	if {$diff < -50} { return weaker50 }
	if {$diff <= 50} { return even }
	if {$diff <= 200} { return stronger50 }
	return stronger200
}


# A game rating as an absolute number; 0 when there is none.  Negative
# ratings are the ones the game did not carry itself (see ::scidb::db::get
# gameInfo); their value is the rating all the same.
proc ::insights::ratingValue {rating} {
	if {![string is integer -strict $rating]} { return 0 }
	return [expr {abs($rating)}]
}


# The year of a game date ("1993.??.??"), "?" when there is none.
proc ::insights::yearOf {date} {
	set year [string range $date 0 3]
	if {[string is integer -strict $year] && $year >= 1000} { return $year }
	return "?"
}


# win, draw or loss for the player of colour <side>; "" when the game
# has no result.
proc ::insights::resultFor {result side} {
	switch -- $result {
		1-0			{ return [expr {$side eq "white" ? "win" : "loss"}] }
		0-1			{ return [expr {$side eq "black" ? "win" : "loss"}] }
		1/2-1/2	{ return draw }
		default		{ return "" }
	}
}


proc ::insights::score100 {wins draws losses} {
	set decided [expr {$wins + $draws + $losses}]
	if {$decided == 0} { return 0 }
	return [expr {round(10000.0*($wins + 0.5*$draws)/$decided)}]
}


proc ::insights::lossRate100 {wins draws losses} {
	set decided [expr {$wins + $draws + $losses}]
	if {$decided == 0} { return 0 }
	return [expr {round(10000.0*$losses/$decided)}]
}


proc ::insights::formatPercent {score} {
	return [format %.1f [expr {$score/100.0}]]
}


# The record line the report shows: +W =D -L.
proc ::insights::formatWdl {wins draws losses} {
	return [format "+%d =%d -%d" $wins $draws $losses]
}


# ======================================================================
# The window.
# ======================================================================

proc ::insights::DialogName {base variant playerIndex} {
	set label [file tail $base]
	set label [string map {: _ / _ \\ _ " " _ . _} $label]
	set label [regsub -all {[^A-Za-z0-9_-]} $label _]
	set label [regsub -all {_+} $label _]
	if {![string length $label]} { set label db }
	set checksum [::scidb::misc::crc32 [file normalize $base]]
	return .insights_${label}_${checksum}_${variant}_$playerIndex
}


proc ::insights::BuildWindow {dlg parent} {
	variable Data
	variable mc

	toplevel $dlg -class Scidb
	wm withdraw $dlg
	wm title $dlg [format $mc::Title $Data($dlg,playerName)]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]

	# the head: who, where, and how many games it came to
	set head $dlg.head
	ttk::frame $head
	pack $head -side top -fill x -padx 6 -pady {6 0}
	ttk::label $head.playerLabel -text $mc::Player
	ttk::label $head.player -text $Data($dlg,playerName)
	ttk::label $head.baseLabel -text $mc::Database
	ttk::label $head.base -text [::util::databaseName $Data($dlg,base) no]
	ttk::label $head.gamesLabel -text $mc::Games
	ttk::label $head.games -textvariable [namespace current]::Data($dlg,gamesText)
	ttk::label $head.scoreLabel -text $mc::Score
	ttk::label $head.score -textvariable [namespace current]::Data($dlg,scoreText)
	ttk::label $head.recordLabel -text $mc::Record
	ttk::label $head.record -textvariable [namespace current]::Data($dlg,recordText)
	set column 1
	foreach child {playerLabel player baseLabel base gamesLabel games
						scoreLabel score recordLabel record} {
		grid $head.$child -row 1 -column $column -sticky w
		incr column 2
	}

	ttk::label $dlg.status -textvariable [namespace current]::Data($dlg,status)
	pack $dlg.status -side top -fill x -padx 6 -pady 3

	ttk::frame $dlg.controls
	pack $dlg.controls -side top -fill x -padx 6 -pady {0 6}
	ttk::button $dlg.controls.refresh -text $mc::Refresh -command [namespace code [list Refresh $dlg]]
	ttk::button $dlg.controls.switcher -text $mc::OpenInSwitcher \
		-command [namespace code [list OpenSelectedOpeningInSwitcher $dlg]]
	ttk::button $dlg.controls.close -text $::mc::Close -command [list destroy $dlg]
	pack $dlg.controls.close -side right
	pack $dlg.controls.switcher -side right -padx {0 6}
	pack $dlg.controls.refresh -side right -padx {0 6}

	# the sections are one report; small windows scroll it
	set scrolled [::scrolledframe $dlg.body]
	::scrolledframe::bindMouseWheel $scrolled $dlg
	pack $dlg.body -side top -fill both -expand yes -padx 6 -pady {0 6}
	set body [ttk::frame $scrolled.f -borderwidth 0 -takefocus 0]
	grid $scrolled.f -sticky nsew

	set Data($dlg,trees:colour) [BuildSection $dlg $body colour \
		$mc::SectionColour {key} $mc::ColColour 3]
	set Data($dlg,trees:family) [BuildSection $dlg $body family \
		$mc::SectionFamily {key} $mc::ColFamily 7]
	set Data($dlg,trees:openings) [BuildSection $dlg $body openings \
		$mc::SectionOpenings {eco opening} $mc::ColEco 9]
	set Data($dlg,trees:weakest) [BuildSection $dlg $body weakest \
		$mc::SectionWeakest {eco opening} $mc::ColEco 6]
	set Data($dlg,trees:bands) [BuildSection $dlg $body bands \
		$mc::SectionStrength {key} $mc::ColStrength 7]
	set Data($dlg,trees:years) [BuildSection $dlg $body years \
		$mc::SectionYear {key} $mc::ColYear 8]
	set Data($dlg,trees:lengths) [BuildSection $dlg $body lengths \
		$mc::SectionLength {key} $mc::ColLength 4]

	set reasons [ttk::labelframe $body.reasons -text " $mc::SectionReasons "]
	pack $body.reasons -side top -fill x -pady {0 6}
	set tree [ttk::treeview $reasons.tree \
		-columns {reason losses} \
		-show headings \
		-height 4]
	$tree heading reason -text $mc::ColReason
	$tree heading losses -text $mc::ColCount
	$tree column reason -anchor w -width 300 -stretch 1
	$tree column losses -anchor e -width 90 -stretch 0
	pack $tree -fill x
	set Data($dlg,trees:reasons) $tree

	foreach section {openings weakest} {
		bind $Data($dlg,trees:$section) <Double-1> \
			[namespace code [list OpenSelectedOpeningInSwitcher $dlg]]
	}

	bind $dlg <Destroy> [namespace code [list Destroy $dlg %W]]
	wm minsize $dlg 780 480
	::util::place $dlg -parent [winfo toplevel $parent] -position center
}


# One section: a labelframe with the percentage bars (canvas) over a
# table (ttk::treeview).  <keyColumns> are the section's own leading
# columns, the numeric ones (wins, draws, losses, games, score, loss)
# follow in every section.  Returns the treeview's path.
proc ::insights::BuildSection {dlg body id title keyColumns keyHeading height} {
	variable mc

	set f [ttk::labelframe $body.$id -text " $title "]
	pack $f -side top -fill x -pady {0 6}

	set columns $keyColumns
	lappend columns {*}{wins draws losses games score loss}

	set tree [ttk::treeview $f.tree -columns $columns -show headings -height $height]
	foreach key $keyColumns {
		set heading $keyHeading
		set width 240
		switch -- $key {
			eco			{ set heading $mc::ColEco; set width 70 }
			opening		{ set heading $mc::ColOpening; set width 300 }
		}
		$tree heading $key -text $heading
		$tree column $key -anchor w -width $width -stretch 1
	}
	foreach {key heading anchor width} {
		wins		$mc::ColWins			e		70
		draws		$mc::ColDraws			e		70
		losses		$mc::ColLosses			e		70
		games		$mc::ColGames			e		70
		score		$mc::ColScore			e		80
		loss		$mc::ColLossRate		e		80
	} {
		$tree heading $key -text $heading
		$tree column $key -anchor $anchor -width $width -stretch 0
	}
	pack $tree -fill x

	set canv [canvas $f.bars -height 1 -highlightthickness 0 \
		-background [::colors::lookup table,background]]
	pack $canv -fill x -before $tree
	# the canvas is not mapped yet when the report arrives; redraw the
	# bars once its real width is known
	bind $canv <Configure> [namespace code [list CanvasResized $dlg $id $canv %w]]

	return $tree
}


proc ::insights::Populate {dlg report} {
	variable Data
	variable Options
	variable mc

	if {![winfo exists $dlg]} { return }

	set colourRows {}
	foreach key {overall white black} {
		if {[dict exists $report $key]} { lappend colourRows [dict get $report $key] }
	}
	FillSection $dlg colour $colourRows [dict create \
		overall $mc::Overall white $mc::White black $mc::Black]

	FillSection $dlg family [dict get $report families] {}
	FillSection $dlg openings [dict get $report openings] {}
	FillSection $dlg weakest [dict get $report weakest] {}
	FillSection $dlg bands [dict get $report bands] [dict create \
		weaker200		$mc::Band(weaker200) \
		weaker50			$mc::Band(weaker50) \
		even				$mc::Band(even) \
		stronger50		$mc::Band(stronger50) \
		stronger200		$mc::Band(stronger200) \
		unknown			$mc::Band(unknown)]
	FillSection $dlg years [dict get $report years] {}
	FillSection $dlg lengths [dict get $report lengths] [dict create \
		short		$mc::Length(short) \
		medium	$mc::Length(medium) \
		long		$mc::Length(long)]

	set tree $Data($dlg,trees:reasons)
	$tree delete [$tree children {}]
	foreach row [dict get $report lossReasons] {
		$tree insert {} end -values $row
	}

	# an empty weakest table says why it is empty
	set weakest $Data($dlg,trees:weakest)
	if {[llength [$weakest children {}]] == 0} {
		$weakest insert {} end -values [list {} \
			[format $mc::WeakestHint [::locale::formatNumber $Options(weakest:min-games)]] \
			{} {} {} {} {} {}]
	}
}


# <labels> translates a row's key into its text when the key itself is
# not what to show (colour, band and length rows).
proc ::insights::FillSection {dlg section rows labels} {
	variable Data
	variable mc

	set tree $Data($dlg,trees:$section)
	set canvas [winfo parent $tree].bars
	$tree delete [$tree children {}]
	$canvas delete all

	if {![llength $rows]} { return }

	set barRows {}
	foreach row $rows {
		if {$section eq "openings" || $section eq "weakest"} {
			lassign $row eco name wins draws losses games score loss
			if {$name eq ""} { set name $eco }
			set values [list $eco $name $wins $draws $losses $games \
				[formatPercent $score] [formatPercent $loss]]
			set label [string trim "$eco $name"]
		} else {
			lassign $row key wins draws losses games score loss
			set label $key
			if {$section eq "family" && $key eq "?"} { set label $mc::NoEco }
			if {[dict exists $labels $key]} { set label [dict get $labels $key] }
			set values [list $label $wins $draws $losses $games \
				[formatPercent $score] [formatPercent $loss]]
		}
		$tree insert {} end -values $values
		lappend barRows [list $label [list $wins $draws $losses $score]]
	}

	# the bars follow the table's width once the window is mapped
	set Data($dlg,bars:$section) $barRows
	set Data($dlg,barWidth:$section) 0
	DrawBars $canvas $barRows [SectionWidth $canvas]
}


# How much width the bars of <canvas> have: the canvas' width once it is
# mapped, its requested width before.
proc ::insights::SectionWidth {canvas} {
	set width [winfo width $canvas]
	if {$width <= 1} { set width 700 }
	return $width
}


proc ::insights::CanvasResized {dlg section canvas width} {
	variable Data

	if {![winfo exists $dlg]} { return }
	if {$width <= 1 || ![info exists Data($dlg,bars:$section)]} { return }
	if {$width == $Data($dlg,barWidth:$section)} { return }
	set Data($dlg,barWidth:$section) $width
	DrawBars $canvas $Data($dlg,bars:$section) $width
}


# The percentage bars of one section: one horizontal bar per row, in
# wins/draws/losses colors, the score at its right end.
proc ::insights::DrawBars {canvas rows width} {
	variable BarColors

	set lineHeight 18
	set barHeight 10
	set margin 4
	set labelWidth 240
	set scoreWidth 64
	set foreground [::colors::lookup table,foreground]
	lassign $BarColors winColor drawColor lossColor

	$canvas delete all
	$canvas configure -height [expr {[llength $rows]*$lineHeight + 2*$margin}]

	set barStart [expr {$labelWidth + 8}]
	set barEnd [expr {$width - $scoreWidth - 8}]
	if {$barEnd < $barStart + 40} { set barEnd [expr {$barStart + 40}] }
	set barWidth [expr {$barEnd - $barStart}]

	set index 0
	foreach row $rows {
		set y [expr {$margin + $index*$lineHeight + $barHeight/2}]
		incr index
		lassign $row label stats
		lassign $stats wins draws losses score
		set decided [expr {$wins + $draws + $losses}]

		$canvas create text $labelWidth $y -anchor e -font TkDefaultFont \
			-fill $foreground -text $label -width $labelWidth

		set barY [expr {$y - $barHeight/2}]
		if {$decided == 0} {
			$canvas create rectangle $barStart $barY $barEnd [expr {$barY + $barHeight}] \
				-outline [::colors::lookup table,disabledforeground]
		} else {
			set x $barStart
			foreach {value color} [list $wins $winColor $draws $drawColor $losses $lossColor] {
				if {$value > 0} {
					set w [expr {$barWidth*$value/$decided}]
					$canvas create rectangle $x $barY [expr {$x + $w}] [expr {$barY + $barHeight}] \
						-fill $color -outline $color
					incr x $w
				}
			}
		}
		$canvas create text [expr {$barEnd + 8}] $y -anchor w -font TkDefaultFont \
			-fill $foreground -text "[formatPercent $score]%"
	}
}


# Double-click on an opening row: those games in the database switcher.
proc ::insights::OpenSelectedOpeningInSwitcher {dlg} {
	variable Data
	variable mc

	if {![winfo exists $dlg]} { return 0 }

	set eco {}
	foreach section {openings weakest} {
		set selection [$Data($dlg,trees:$section) selection]
		if {[llength $selection]} {
			set eco [lindex [$Data($dlg,trees:$section) item [lindex $selection 0] -values] 0]
			break
		}
	}
	if {$eco eq "" || $eco eq "?"} {
		::dialog::info -parent $dlg -message $mc::NoSelection
		return 0
	}

	set base $Data($dlg,base)
	set variant $Data($dlg,variant)
	set label [string trim "$Data($dlg,playerName) $eco"]
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]

	set rc [catch {
		::scidb::view::search $base $variant $view null none \
			[list AND [list player $Data($dlg,playerIndex)] [list eco $eco]]
		::application::database::OpenFilteredViewInSwitcher $dlg $base $variant $view insights $label
	} result options]
	catch { ::scidb::view::close $base $variant $view }
	return -options $options $result
}


proc ::insights::Destroy {dlg widget} {
	variable Data

	if {$widget ne $dlg} { return }
	if {[info exists Data($dlg,token)]} { CancelCollect $Data($dlg,token) }
	foreach key [array names Data $dlg,*] { unset Data($key) }
}


proc ::insights::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::insights::WriteOptions

# vi:set ts=3 sw=3:
