# ======================================================================
# Author : $Author$
# Version: $Revision: 2 $
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
# SOAP web service at https://www.iccf.com/XfccBasic.asmx
# Spec: http://www.bennedik.de/xfcc/ (XFCC Basic Specification v1.0)
# Reference impl: https://github.com/hauva69/go-chess-xfcc
#
# Operations:
#   GetMyGames  — fetch player's correspondence games
#   MakeAMove   — submit a move (basic)
#   MakeAMove2  — submit a move (with conditional moves)
#
# Authentication: ICCF username + password in SOAP body (not HTTP Basic)
# ======================================================================

::util::source iccf-xfcc

namespace eval iccf {
namespace eval xfcc {
namespace eval mc {

set NotConfigured		"ICCF XFCC client is not configured. Set your ICCF username and password."
set ConnectionFailed	"Failed to connect to ICCF server: %s"
set SubmitFailed		"Failed to submit move to ICCF server: %s"
set SyncFailed			"Failed to sync games from ICCF server: %s"
set AuthFailed			"ICCF authentication failed. Check your username and password."
set TlsNotAvailable	"TLS package not available. Install tcl-tls for HTTPS support."

} ;# namespace mc

variable Config
array set Config {
	username		""
	password		""
	endpoint		"https://www.iccf.com/XfccBasic.asmx"
	host			"www.iccf.com"
	configured	0
	initialized	0
}

# XFCC namespace URI
variable NS "http://www.bennedik.com/webservices/XfccBasic"


# ======================================================================
# Initialization — load TLS and HTTP, register HTTPS
# ======================================================================

proc initTls {} {
	variable Config
	variable mc::TlsNotAvailable

	if {$Config(initialized)} { return 1 }

	# Step 1: Try direct package require (works when auto_path is correct)
	if {[catch {package require tls} version] == 0} {
		set tlsOk 1
	} else {
		# Step 2: Search common TLS package paths across distros
		set tlsOk 0
		set searchPaths {
			/usr/lib/tcltk/x86_64-linux-gnu
			/usr/lib/tcltk/aarch64-linux-gnu
			/usr/lib/tcltk/arm-linux-gnueabihf
			/usr/lib/tcl/tls1.8.0
			/usr/lib/tcl/tls1.7
			/usr/lib64/tcl/tls1.8.0
			/usr/local/lib/tls1.8.0
			/usr/local/lib/tcltls1.8.0
			/opt/local/lib/tls1.8.0
			/Library/Tcl/tls1.8.0
			/Library/Tcl/tls1.7
		}
		# Also check TCLLIBPATH env var (user-set package search path)
		if {[info exists ::env(TCLLIBPATH)]} {
			foreach p $::env(TCLLIBPATH) {
				lappend searchPaths $p
			}
		}
		# Try each path
		foreach path $searchPaths {
			if {![file isdirectory $path]} { continue }
			if {$path ni $::auto_path} { lappend ::auto_path $path }
		}
		# Retry package require with expanded auto_path
		if {[catch {package require tls} version] == 0} {
			set tlsOk 1
		}
	}

	if {!$tlsOk} {
		puts stderr $TlsNotAvailable
		return 0
	}
	if {[catch {package require http}]} {
		puts stderr "HTTP package not available"
		return 0
	}

	::http::register https 443 [list ::tls::socket -servername $Config(host)]
	set Config(initialized) 1
	return 1
}


# ======================================================================
# Configuration
# ======================================================================

proc configure {username password {endpoint ""}} {
	variable Config

	set Config(username) $username
	set Config(password) $password
	if {[string length $endpoint]} {
		set Config(endpoint) $endpoint
		# Extract host from endpoint URL
		set Config(host) [regsub {^https?://([^/]+)/.*} $endpoint {\1}]
	}
	set Config(configured) [expr {[string length $username] && [string length $password]}]
	if {$Config(configured)} { initTls }
}


proc configured? {} {
	variable Config
	return $Config(configured)
}


# ======================================================================
# SOAP envelope builders
# ======================================================================

variable NS "http://www.bennedik.com/webservices/XfccBasic"

proc soapEnvelope {body} {
	variable NS
	return "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<soap:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\">
  <soap:Body>
$body
  </soap:Body>
</soap:Envelope>"
}


proc buildGetMyGames {} {
	variable Config
	variable NS
	return [soapEnvelope "    <GetMyGames xmlns=\"$NS\">
      <username>$Config(username)</username>
      <password>$Config(password)</password>
    </GetMyGames>"]
}


proc buildMakeAMove {gameId move movecount args} {
	variable Config
	variable NS

	array set opts {
		resign		0
		acceptDraw	0
		offerDraw		0
		claimDraw		0
		message		""
	}
	array set opts $args

	return [soapEnvelope "    <MakeAMove xmlns=\"$NS\">
      <username>$Config(username)</username>
      <password>$Config(password)</password>
      <gameId>$gameId</gameId>
      <resign>$opts(resign)</resign>
      <acceptDraw>$opts(acceptDraw)</acceptDraw>
      <movecount>$movecount</movecount>
      <myMove>$move</myMove>
      <offerDraw>$opts(offerDraw)</offerDraw>
      <claimDraw>$opts(claimDraw)</claimDraw>
      <myMessage>$opts(message)</myMessage>
    </MakeAMove>"]
}


# ======================================================================
# HTTP request
# ======================================================================

proc soapRequest {soapAction body} {
	variable Config
	variable mc::ConnectionFailed

	if {![initTls]} {
		error $TlsNotAvailable
	}

	set headers [list \
		"Content-Type" "text/xml; charset=utf-8" \
		"SOAPAction" "$soapAction" \
	]

	if {[catch {
		set token [::http::geturl $Config(endpoint) \
			-timeout 30000 \
			-headers $headers \
			-query $body \
		]
	} err]} {
		error [format $ConnectionFailed $err]
	}

	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::http::data $token]
	::http::cleanup $token

	if {$status ne "ok" || ($code != 200 && $code != 500)} {
		error [format $ConnectionFailed "HTTP $code $status"]
	}

	return $data
}


# ======================================================================
# API: GetMyGames
# ======================================================================

proc getGames {} {
	variable NS
	variable mc::SyncFailed
	variable mc::AuthFailed

	if {![configured?]} { error $mc::NotConfigured }

	set request [buildGetMyGames]
	set action "${NS}/GetMyGames"

	if {[catch {soapRequest $action $request} response]} {
		error [format $SyncFailed $response]
	}

	# Check for SOAP fault
	set fault [extractFault $response]
	if {[string length $fault]} {
		if {[string match -nocase "*auth*" $fault]} {
			error $AuthFailed
		}
		error [format $SyncFailed $fault]
	}

	return [parseGamesResponse $response]
}


# ======================================================================
# API: MakeAMove
# ======================================================================

proc submitMove {gameId move movecount args} {
	variable NS
	variable mc::SubmitFailed

	if {![configured?]} { error $mc::NotConfigured }

	set request [buildMakeAMove $gameId $move $movecount {*}$args]
	set action "${NS}/MakeAMove"

	if {[catch {soapRequest $action $request} response]} {
		error [format $SubmitFailed $response]
	}

	set fault [extractFault $response]
	if {[string length $fault]} {
		error [format $SubmitFailed $fault]
	}

	return [parseMoveResult $response]
}


# ======================================================================
# Response parsing
# ======================================================================

proc extractFault {xml} {
	# Check for SOAP fault
	if {[regexp {<faultstring>(.*?)</faultstring>} $xml -> fault]} {
		return $fault
	}
	return ""
}


proc parseGamesResponse {xml} {
	# Parse the GetMyGames SOAP response.
	# Extract all XfccGame elements and return a list of dicts.
	set result {}
	set offset 0

	while {1} {
		set start [string first "<XfccGame" $xml $offset]
		if {$start == -1} { break }
		set end [string first "</XfccGame>" $xml $start]
		if {$end == -1} { break }
		set gameXml [string range $xml $start $end]
		incr end [string length "</XfccGame>"]
		incr end -1

		set game [parseGameFields $gameXml]
		if {[llength $game]} { lappend result $game }

		set offset [expr {$end + 1}]
	}

	return $result
}


proc parseGameFields {xml} {
	# Parse individual game fields from XML text.
	# Returns a dict with known XFCC field names.
	set fields {
		id white black event site date eventDate myTurn hasWhite moves
		drawOffered message whiteTitle blackTitle whiteElo blackElo
		whiteNA blackNA eventSponsor section stage board timeControl
		setup fen result variant gameLink serverInfo
		daysPlayer hoursPlayer minutesPlayer
		daysOpponent hoursOpponent minutesOpponent
	}

	set game {}

	foreach field $fields {
		set value ""
		if {[regexp "<$field>(.*?)</$field>" $xml -> value]} {
			# Decode XML entities
			set value [xmlDecode $value]
		}
		lappend game $field $value
	}

	return $game
}


proc parseMoveResult {xml} {
	# Parse MakeAMove response — returns the result string.
	if {[regexp {<MakeAMoveResult>(.*?)</MakeAMoveResult>} $xml -> result]} {
		return [string trim $result]
	}
	if {[regexp {<MakeAMove2Result>(.*?)</MakeAMove2Result>} $xml -> result]} {
		return [string trim $result]
	}
	return "Unknown"
}


proc xmlDecode {s} {
	# Decode basic XML entities
	set s [string map {
		"&lt;" "<" "&gt;" ">" "&amp;" "&" "&quot;" "\"" "&apos;" "'"
	} $s]
	return $s
}


proc xmlEncode {s} {
	# Encode basic XML entities for SOAP requests
	set s [string map {
		"&" "&amp;" "<" "&lt;" ">" "&gt;" "\"" "&quot;" "'" "&apos;"
	} $s]
	return $s
}


# ======================================================================
# Result enum helpers
# ======================================================================

proc resultToPgn {result} {
	# Convert XFCC result enum to PGN result string
	switch -- $result {
		"Ongoing"				{ return "*" }
		"WhiteWins"				{ return "1-0" }
		"BlackWins"				{ return "0-1" }
		"Draw"					{ return "1/2-1/2" }
		"WhiteWinAdjudicated"	{ return "1-0" }
		"BlackWinAdjudicated"	{ return "0-1" }
		"DrawAdjudicated"		{ return "1/2-1/2" }
		"WhiteDefaulted"			{ return "1-0" }
		"BlackDefaulted"			{ return "0-1" }
		default					{ return "*" }
	}
}


proc timeRemaining {game} {
	# Extract time remaining for player and opponent from a game dict.
	# Returns: {playerTime opponentTime} as ISO 8601 duration strings.
	set dp [dict get $game daysPlayer]
	set hp [dict get $game hoursPlayer]
	set mp [dict get $game minutesPlayer]
	set do [dict get $game daysOpponent]
	set ho [dict get $game hoursOpponent]
	set mo [dict get $game minutesOpponent]

	set playerTime [format "P%sDT%sH%sM" $dp $hp $mp]
	set opponentTime [format "P%sDT%sH%sM" $do $ho $mo]

	return [list $playerTime $opponentTime]
}

} ;# namespace xfcc
} ;# namespace iccf

# vi:set ts=3 sw=3: