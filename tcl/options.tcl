# ======================================================================
# Author : $Author$
# Version: $Revision: 1520 $
# Date   : $Date: 2018-09-12 06:22:56 -0400 (Wed, 12 Sep 2018) $
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
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source options

namespace eval options {

namespace import ::tcl::mathfunc::max

array set WriteCallbacks {}
array set TableCallbacks {}

variable TableSaveCallbacks {}
variable TableRestoreCallbacks {}
variable TableCompareCallbacks {}
variable TempSuffix "927568377322.tmp"


proc sourceFile {{variant ""}} {
	set filename [MakeFilename $variant]
	if {![file readable $filename]} { return 0 }
	ProvideNamespaces $filename
	::load::source $filename \
		-message $::load::mc::ReadingFile(options) \
		-encoding utf-8 \
		-throw 1 \
		;
	return 1
}


# A saved file can name options of a feature that has since been removed
# (::gamereview::Options after the Game Review window went): setting them
# failed with "parent namespace doesn't exist" and the app never started.
# Create such namespaces so the stale values load harmlessly; the next save
# writes only the options that are still registered.
proc ProvideNamespaces {filename} {
	if {[catch {
		set fd [open $filename r]
		fconfigure $fd -encoding utf-8
		set data [read $fd]
		close $fd
	}]} { return }
	foreach {_ ns} [regexp -all -inline -line {^\s*(?:array\s+)?set\s+(::[A-Za-z0-9_:]+)::[^\s:(]+} $data] {
		if {![namespace exists $ns]} { namespace eval $ns {} }
	}
}


proc deleteFiles {} {
	set filename [MakeFilename]
	if {[file exists $filename]} { file rename -force $filename $filename.bak }

	foreach variant $::layoutVariants {
		set filename [MakeFilename $variant]
		if {[file exists $filename]} { file rename -force $filename $filename.bak }
	}
}


proc recoverFiles {} {
	set filename [MakeFilename]
	if {[file exists $filename.bak]} { file rename -force $filename.bak $filename }

	foreach variant $::layoutVariants {
		set filename [MakeFilename $variant]
		if {[file exists $filename.bak]} { file rename -force $filename.bak $filename }
	}
}


proc hookWriter {callback {file options}} {
	variable WriteCallbacks

	if {![info exists WriteCallbacks($file)]} {
		set i -1
	} else {
		set i [lsearch -exact $WriteCallbacks($file) $callback]
	}
	if {$i == -1} { lappend WriteCallbacks($file) $callback }
}


proc hookTableWriter {callback {file options}} {
	variable TableCallbacks

	if {![info exists TableCallbacks($file)]} {
		set i -1
	} else {
		set i [lsearch -exact $TableCallbacks($file) $callback]
	}
	if {$i == -1} { lappend TableCallbacks($file) $callback }
}


proc unhookWriter {callback {file options}} {
	variable WriteCallbacks

	if {[info exists WriteCallbacks($file)]} {
		set i [lsearch -exact $WriteCallbacks($file) $callback]
		if {$i >= 0} { set WriteCallbacks($file) [lreplace $WriteCallbacks($file) $i $i] }
	}
}


proc writeHeader {chan file} {
	puts $chan "# Scidb $file file"
	puts $chan "# Version: $::scidb::version"
	puts $chan "# Syntax: Tcl language format"
	puts $chan ""
}


proc startTransaction {} {
	# a transaction that failed half way is cleaned up, not forgotten
	abortTransaction
}


# Closes every channel of the transaction and removes its temporary files;
# the option files stay as they were.
proc abortTransaction {} {
	variable TempSuffix
	variable fd_

	foreach filename [array names fd_] {
		catch { close $fd_($filename) }
		catch { file delete -- $filename.$TempSuffix }
	}
	array unset fd_
}


# Replaces the option files only when every one was written completely
# (a full disk shows at close); otherwise none is replaced.
proc endTransaction {} {
	variable TempSuffix
	variable fd_

	set files [array names fd_]
	set failed {}
	foreach filename $files {
		if {[catch { close $fd_($filename) } err] && ![llength $failed]} {
			set failed [list $filename $err]
		}
	}
	array unset fd_
	if {[llength $failed]} {
		foreach filename $files { catch { file delete -- $filename.$TempSuffix } }
		error "cannot write [lindex $failed 0]: [lindex $failed 1]"
	}
	foreach filename $files {
		file rename -force $filename.$TempSuffix $filename
	}
}


proc saveOptionsFile {} {
	variable TempSuffix
	variable WriteCallbacks
	variable fd_

	foreach file [array names WriteCallbacks] {
		set filename [set ::scidb::file::$file]
		set fd_($filename) [set chan [open $filename.$TempSuffix w]]
		fconfigure $chan -encoding utf-8
		writeHeader $chan $file
		# a failing writer leaves no open channel and no temporary file
		if {[catch { foreach callback $WriteCallbacks($file) { {*}$callback $chan } } err opts]} {
			abortTransaction
			return -options $opts $err
		}
	}
}


proc saveTableOptionsFile {variant} {
	variable TempSuffix
	variable TableCallbacks
	variable fd_

	foreach file [array names TableCallbacks] {
		set filename [MakeFilename $variant]
		file mkdir [file dirname $filename]
		set fd_($filename) [set chan [open $filename.$TempSuffix w]]
		fconfigure $chan -encoding utf-8
		if {[catch {
			foreach callback $TableCallbacks($file) { {*}$callback $chan $variant }
			SaveToolbarOptions $chan $variant [::toolbar::toolbarIds]
		} err opts]} {
			abortTransaction
			return -options $opts $err
		}
	}
}


proc writeTableOptions {chan id variant} {
	variable TableCallbacks

	if {[info exists TableCallbacks(options)]} {
		foreach callback $TableCallbacks(options) { {*}$callback $chan $variant $id }
	}
	SaveToolbarOptions $chan $variant [::toolbar::getIdsForLayout $id]
}


proc writeEvalNS {chan namespace} {
	puts $chan "namespace eval $namespace {}"
}


proc writeItem {chan var {lowercaseOnly 1}} {
	if {[array exists $var]} {
		puts $chan "array set $var {"
		writeArray $chan [array get $var] $lowercaseOnly
		puts $chan "}"
	} elseif {[info exists $var]} {
		if {[set $var] eq ""} {
			puts $chan "set $var {}"
		} else {
			puts $chan [list set $var [set $var]]
		}
	}
}


proc writeList {chan var} {
	if {[llength [set $var]] == 0} {
		puts $chan "set $var {}"
	} else {
		puts $chan [list set $var [set $var]]
	}
}


proc writeArray {chan arr {lowercaseOnly 1}} {
	set maxlength 0
	foreach {key val} $arr {
		set length [string length [list $key]]
		set maxlength [max $maxlength $length]
	}
	set lst {}
	foreach {key val} $arr { lappend lst [list $key $val] }
	foreach elem [lsort -index 0 $lst] {
		lassign $elem key val
		if {!$lowercaseOnly || ![string is upper [string index $key 0]]} {
			set key [list $key]
			set spaces [string repeat " " [expr {$maxlength - [string length $key] + 1}]]
			if {[string trim $val] eq ""} {
				puts $chan "  $key$spaces{}"
			} else {
				puts $chan "  $key$spaces[list $val]"
			}
		}
	}
}


proc hookSaveOptions {saveCallback restoreCallback compareCallback} {
	variable TableSaveCallbacks
	variable TableRestoreCallbacks 
	variable TableCompareCallbacks

	lappend TableSaveCallbacks $saveCallback
	lappend TableRestoreCallbacks $restoreCallback
	lappend TableCompareCallbacks $compareCallback
}


proc save {twm variant} {
	variable TableSaveCallbacks
	foreach callback $TableSaveCallbacks { {*}$callback $twm $variant }
}


proc restore {twm variant} {
	variable TableRestoreCallbacks
	foreach callback $TableRestoreCallbacks { {*}$callback $twm $variant }
}


proc compare {twm variant} {
	variable TableCompareCallbacks

	foreach callback $TableCompareCallbacks {
		if {![{*}$callback $twm $variant]} { return false }
	}
	return true
}


proc SaveToolbarOptions {chan variant toolbarIds} {
	foreach id $toolbarIds {
		puts $chan "::toolbar::setOptions $id {"
		writeArray $chan [::toolbar::getOptions $id]
		puts $chan "}"
	}
}


proc MakeFilename {{variant ""}} {
	set filename $::scidb::file::options
	if {[string length $variant]} {
		set dir [file join [file dirname $::scidb::file::options] $variant]
		set filename [file join $dir [file tail $::scidb::file::options]]
	}
	return $filename
}


} ;# namespace options


if {[::process::testOption recover-options]} {
	::options::recoverFiles
} elseif {[::process::testOption first-time]} {
	::options::deleteFiles
}
# vi:set ts=3 sw=3:
