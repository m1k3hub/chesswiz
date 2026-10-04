# ======================================================================
# Author : $Author$
# Version: $Revision: 1507 $
# Date   : $Date: 2018-08-13 08:17:53 -0400 (Mon, 13 Aug 2018) $
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
# Copyright: (C) 2012-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

namespace eval util {
namespace eval photos {
namespace eval mc {}

# Kept for compatibility with any caller checking busy status
proc busy? {} {
	return 0
}


proc get {name {info {}}} {
	set file [findPhotoFile $name]
	set found $file
	set img ""

	if {[string length $found] == 0 && [llength $info]} {
		set aliases [lindex $info 20]

		foreach alias $aliases {
			set file [findPhotoFile $alias]
			if {[string length $file]} {
				set found $file
				break
			}
		}
	}

	if {[string length $found] > 0} {
		catch { set img [image create photo -data [::file::read $found -translation binary]] }
	}

	return $img
}


proc findPhotoFile {name} {
	set key [NormalizeName $name]
	set dir [string index $key 0]
	if {![string match {[a-z]} $dir]} { return "" }
	set path [file join $::scidb::dir::user photos $dir $key]
	if {[file readable $path]} { return $path }
	set path [file join $::scidb::dir::photos $dir $key]
	if {[file readable $path]} { return $path }
	return ""
}


proc NormalizeName {name} {
	set key [string map {. "" " " "" - ""} [string tolower $name]]
	set index [string last ",dr" $key]
	if {$index >= 0} { set key [string range $key 0 [expr {$index - 1}]] }
	return $key
}

} ;# namespace photos
} ;# namespace util

# vi:set ts=3 sw=3:
