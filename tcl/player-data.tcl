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
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source player-data
}

namespace eval playerdata {
namespace eval mc {

set UpdateFide		"Update FIDE Rating List..."
set Confirm			"Download FIDE's current rating list (about 45 MB) from ratings.fide.com?"
set ConfirmDetail	"The list replaces the one Scidb ships (March 2012). Only players rated 1800 or more, or titled, are kept. Nothing is sent but the request."
set Downloading	"Downloading FIDE's rating list..."
set Done				"FIDE's rating list of %s is installed: %s players."
set Failed			"The FIDE rating list could not be updated: %s"

} ;# namespace mc

variable Url https://ratings.fide.com/download/players_list.zip
variable Busy 0

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
