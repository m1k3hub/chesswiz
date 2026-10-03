# ======================================================================
# ::ai::factcheck -- check someone else's annotations against the facts.
#
# The claim checker (::ai::claims) exists to keep generated prose honest.
# This module points it at *human* prose: the comments already stored in a
# game -- an author's, a book's, your own -- and answers the question
# "does this annotation say anything the position contradicts?".
#
# It is the same deterministic checker the pipeline uses (regex vocabulary
# plus the C++ fact layer: move legality, piece placement, structural
# features such as isolated pawns, open files, bishop pairs), so the result
# is reproducible and needs no model, no engine and no network.  Only
# claims the facts *positively contradict* are reported, exactly as in the
# generation pipeline: a clean report is meaningful.
#
#   ::ai::factcheck::game ?<position>?      check the annotations of a game
#   ::ai::factcheck::text <fen> <text>      check one annotation
#   ::ai::factcheck::report $parent $result render a report
#
# A comment attached *after* move k describes the position after that move;
# a comment attached *before* move k describes the position before it.  Each
# comment is therefore checked against the position it annotates, not
# against the game's current position.
#
# The scan walks the game and puts the board back where it was (the comment
# read path works from the current key, as the editor's does).
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-factcheck
}

package require Tcl 8.5
package require Tk 8.5

namespace eval ai {
namespace eval factcheck {
namespace eval mc {

set Title			"Annotation fact-check"
set Clean			"Every annotation agrees with the position it describes."
set Found			"%d annotation(s) make %d claim(s) the position contradicts."
set Progress		"Checking move %d of %d..."
set NoComments		"this game has no comments to check"

} ;# namespace factcheck
} ;# namespace factcheck
} ;# namespace ai


# ======================================================================
# Checking
# ======================================================================

# One annotation: <fen> is the position it describes.  Returns a dict
# {move ply side text problems}.
proc ::ai::factcheck::annotation {san ply side fen text} {
	set problems {}
	if {[catch { ::ai::claims::check $fen $text } problems]} { set problems {} }
	return [dict create move $san ply $ply side $side fen $fen text $text problems $problems]
}


# The annotations of the game at <position>, checked.  Returns
# {game N checked C flagged F findings {...}}.
proc ::ai::factcheck::game {{position 9}} {
	set findings {}
	set checked 0

	set saved ""
	catch { set saved [::scidb::game::position key] }

	if {[catch { set plies [::scidb::game::query $position mainline] }]} {
		return [dict create game 0 checked 0 flagged 0 findings {} error "no game"]
	}

	set ply 0
	foreach one $plies {
		lassign $one key san fen
		incr ply
		# the comment path reads the *current* key: step there, read, then
		# restore the user's position at the end
		if {[catch { ::scidb::game::go $position key $key }]} { continue }

		set mover [expr {[lindex [split $fen] 1] eq "b" ? "black" : "white"}]
		set after [AfterFen $fen $san]
		set others [expr {$mover eq "white" ? "black" : "white"}]

		if {[string length $after]} {
			set found [CheckOne $san $ply $others $after $position after]
			if {[llength $found]} {
				incr checked
				if {[llength [dict get $found problems]]} { lappend findings $found }
			}
		}
		set found [CheckOne $san $ply $mover $fen $position before]
		if {[llength $found]} {
			incr checked
			if {[llength [dict get $found problems]]} { lappend findings $found }
		}
	}
	if {[string length $saved]} { catch { ::scidb::game::go $position key $saved } }

	return [dict create game [llength $plies] checked $checked flagged [llength $findings] findings $findings]
}


# The comment of one kind at the current key, checked, or {}.
proc ::ai::factcheck::CheckOne {san ply side fen position which} {
	if {[catch { ::scidb::game::query $position comment $which } comment]} { return {} }
	set text [plain $comment]
	if {![string length $text]} { return {} }
	return [annotation $san $ply $side $fen $text]
}


# The FEN after <san> in <fen>, from the C++ fact layer.
proc ::ai::factcheck::AfterFen {fen san} {
	if {[catch { ::scidb::ai::moveFacts $san $fen } facts]} { return "" }
	if {[regexp {"fenAfter":"([^"]+)"} $facts -> after]} { return $after }
	return ""
}


# A stored comment is XML (str/figurine elements); the claim checker wants
# the words.  ::scidb::misc::xml knows toList (and fromList); there is no
# toText, so the text is reassembled from the parsed structure, with a tag
# strip as a last resort.
proc ::ai::factcheck::plain {comment} {
	set parts {}

	if {![catch { ::scidb::misc::xml toList $comment } parsed] && [llength $parsed]} {
		foreach entry [lindex $parsed 0] {
			lassign $entry lang content
			foreach pair $content {
				lassign $pair code text
				if {[string length $text]} { lappend parts $text }
			}
		}
	}
	if {![llength $parts]} {
		set stripped $comment
		regsub -all {<[^>]*>} $stripped {} stripped
		set parts [list [string trim $stripped]]
	}
	return [string trim [join $parts " "]]
}


# ::scidb::ai::facts speaks JSON; the rest of the app reads the plain text.
proc ::ai::factcheck::text {fen content} {
	return [annotation "" 0 "" $fen $content]
}


# ======================================================================
# Reporting
# ======================================================================
proc ::ai::factcheck::report {parent result} {
	variable mc

	set html {}
	if {[dict get $result flagged] == 0} {
		append html "<p><b>$mc::Title</b></p><p>[::application::ai::escape $mc::Clean]</p>"
		append html "<p>[dict get $result checked] annotation(s) checked.</p>"
	} else {
		append html "<p><b>$mc::Title</b></p><p>[format $mc::Found \
			[dict get $result flagged] \
			[llength [concat {*}[lmap f [dict get $result findings] { dict get $f problems }]]]]</p>"
		append html "<ul>"
		foreach finding [dict get $result findings] {
			set where [dict get $finding move]
			append html "<li><b>[::application::ai::escape [string trim "$where"]]</b>: \
				[::application::ai::escape [dict get $finding text]]<br><i>"
			append html [::application::ai::escape [join [dict get $finding problems] {; }]]
			append html "</i></li>"
		}
		append html "</ul>"
	}

	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "$mc::Title" \
			[::application::ai::htmlData $html] }
	}
	return [dict create html $html]
}


# The menu/assistant entry point: check the game on the board and report.
proc ::ai::factcheck::current {parent} {
	set result [game 9]
	report $parent $result
	if {[dict get $result checked] == 0} { return $mc::NoComments }
	return [expr {[dict get $result flagged]
		? [format $mc::Found [dict get $result flagged] \
			[llength [concat {*}[lmap f [dict get $result findings] { dict get $f problems }]]]]
		: $mc::Clean}]
}

# vi:set ts=3 sw=3:
