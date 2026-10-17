#!/usr/bin/env tclsh
# ======================================================================
# Verify the endgame trainer's built-in FENs against the online Lichess
# tablebase, and store the verdicts.
#
# Run once (it needs the network), from anywhere:
#
#     tclsh tests/verify_endgame_fens.tcl
#
# It sources tcl/endgame-trainer.tcl for the catalog (the catalog needs no
# Tk), asks https://tablebase.lichess.ovh/standard for every position,
# compares the answer with the verdict stored in the catalog and writes the
# verdicts next to this script as endgame-verdicts.tsv.  A mismatch, an
# illegal position or a network error makes it exit non-zero.
#
# The top-level category of the answer is read with a regex, so no JSON
# package (tcllib) is needed for this one-off tool.
# ======================================================================

package require Tcl 8.5
package require http 2.7

# The catalog is loaded without the application: ::util::source is a no-op
# and the options hook has nothing to write to.
namespace eval ::util { proc source {args} {} }
namespace eval ::options { proc hookWriter {args} {} }
namespace eval ::scidb { namespace eval dir { set home [pwd] } }
namespace eval ::verify {}

# https needs the tls package.  Tcl installs it under a versioned directory
# that a plain tclsh does not always have on auto_path, so the usual spots
# are tried first; without tls the fetch falls back to curl.
set ::verify::useCurl 0
if {[catch { package require tls }]} {
	foreach dir [glob -nocomplain /usr/lib/tcltk/tls* /usr/lib/tcltk/*/tls* \
		/usr/local/lib/tcltk/tls* /usr/local/lib/tcltk/*/tls*] {
		lappend auto_path $dir
	}
	if {[catch { package require tls }]} { set ::verify::useCurl 1 }
}
if {!$::verify::useCurl} {
	proc ::verify::tlsSocket {args} {
		set host [lindex $args end-1]
		return [::tls::socket -servername $host {*}$args]
	}
	::http::register https 443 ::verify::tlsSocket
}

# The body of <url>, over Tcl http or curl.
proc ::verify::fetch {url} {
	if {$::verify::useCurl} {
		if {[catch { exec curl -s --fail --max-time 30 $url } data]} {
			error "curl could not fetch $url: $data"
		}
		return $data
	}
	set token [::http::geturl $url -timeout 30000]
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::http::data $token]
	::http::cleanup $token
	if {$status ne "ok" || $code != 200} {
		error "tablebase answered '$status $code': [string range $data 0 60]"
	}
	return $data
}

set ::here [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $::here .. tcl endgame-trainer.tcl]


# The category of the tablebase answer for <fen> ("win", "draw", ...), or
# an error naming the HTTP status / tablebase message.
proc ::verify::ask {fen} {
	set url "https://tablebase.lichess.ovh/standard?fen=[string map {" " _} $fen]"
	set data [::verify::fetch $url]
	if {![regexp {"category":"([a-z-]+)"} $data -> category]} {
		error "no category in the tablebase answer: [string range $data 0 60]"
	}
	return $category
}


set out [::open [file join $::here endgame-verdicts.tsv] w]
puts $out "# ending\tgoal\tcategory\tverdict\tfen"
set checked 0
set failures 0

foreach theme [::endtrainer::Themes] {
	foreach ending [::endtrainer::Endings [lindex $theme 0]] {
		set id [dict get $ending id]
		set goal [dict get $ending goal]
		foreach position [dict get $ending positions] {
			lassign $position fen stored
			incr checked
			if {[catch { ::verify::ask $fen } category]} {
				incr failures
				puts "ERROR    $id $fen: $category"
				puts $out [join [list $id $goal "-" "error" $fen] "\t"]
				continue
			}
			set verdict [::endtrainer::VerdictOf [dict create category $category]]
			puts $out [join [list $id $goal $category $verdict $fen] "\t"]
			if {$verdict ne $stored} {
				incr failures
				puts "MISMATCH $id $fen: stored '$stored', tablebase '$category'"
			} else {
				puts [format "ok       %-9s %-6s %-8s %s" $id $goal $category $fen]
			}
		}
	}
}

close $out
puts "checked $checked position(s), $failures failure(s)"
puts "verdicts written to [file join $::here endgame-verdicts.tsv]"

if {$failures} { exit 1 }
exit 0
