# ======================================================================
# ::game::clipboard -- copy and paste games between databases
#
# Decision 006 (user 2026-10-19): the game-row context menu copies the
# selected games into a clipboard that remembers exactly those games
# (base, variant, game numbers). Pasting copies only those games into the
# database that has focus; it never copies the rest of the Clipbase.
#
# The clipboard is independent of the Clipbase: copying does not modify
# any database, and pasting does not read the Clipbase.
#
#   ::game::clipboard::copy <base> <variant> <numbers>
#   ::game::clipboard::paste ?<base> <variant>?
#   ::game::clipboard::count
#   ::game::clipboard::hidden?
#   ::game::clipboard::reason <base> <variant>
# ======================================================================

package require Tcl 8.5

namespace eval ::game::clipboard {
	variable Games {}
	variable Label ""
	variable LastPath ""

	namespace export copy paste count hidden? reason
}

namespace eval ::game::clipboard::mc {
	set CopyGame		"Copy Game"
	set CopyGames		"Copy Games"
	set PasteGames		"Paste Game(s)"
	set NothingToPaste	"Nothing has been copied."
	set Pasted			"Pasted %d game(s)."
	set ReadOnly		"Cannot paste into '%s': the database is read-only."
	set NoVariant		"Cannot paste into '%s': the game variant is not supported."
	set NoTarget		"Cannot paste: no database has focus."
	set UnknownGame		"Cannot copy: game %s does not exist."
}


# Remember exactly these games. <numbers> are 0-based game numbers in
# <base>/<variant>. Returns the number of games remembered.
proc ::game::clipboard::copy {base variant numbers} {
	variable Games
	variable Label

	if {$base eq ""} {
		return -code error "cannot copy: no database"
	}
	if {![llength $numbers]} {
		return -code error "cannot copy: no game selected"
	}
	set count [::scidb::db::count games $base $variant]
	set clean {}
	foreach number $numbers {
		if {![string is integer -strict $number] || $number < 0 || $number >= $count} {
			return -code error [format $mc::UnknownGame $number]
		}
		if {$number ni $clean} { lappend clean $number }
	}
	if {![llength $clean]} {
		return -code error "cannot copy: no game selected"
	}
	set Games [list [list $base $variant $clean]]
	set Label [expr {[llength $clean] == 1 ? $mc::CopyGame : $mc::CopyGames}]
	return [llength $clean]
}


# Remember several (base, variant, numbers) entries, e.g. a selection
# that spans games loaded from more than one database.
proc ::game::clipboard::copyEntries {entries} {
	variable Games
	variable Label

	set stored {}
	set total 0
	foreach entry $entries {
		lassign $entry base variant numbers
		if {$base eq "" || ![llength $numbers]} { continue }
		set count [::scidb::db::count games $base $variant]
		set clean {}
		foreach number $numbers {
			if {![string is integer -strict $number] || $number < 0 || $number >= $count} {
				return -code error [format $mc::UnknownGame $number]
			}
			if {$number ni $clean} { lappend clean $number }
		}
		if {[llength $clean]} {
			lappend stored [list $base $variant $clean]
			incr total [llength $clean]
		}
	}
	if {![llength $stored]} {
		return -code error "cannot copy: no game selected"
	}
	set Games $stored
	set Label [expr {$total == 1 ? $mc::CopyGame : $mc::CopyGames}]
	return $total
}


proc ::game::clipboard::count {} {
	variable Games
	set n 0
	foreach entry $Games { incr n [llength [lindex $entry 2]] }
	return $n
}


proc ::game::clipboard::entries {} {
	variable Games
	return $Games
}


proc ::game::clipboard::clear {} {
	variable Games
	variable Label
	set Games {}
	set Label ""
	return
}


# The paste entry is hidden when nothing was copied.
proc ::game::clipboard::hidden? {} {
	return [expr {[count] == 0}]
}


# Why a paste into this target cannot run, or "" when it can.
proc ::game::clipboard::reason {{base ""} {variant ""}} {
	variable Games

	if {[count] == 0} { return $mc::NothingToPaste }
	if {$base eq ""} { set base [::scidb::db::get name] }
	if {$base eq ""} { return $mc::NoTarget }
	if {$variant eq ""} { set variant [::scidb::db::get variant?] }
	if {[catch { ::scidb::db::get readonly? $base $variant } ro]} { set ro 0 }
	if {$ro} { return [format $mc::ReadOnly [::util::databaseName $base]] }
	set variants {}
	catch { set variants [::scidb::db::get variants $base] }
	foreach entry $Games {
		set v [lindex $entry 1]
		if {[llength $variants] && $v ni $variants} {
			return [format $mc::NoVariant [::util::databaseName $base]]
		}
	}
	return ""
}


# Copy exactly the remembered games into <base>/<variant>. Returns the
# number of games pasted.
proc ::game::clipboard::paste {{base ""} {variant ""} {confirm {}}} {
	variable Games

	if {[count] == 0} {
		return -code error $mc::NothingToPaste
	}
	if {$base eq ""} { set base [::scidb::db::get name] }
	if {$base eq ""} { return -code error $mc::NoTarget }
	if {$variant eq ""} { set variant [::scidb::db::get variant?] }

	set why [reason $base $variant]
	if {$why ne ""} { return -code error $why }

	set total [count]
	if {$total > 1} {
		set ask $confirm
		if {$ask eq ""} { set ask $::action::BulkHook }
		if {$ask ne ""} {
			set what [format "paste %d games into '%s'?" $total [::util::databaseName $base]]
			if {[catch { {*}$ask $what } answer]} { set answer 0 }
			if {!$answer} { return -code error "declined" }
		}
	}

	set pasted 0
	foreach entry $Games {
		lassign $entry src srcVariant numbers
		# view::copy reads the source in its own variant; reason() has
		# already checked that the target supports that variant.
		set view [::scidb::view::new $src $srcVariant unused unused unused unused master slave]
		if {[catch {
			::scidb::view::setGames $src $srcVariant $view $numbers
			set before [::scidb::db::count games $base $srcVariant]
			set n [::scidb::view::copy $src $view $base $srcVariant {} \
				[namespace current]::NoProgress {} [namespace current]::LogCopy {}]
			if {![string is integer -strict $n] || $n < 0} {
				set n [expr {[::scidb::db::count games $base $srcVariant] - $before}]
			}
			incr pasted $n
		} msg]} {
			catch { ::scidb::view::close $src $srcVariant $view }
			return -code error $msg
		}
		catch { ::scidb::view::close $src $srcVariant $view }
	}

	if {[catch { ::ui::message [format $mc::Pasted $pasted] }]} {
		catch { ::log::info clipboard [format $mc::Pasted $pasted] }
	}
	return $pasted
}


proc ::game::clipboard::NoProgress {args} { return 0 }
proc ::game::clipboard::LogCopy {args} { return 0 }


# The game numbers of the selected rows in a game list, 0-based in the
# database. A game list currently has one selected row; <extra> carries
# additional rows for a multi-selection when the table grows one.
proc ::game::clipboard::selection {path base variant view {extra {}}} {
	variable LastPath
	set LastPath $path
	set numbers $extra
	set row [::scrolledtable::selection $path]
	if {$row >= 0} {
		lassign [::scidb::db::get gameInfo $row $view $base $variant] number
		if {[string is integer -strict $number]} {
			set number [expr {$number - 1}]
			if {$number ni $numbers} { lappend numbers $number }
		}
	}
	return $numbers
}


# The game that is loaded, as {base variant number}, for the assistant.
proc ::game::clipboard::currentGame {} {
	set pos [::scidb::game::current]
	if {$pos < 0} { return {} }
	set list [::game::gameList]
	if {$pos >= [llength $list]} { return {} }
	lassign [lindex $list $pos] base variant number
	return [list $base $variant $number]
}


proc ::game::clipboard::DoCopy {cargs} {
	variable LastPath

	set base [expr {[dict exists $cargs base] ? [dict get $cargs base] : ""}]
	set variant [expr {[dict exists $cargs variant] ? [dict get $cargs variant] : ""}]
	set numbers [expr {[dict exists $cargs numbers] ? [dict get $cargs numbers] : {}}]
	set target [expr {[dict exists $cargs database] ? [dict get $cargs database] : ""}]

	if {$base eq "" || ![llength $numbers]} {
		lassign [currentGame] base variant number
		if {![llength $numbers] && [string is integer -strict $number]} {
			set numbers [list $number]
		}
	}
	if {$variant eq ""} { set variant Normal }

	set n [copy $base $variant $numbers]
	if {$target ne ""} {
		paste $target $variant
	}
	return "copied $n game(s) into the clipboard"
}


proc ::game::clipboard::DoPaste {cargs} {
	set base [expr {[dict exists $cargs base] ? [dict get $cargs base] : ""}]
	set variant [expr {[dict exists $cargs variant] ? [dict get $cargs variant] : ""}]
	set n [paste $base $variant]
	return [format $mc::Pasted $n]
}


proc ::game::clipboard::Register {} {
	::action::register game.copy [dict create \
		label game.copy \
		object {} \
		args {
			{base {type string default {}}}
			{variant {type string default {}}}
			{numbers {type array items integer default {}}}
			{database {type string default {}}}
		} \
		handler ::game::clipboard::DoCopy \
		what "copy these games" \
		ai 1 \
		doc "Copy the selected games (base, variant, numbers) into the game clipboard; optionally also paste them into 'database'." \
	]
	::action::register game.paste [dict create \
		label game.paste \
		object {} \
		args {
			{base {type string default {}}}
			{variant {type string default {}}}
		} \
		handler ::game::clipboard::DoPaste \
		what "paste the copied games" \
		ai 1 \
		doc "Paste exactly the games in the game clipboard into the database that has focus (or 'base'); read-only and unsupported variants are refused." \
	]
	return
}

::game::clipboard::Register

# vi:set ts=3 sw=3:
