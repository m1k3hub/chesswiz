# ======================================================================
# Author : $Author$
# Version: $Revision: 1 $
# Date   : $Date: 2026-08-24 $
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
# Copyright: (C) 2026 scidb-beta
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

# ======================================================================
# ICCF XFCC (XML-Friendly Chess Connection) Protocol Client
#
# This is a STUB module. The actual implementation requires:
# - XFCC protocol specification from ICCF
# - ICCF test credentials (player ID + API password)
# - TLS package for HTTPS support
#
# See ICCF_XFCC_DESIGN.md for the full design document.
# ======================================================================

::util::source iccf-xfcc

namespace eval iccf {
namespace eval xfcc {
namespace eval mc {

set NotConfigured		"ICCF XFCC client is not configured. Set your ICCF player ID and API password."
set ConnectionFailed	"Failed to connect to ICCF server: %s"
set SubmitFailed		"Failed to submit move to ICCF server: %s"
set SyncFailed			"Failed to sync games from ICCF server: %s"
set NotYetImplemented	"ICCF XFCC integration is not yet implemented. See ICCF_XFCC_DESIGN.md."

} ;# namespace mc

variable Config
array set Config {
	playerId		""
	password		""
	endpoint		"https://www.iccf.com/xfcc/"
	configured	0
}


proc configure {playerId password {endpoint ""}} {
	variable Config

	set Config(playerId) $playerId
	set Config(password) $password
	if {[string length $endpoint]} { set Config(endpoint) $endpoint }
	set Config(configured) [expr {[string length $playerId] && [string length $password]}]
}


proc configured? {} {
	variable Config
	return $Config(configured)
}


proc getGames {{filter "all"}} {
	variable mc::NotYetImplemented
	error $NotYetImplemented
}


proc getGame {gameId} {
	variable mc::NotYetImplemented
	error $NotYetImplemented
}


proc submitMove {gameId san} {
	variable mc::NotYetImplemented
	error $NotYetImplemented
}


proc getEvents {} {
	variable mc::NotYetImplemented
	error $NotYetImplemented
}


# ======================================================================
# XML parsing helpers (implemented — can be tested without a server)
# ======================================================================


proc parseGamesXml {xml} {
	# Parse XFCC <games> XML response.
	# Returns a list of dicts with keys: id, status, white, black,
	# whiteTimeLeft, blackTimeLeft, lastMove, toMove.
	set result {}
	set parsed [::scidb::misc::xml toList $xml]

	foreach node $parsed {
		lassign $node tag attrs content
		if {$tag eq "games"} {
			foreach game $content {
				lassign $game gtag gattrs gcontent
				if {$gtag eq "game"} {
					set dict {}
					foreach {k v} $gattrs {
						switch $k {
							id - status - white - black - whiteTimeLeft -
							blackTimeLeft - lastMove - toMove {
								lappend dict $k $v
							}
						}
					}
					if {[llength $dict]} { lappend result $dict }
				}
			}
		}
	}
	return $result
}


proc parseGameXml {xml} {
	# Parse XFCC <game> XML response (full game detail with moves).
	# Returns a dict with game metadata and a 'moves' key containing
	# a list of move dicts.
	set parsed [::scidb::misc::xml toList $xml]

	foreach node $parsed {
		lassign $node tag attrs content
		if {$tag eq "game"} {
			set result {}
			foreach {k v} $attrs {
				lappend result $k $v
			}
			set moves {}
			foreach child $content {
				lassign $child ctag cattrs ccontent
				if {$ctag eq "moves"} {
					foreach move $ccontent {
						lassign $move mtag mattrs mcontent
						if {$mtag eq "move"} {
							lappend moves $mattrs
						}
					}
				}
			}
			lappend result moves $moves
			return $result
		}
	}
	return {}
}


proc parseResultXml {xml} {
	# Parse XFCC <result> XML response (move submission confirmation).
	# Returns a dict with: success (bool), gameId, move, message (if any).
	set parsed [::scidb::misc::xml toList $xml]

	foreach node $parsed {
		lassign $node tag attrs content
		if {$tag eq "result"} {
			set result {}
			foreach {k v} $attrs {
				lappend result $k $v
			}
			return $result
		}
	}
	return {}
}

} ;# namespace xfcc
} ;# namespace iccf

# vi:set ts=3 sw=3: