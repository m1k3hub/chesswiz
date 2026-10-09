# ======================================================================
# ::playerdata -- the player dictionary's rating lists, kept current from
# their authoritative sources (player data plan, step 1: FIDE).
#
# Scidb ships FIDE's list of March 2012. FIDE publishes its combined list
# (standard, rapid, blitz; ID, name, federation, sex, titles, birth year)
# every month at ratings.fide.com. On request -- it is a download from the
# internet, never automatic -- the list is fetched, filtered to the players
# the dictionary keeps (rated 1800 or more in any of the three, or titled;
# about 250,000 of 1.9 million) into the user directory, and loaded into the
# running dictionary; at startup it replaces the shipped list. FIDE's
# spelling and federation win over the old ones; nothing is written into a
# database.
#
#   ::playerdata::fideFile              -> the updated list in the user directory
#   ::playerdata::fideInfo              -> {date D players N} of the update, or {}
#   ::playerdata::updateFide <parent> ?-confirm 0|1? ?-done CMD?
#       CMD gets {ok 1 players N read M} or {ok 0 error E}
#   ::playerdata::install <zip>         filter and load a downloaded list
#
# Names in a database are linked to the lists' entries when the database
# opens: exactly, or -- step 3 of the plan -- through other spellings
# (::scidb::db::linkPlayers: extra given names or a cut patronymic,
# initials, numbered namesakes, homonyms told apart by the games' Elo),
# only where the evidence agrees; the rest is left alone. A link changes
# what the player card and searches show, never the database.
#
#   ::playerdata::link <base>           link the names of an open database
#   ::playerdata::linkOpen              ... of every open database
#   ::playerdata::lastLink <base>       -> {linked N ambiguous {name ...}}
#
# What the rules leave is mostly other transliterations ("Tal, Mihail" for
# "Tal, Mikhail N"). On request -- the names go to the System One backend
# chosen in Extras > AI, possibly a cloud service -- a decision model judges
# whether the spellings name the same person. C++ has already kept only the
# entries of that surname whose initials, sex and rating agree with the games
# (::scidb::db::spellingCandidates); the model judges the name alone, which
# the experiments showed it does well, while it is unreliable on initials and
# Elo. A name is proposed only when exactly one entry reaches the threshold,
# and nothing is linked before the user confirms the list.
#
#   ::playerdata::spellingCheck <base> ?-threshold P? -done CMD
#       CMD gets {ok 1 proposals {{index name fideID entry p} ...} asked N}
#       or {ok 0 error E}
#   ::playerdata::applySpellings <base> <proposals>  -> number linked
#   ::playerdata::checkSpellings <parent>   the menu step for the current base
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source player-data
}

namespace eval playerdata {
namespace eval mc {

set UpdateFide		"Update FIDE Rating List..."
set Confirm			"Download FIDE's current rating list (about 45 MB) from ratings.fide.com?"
set ConfirmDetail	"The list replaces the one Chesswiz ships (March 2012). Only players rated 1800 or more, or titled, are kept. Nothing is sent but the request."
set Downloading	"Downloading FIDE's rating list..."
set Done				"FIDE's rating list of %s is installed: %s players."
set Failed			"The FIDE rating list could not be updated: %s"
set CheckSpellings	"Link Other Spellings of Players..."
set SpellConfirm		"Ask the AI decision model whether %s unlinked player names are other spellings of rating-list entries?"
set SpellConfirmDetail	"The names and their candidates are sent to the System One backend chosen in Extras > AI (%s). Nothing is linked before you confirm."
set SpellNoBackend	"No System One backend is configured (Extras > AI)."
set SpellNothing		"No unlinked player name has a candidate with agreeing initials and rating."
set SpellNone		"None of the %s names could be matched with enough certainty."
set SpellPreview		"Link %s player names to these rating-list entries?"
set SpellMore		"... and %s more"
set SpellDone		"%s player name(s) linked."

} ;# namespace mc

variable Url https://ratings.fide.com/download/players_list.zip
variable Busy 0
# LinkResult(<base>): what the last linking of <base> did
variable LinkResult
array set LinkResult {}
# the probability a spelling must reach (tuned on hand-made cases with
# jev-latest: true variants 0.79..0.98, contradicting names <= 0.15 once
# C++ has checked the initials)
variable SpellThreshold 0.9

} ;# namespace playerdata


proc ::playerdata::Dir {} {
	return [file join $::scidb::dir::user ratings]
}


proc ::playerdata::fideFile {} {
	return [file join [Dir] fide-players.txt]
}


proc ::playerdata::fideInfo {} {
	set file [file join [Dir] fide-players.info]
	if {![file readable $file]} { return {} }
	if {[catch { set chan [open $file]; set info [read $chan]; close $chan }]} { return {} }
	if {![string is list $info] || [llength $info] % 2} { return {} }
	return $info
}


proc ::playerdata::updateFide {parent args} {
	variable Url
	variable Busy
	variable mc

	array set opts {-confirm 1 -done {}}
	array set opts $args

	if {$Busy} { return }
	if {$opts(-confirm)} {
		set reply [::dialog::question -parent $parent -message $mc::Confirm -detail $mc::ConfirmDetail]
		if {$reply ne "yes"} { return }
	}
	set Busy 1
	::log::info "Player data" $mc::Downloading
	::application::download::Get $Url [namespace code [list Fetched $parent $opts(-done)]]
}


proc ::playerdata::Fetched {parent done result} {
	variable Busy
	variable mc

	if {![dict get $result ok]} {
		set Busy 0
		Report $parent $done [dict create ok 0 error [dict get $result error]]
		return
	}
	set zip [file join [Dir] players_list.zip]
	if {[catch {
		file mkdir [Dir]
		set chan [open $zip wb]
		puts -nonewline $chan [dict get $result data]
		close $chan
		set answer [install $zip]
	} err]} {
		set answer [dict create ok 0 error $err]
	}
	catch { file delete $zip }
	set Busy 0
	Report $parent $done $answer
}


# Filter FIDE's players_list.zip (or the text in it) into the user directory
# and load it into the dictionary.
proc ::playerdata::install {zip} {
	file mkdir [Dir]
	set file [fideFile]
	lassign [::scidb::app::filterFideList $zip $file.new] read kept
	file rename -force $file.new $file
	::scidb::app::load fide $file
	::scidb::app::load done
	# the new entries may fit names the old list did not
	linkOpen
	set info [dict create date [clock format [clock seconds] -format %Y-%m-%d] players $kept read $read]
	set chan [open [file join [Dir] fide-players.info] w]
	puts -nonewline $chan $info
	close $chan
	return [dict create ok 1 players $kept read $read]
}


proc ::playerdata::Report {parent done answer} {
	variable mc
	if {[dict get $answer ok]} {
		set text [format $mc::Done [dict get [fideInfo] date] [::locale::formatNumber [dict get $answer players]]]
		::log::info "Player data" $text
		if {![llength $done]} { ::dialog::info -parent $parent -message $text }
	} else {
		set text [format $mc::Failed [dict get $answer error]]
		::log::error "Player data" $text
		if {![llength $done]} { ::dialog::error -parent $parent -message $text }
	}
	if {[llength $done]} { uplevel #0 [list {*}$done $answer] }
}


proc ::playerdata::link {base} {
	variable LinkResult

	if {![llength [info commands ::scidb::db::linkPlayers]]} { return }
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	set linked 0
	set ambiguous {}
	foreach variant $variants {
		if {[catch { ::scidb::db::linkPlayers $base $variant } result]} { continue }
		incr linked [dict get $result linked]
		lappend ambiguous {*}[dict get $result ambiguous]
	}
	set LinkResult($base) [dict create linked $linked ambiguous $ambiguous]
	if {$linked} {
		::log::info "Player data" "[::util::databaseName $base]: $linked more player name(s) linked to the rating lists"
	}
	return $LinkResult($base)
}


proc ::playerdata::linkOpen {} {
	set bases {}
	catch {
		set switcher [::application::database::switcherWidget]
		if {[string length $switcher]} { set bases [$switcher bases] }
	}
	foreach base $bases { catch { link $base } }
}


proc ::playerdata::lastLink {base} {
	variable LinkResult
	if {[info exists LinkResult($base)]} { return $LinkResult($base) }
	return {}
}



proc ::playerdata::SpellQuestion {name entry} {
	return [dict create type noul \
		instructions "Could the chess player name \"$name\" be written for the same person as the rating-list name \"$entry\"? Accept transliteration variants (Mihail/Mikhail, Vasyl/Vassily), dropped patronymics and initials that match a given name; the surname must be the same name." \
		criteria [dict create \
			true "The two forms are compatible spellings of one person's name" \
			false "A given name contradicts, or the names are different names"]]
}


proc ::playerdata::spellingCheck {base args} {
	variable SpellThreshold
	array set opts [list -threshold $SpellThreshold -done {}]
	array set opts $args

	set work {}
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	foreach variant $variants {
		if {[catch { ::scidb::db::spellingCandidates $base $variant } rows]} { continue }
		foreach row $rows { lappend work [list $variant {*}$row] }
	}
	set state [dict create base $base work $work threshold $opts(-threshold) \
		done $opts(-done) proposals {} asked [llength $work]]
	after 0 [list ::playerdata::SpellNext $state]
	return [llength $work]
}


proc ::playerdata::SpellNext {state} {
	set work [dict get $state work]
	if {![llength $work]} {
		uplevel #0 [list {*}[dict get $state done] \
			[list ok 1 proposals [dict get $state proposals] asked [dict get $state asked]]]
		return
	}
	dict set state work [lrange $work 1 end]
	lassign [lindex $work 0] variant index name elo candidates
	set questions {}
	set k 0
	foreach c $candidates {
		dict set questions c[incr k] [SpellQuestion $name [lindex $c 1]]
	}
	::ai::systemone::evaluateAsync $name $questions \
		[list ::playerdata::SpellReply $state [list $variant $index $name $candidates]]
}


proc ::playerdata::SpellReply {state item reply} {
	if {![dict get $reply ok]} {
		uplevel #0 [list {*}[dict get $state done] [list ok 0 error [dict get $reply error]]]
		return
	}
	lassign $item variant index name candidates
	set answers [dict get $reply answers]
	set hits {}
	set k 0
	foreach c $candidates {
		set id c[incr k]
		if {![dict exists $answers $id noul]} { continue }
		set p [dict get $answers $id noul]
		if {$p >= [dict get $state threshold]} { lappend hits [list {*}$c $p] }
	}
	# exactly one entry, or none: two plausible entries are not a decision
	if {[llength $hits] == 1} {
		lassign [lindex $hits 0] fideID entry fed rating p
		dict lappend state proposals [list $variant $index $name $fideID $entry $p]
	}
	after 0 [list ::playerdata::SpellNext $state]
}


proc ::playerdata::applySpellings {base proposals} {
	set linked 0
	foreach prop $proposals {
		lassign $prop variant index name fideID
		if {![catch { ::scidb::db::linkPlayer $base $variant $index $fideID } ok] && $ok} {
			incr linked
		}
	}
	if {$linked} {
		::log::info "Player data" "[::util::databaseName $base]: $linked player name(s) linked as other spellings"
	}
	return $linked
}


proc ::playerdata::checkSpellings {parent} {
	variable mc

	set base [::scidb::db::get name]
	if {![llength [info commands ::ai::systemone::enabled]] || ![::ai::systemone::enabled]} {
		::dialog::info -parent $parent -message $mc::SpellNoBackend
		return
	}
	set count 0
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	foreach variant $variants {
		catch { incr count [llength [::scidb::db::spellingCandidates $base $variant]] }
	}
	if {$count == 0} {
		::dialog::info -parent $parent -message $mc::SpellNothing
		return
	}
	set reply [::dialog::question -parent $parent -default no \
		-message [format $mc::SpellConfirm [::locale::formatNumber $count]] \
		-detail [format $mc::SpellConfirmDetail [::ai::systemone::describe]]]
	if {$reply ne "yes"} { return }
	::widget::busyCursor on
	spellingCheck $base -done [list ::playerdata::SpellPreview $parent $base]
}


proc ::playerdata::SpellPreview {parent base result} {
	variable mc

	::widget::busyCursor off
	if {![dict get $result ok]} {
		::dialog::error -parent $parent -message [dict get $result error]
		return
	}
	set proposals [dict get $result proposals]
	if {![llength $proposals]} {
		::dialog::info -parent $parent \
			-message [format $mc::SpellNone [::locale::formatNumber [dict get $result asked]]]
		return
	}
	set lines {}
	foreach prop [lrange $proposals 0 29] {
		lassign $prop variant index name fideID entry
		lappend lines "$name  \u2192  $entry ($fideID)"
	}
	if {[llength $proposals] > 30} {
		lappend lines [format $mc::SpellMore [expr {[llength $proposals] - 30}]]
	}
	set reply [::dialog::question -parent $parent -default no \
		-message [format $mc::SpellPreview [::locale::formatNumber [llength $proposals]]] \
		-detail [join $lines \n]]
	if {$reply ne "yes"} { return }
	set n [applySpellings $base $proposals]
	::dialog::info -parent $parent -message [format $mc::SpellDone [::locale::formatNumber $n]]
}
