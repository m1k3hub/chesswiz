# ======================================================================
# Author : $Author$
# Version: $Revision: 1289 $
# Date   : $Date: 2017-07-12 15:11:19 -0400 (Wed, 12 Jul 2017) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2010-2013 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source load-management

namespace eval load {
namespace eval mc {

set SevereError				"Severe error during load of ECO file"
set FileIsCorrupt 			"File %s is corrupt:"
set ProgramAborting			"Program is aborting."
set EngineSetupFailed		"Loading engine configuration failed"

set Loading						"Loading %s"
set StartupFinished			"Startup finished"
set SystemEncoding			"System encoding is '%s'"
set Startup						"Startup"

set ReadingFile(options)	"Reading options file"
set ReadingFile(engines)	"Reading engines file"

set ECOFile						"ECO file"
set EngineFile					"engine file"
set SpellcheckFile			"spell-check file"
set LocalizationFile			"localization file"
set RatingList					"%s rating list"
set WikipediaLinks			"Wikipedia links"
set ChessgamesComLinks		"chessgames.com links"
set Cities						"cities"
set PieceSet					"piece set"
set Theme						"theme"
set Icons						"icons"

}

variable currentFile {}
variable photoFile {}

variable LastMsg	""
variable Log		{}
variable CacheWritable 1
variable CacheHit 0


proc source {path args} {
	variable LastMsg
	variable Log
	variable currentFile

	array set opts { -message "" -encoding "" -throw 0 }
	array set opts $args
	set msg $opts(-message)

	if {[string length $msg]} {
		if {$msg ne $LastMsg} {
			::splash::print "${msg}..."
			set LastMsg $msg
		}
	}

	set currentFile $path
	set enc {}
	if {[string length $opts(-encoding)]} { set enc [list -encoding $opts(-encoding)] }

	if {$opts(-throw)} {
		uplevel ::source {*}$enc [list $path]
	} elseif {[catch {uplevel ::source {*}$enc [list $path]} err]} {
		lappend Log error [format $mc::FileIsCorrupt $path] error $err
	} elseif {[string length $msg]} {
		lappend Log info "$msg: $path"
	}

	update idletasks
}


proc load {msg type path} {
	variable LastMsg
	variable Log

	if {$msg ne $LastMsg} {
		::splash::print "${msg}..."
		set LastMsg $msg
	}

	set currentFile $path

	if {[catch {::scidb::app::load $type $path} err]} {
		set ::load::CacheWritable 0
		set msg [format $mc::FileIsCorrupt $path]
		if {$type eq "eco"} {
			append str $mc::SevereError .\n $msg \n\n $mc::ProgramAborting
			set detail ""
			if {$type eq "eco"} {
				append detail "This error may occur due to a defect executable, caused by a broken linker."
				append detail "\n\n"
				append detail "Please change to your installation directory of Chesswiz and invoke"
				append detail "\n   > make check-build\n"
				append detail "for further details."
			}
			dialog::error -message $str -detail $detail
			exit 1
		} else {
			lappend Log error $msg error $err
		}
		puts "$msg -- $err"
	} else {
		lappend Log info "$msg: $path"
	}

	update idletasks
}


proc writeLog {} {
	variable Log

	::log::info [format $mc::SystemEncoding [encoding system]]
	foreach {type msg} $Log { log::$type $msg }
	array unset Log
	::log::info $mc::StartupFinished
	::log::close
}


proc write {} {
	set chan [open [file join $scidb::dir::config load.tcl] w]
	fconfigure $chan -encoding utf-8

	foreach name [info vars ::load::mc::*] {
		if {[array exists $name]} {
			foreach attr [array names $name] {
				puts $chan "set ${name}($attr) \"[set ${name}($attr)]\""
			}
		} else {
			puts $chan "set $name \"[set $name]\""
		}
	}

	close $chan
}

# The dictionaries were rebuilt (first start, or a rating/link file changed) and
# the cache for the next start is missing. Writing it costs seconds on a slow
# disk, and only the next start needs it, so it is not part of the startup path:
# wait until the main window is up and drawn, then write it.
proc writeCacheWhenUp {start {tries 50}} {
	# Without Tk (plain tclsh) or after five seconds (headless runs) there is no
	# window to wait for, and the write must not be lost.
	if {[llength [info commands winfo]] && $tries > 0
			&& (![winfo exists .application] || ![winfo ismapped .application])} {
		after 100 [list ::load::writeCacheWhenUp $start [expr {$tries - 1}]]
	} else {
		after idle [list ::load::writeCacheNow $start]
	}
}

proc writeCacheNow {start} {
	set written 0
	set begin [clock milliseconds]
	catch {
		file mkdir [file dirname $::load::CachePath]
		set written [::scidb::app::load cache-write $::load::CachePath $::load::CacheSources]
	}
	::debuglog::log startup "player cache write success=$written [expr {[clock milliseconds]-$begin}]ms deferred=[expr {$begin-$start}]ms"
}

} ;# namespace load


if {[file readable [file join $scidb::dir::config load.tcl]]} {
	catch { source -encoding utf-8 [file join $scidb::dir::config load.tcl] }
}


# log will be closed in end.tcl
::log::open "Startup" 0
#set t [clock microseconds]

# --- Load ECO file ----------------------------------------------------
load::load	[format $load::mc::Loading $load::mc::ECOFile] \
				eco \
				[file join $scidb::dir::data eco.bin] \
				;

set ::load::CacheHit 0
set ::load::CacheWritable 1
if {![::process::testOption fast-load]} {
	# Include both FIDE paths so creating/removing the user's downloaded list
	# invalidates a cache made with the shipped list. Preserve load order and
	# distinguish elo-only by its actual source list.
	set ::load::CachePath [file join $::scidb::dir::user cache players.bin]
	set ::load::CacheSources {}
	set ::load::FideList [file join $::scidb::dir::user ratings fide-players.txt]
	if {![file readable $::load::FideList]} {
		set ::load::FideList [file join $::scidb::dir::data players_list.zip]
	}
	foreach name {ratings_utf8.ssp.zip ratings-additional.ssp engines.txt} {
		lappend ::load::CacheSources [file join $::scidb::dir::data $name]
	}
	lappend ::load::CacheSources $::load::FideList
	lappend ::load::CacheSources [file join $::scidb::dir::user ratings fide-players.txt]
	if {![::process::testOption elo-only]} {
		foreach name {ips-ratings.txt dwz-ratings.txt ecf-ratings.txt iccf-ratings.txt} {
			lappend ::load::CacheSources [file join $::scidb::dir::data $name]
		}
	}
	foreach name {wikipedia-de.txt wikipedia-en.txt chessgames.com.zip cities.txt} {
		lappend ::load::CacheSources [file join $::scidb::dir::data $name]
	}
	set cacheStart [clock milliseconds]
	catch { set ::load::CacheHit [::scidb::app::load cache-read $::load::CachePath $::load::CacheSources] }
	::debuglog::log startup "player cache read hit=$::load::CacheHit [expr {[clock milliseconds]-$cacheStart}]ms"
	unset cacheStart
}

if {![::process::testOption fast-load] && !$::load::CacheHit} {

# --- Load spellcheck files --------------------------------------------
foreach file {ratings_utf8.ssp.zip ratings-additional.ssp} {
	load::load	[format $load::mc::Loading $load::mc::SpellcheckFile] \
					ssp \
					[file join $scidb::dir::data $file] \
					;
}

# --- Load engines -----------------------------------------------------
load::load	[format $load::mc::Loading $load::mc::EngineFile] \
				comp \
				[file join $scidb::dir::data engines.txt] \
				;

# --- Load FIDE players ------------------------------------------------
# FIDE's current list, when the user fetched it (player-data.tcl), replaces
# the shipped one of 2012
set fideList $::load::FideList
load::load	[format $load::mc::Loading [format $load::mc::RatingList FIDE]] \
				fide \
				$fideList \
				;
unset fideList

if {![::process::testOption elo-only]} {

# --- Load rating lists ------------------------------------------------
foreach rating {IPS DWZ ECF ICCF} {
	set type [string tolower $rating]
	load::load	[format $load::mc::Loading [format $load::mc::RatingList $rating]] \
					$type \
					[file join $scidb::dir::data $type-ratings.txt] \
					;
}

} ;# if elo-only

# --- Load Wikipedia links ---------------------------------------------
foreach lang {de en} {
	load::load	[format $load::mc::Loading $load::mc::WikipediaLinks] \
					wiki \
					[file join $scidb::dir::data wikipedia-${lang}.txt] \
					;
}

# --- Load chessgames.com links ----------------------------------------
load::load	[format $load::mc::Loading $load::mc::ChessgamesComLinks] \
				cgdc \
				[file join $scidb::dir::data chessgames.com.zip] \
				;

# --- Load cities ------------------------------------------------------
load::load	[format $load::mc::Loading $load::mc::Cities] \
				site \
				[file join $scidb::dir::data cities.txt] \
				;

} ;# if fast-load

# --- Load localization file -------------------------------------------
set file [file join $scidb::dir::share lang localization.tcl]
if {[file readable $file]} {
	load::source $file -message [format $load::mc::Loading $load::mc::LocalizationFile] -encoding utf-8
}

# --- Load piece sets --------------------------------------------------
foreach file [glob -directory [file join $::scidb::dir::share pieces] -nocomplain *.tcl] {
	load::source $file -message [format $load::mc::Loading $load::mc::PieceSet]
}

set msg [format $load::mc::Loading $load::mc::Theme]

# --- Load themes ------------------------------------------------------
### Upgrade #######################################
set update 0
if {	[file exists [file join $::scidb::dir::user themes StonyGlass.dat]]
	|| [file exists [file join $::scidb::dir::user themes Mayan-1.dat]]} {
	file delete [file join $::scidb::dir::user themes BlueMono.dat]
	file delete [file join $::scidb::dir::user themes Blue.dat]
	file delete [file join $::scidb::dir::user themes Glassy&Red.dat]
	file delete [file join $::scidb::dir::user themes Marble.dat]
	file delete [file join $::scidb::dir::user themes Marmor.dat]
	file delete [file join $::scidb::dir::user themes Mayan-1.dat]
	file delete [file join $::scidb::dir::user themes Mayan-2.dat]
	file delete [file join $::scidb::dir::user themes Phoenix.dat]
	file delete [file join $::scidb::dir::user themes StonyGlass.dat]
	file delete [file join $::scidb::dir::user themes Wood.dat]
	file delete [file join $::scidb::dir::user themes square Blue.dat]
	file delete [file join $::scidb::dir::user themes square BlueMono.dat]
	file delete [file join $::scidb::dir::user themes square Marble-Classic.dat]
	file delete [file join $::scidb::dir::user themes square Marble-Red.dat]
	file delete [file join $::scidb::dir::user themes square Wood-Green.dat]
	file delete [file join $::scidb::dir::user themes piece MayanRed.dat]
	file delete [file join $::scidb::dir::user themes piece Yellow.dat]
	set update 1
}
if {[file exists [file join $::scidb::dir::user themes square Brown-Wood.dat]]} {
	file delete [file join $::scidb::dir::user themes square Brown-Wood.dat]
	set update 1
}
if {[file exists [file join $::scidb::dir::user themes BlueTheme.dat]]} {
	file delete [file join $::scidb::dir::user themes BlueTheme.dat]
	file delete [file join $::scidb::dir::user themes square BlueTheme.dat]
	set update 1
}
if {[file exists [file join $::scidb::dir::user themes Virtual.dat]]} {
	file delete [file join $::scidb::dir::user themes Virtual.dat]
	file delete [file join $::scidb::dir::user themes VirtualColored.dat]
}
if {	![file exists [file join $::scidb::dir::user themes Primus.dat]]
	|| ![file exists [file join $::scidb::dir::user themes Country-Style.dat]]
	|| ![file exists [file join $::scidb::dir::user themes Blackjack.dat]]
	|| ![file exists [file join $::scidb::dir::user themes VirtualBlue.dat]]
	|| ![file exists [file join $::scidb::dir::user themes Burnt.dat]]
	|| ![file exists [file join $::scidb::dir::user themes Creepy.dat]]
	|| ![file exists [file join $::scidb::dir::user themes NordicFrost.dat]]} {
	set update 1
}
if {[::process::testOption first-time]} {
	set update 1
}
if {[::process::testOption update-themes]} {
	set update 1
}
if {$update} { ::scidb::themes::update }
if {[file exists [file join $::scidb::dir::user themes square Wood-Green.dat]]} {
	file delete [file join $::scidb::dir::user themes square Wood-Green.dat]
}
if {[file exists [file join $::scidb::dir::user themes square Brown-Wood.dat]]} {
	file delete [file join $::scidb::dir::user themes square Brown-Wood.dat]
}
unset update
###################################################

foreach subdir {piece square {}} {
	foreach file [glob -directory [file join $::scidb::dir::user themes {*}$subdir] -nocomplain *.dat] {
		load::source $file -message $msg
	}
}

set file [file join $::scidb::dir::share textures preferences.dat]
if {[file readable $file]} { load::source $file }

###################################################

set msg [format $load::mc::Loading "Ttk $load::mc::Theme"]
foreach file [glob -directory [file join $::scidb::dir::share themes ttk] -nocomplain *.tcl] {
	load::source $file -message $msg
}

# --- Load done --------------------------------------------------------
unset file subdir msg
set cacheStart [clock milliseconds]
::scidb::app::load done
::debuglog::log startup "player/site loadDone [expr {[clock milliseconds]-$cacheStart}]ms"
if {![::process::testOption fast-load] && !$::load::CacheHit && $::load::CacheWritable} {
	set cacheStart [clock milliseconds]
	# Deferred: the window must not wait for the cache write (see writeCacheWhenUp).
	after 0 [list ::load::writeCacheWhenUp $cacheStart]
	unset cacheStart
}

#puts "[expr {[clock microseconds] - $t}] micro-secs"
#unset t

# Load time with empty cache: 6.76 s
# Load time with full cache:  2.68 s

# Load time of ECO file with empty cache: 0.51 s
# Load time of ECO file with full cache:  0.36 s

# vi:set ts=3 sw=3:
