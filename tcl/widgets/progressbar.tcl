# ======================================================================
# Author : $Author$
# Version: $Revision: 609 $
# Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
# Url    : $URL$
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

namespace eval widget {
namespace eval progressbar {

proc build {parent} {
	set w $parent._progress_
	tk::canvas $w -width 259 -height 20 -bg white -relief sunken -border 2
	$w create rectangle 0 0 0 16 -fill blue -outline blue -tags bar
	return $w
}


proc update {parent n} {
	$parent._progress_ coords bar 0 0 $n 16
}

} ;# namespace progressbar
} ;# namespace widget

# vi:set ts=3 sw=3:
