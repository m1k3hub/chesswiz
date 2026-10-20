# ======================================================================
# Scidb App Test — context objects through the cloud egress gate
# (VAL-AI-004, decision 004).
#
# "What can I do here?" hands a structured record of the clicked object
# to the assistant. The record passes tcl/ai-egress.tcl first: the
# classifier is asked over the closed set {private public} for every
# object kind (C1-C12), a public answer delivers the record, and a
# private answer sends nothing and tells the user what was withheld.
#
# ::ai::decide is stubbed in this process and restored after every test,
# so the files that follow see the real command. The tests run as this
# file is sourced (tcltest runs a matched test when it is defined), so
# every helper must come before the first test.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::ctxegress {
	variable Calls {}
	variable Decision {ok 1 label public confidence 0.9 source classifier}
	variable Delivered {}
	variable Messages {}
	variable Infos {}
	variable Pumped 0
	variable SavedDecide ""
	variable SavedMessage ""
	variable SavedInfo ""
}

# One object of every kind, carrying exactly the VAL-CTX-002 fields.
proc ::scidb::test::ctxegress::Objects {} {
	set fen "r1bqkbnr/pppppppp/2n5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2"
	return [list \
		C1 [dict create square e4 fen $fen] \
		C2 [dict create base /db/one.sci variant Normal index 7 ply 12 san Nf3] \
		C3 [dict create base /db/one.sci variant Normal index 7] \
		C4 [dict create base /db/one.sci] \
		C5 [dict create kind player name "Kasparov, Garry" base /db/one.sci] \
		C6 [dict create engine Stockfish lineId 2 pv "e4 e5 Nf3"] \
		C7 [dict create base /db/one.sci mediaId 4 path /media/clip.mp4] \
		C8 [dict create fen $fen move Nf3] \
		C9 [dict create paneUid games] \
		C10 [dict create table games column White] \
		C11 [dict create base /db/one.sci index 7 ply 12] \
		C12 [dict create gameSlot 2] \
	]
}

# The record fields each kind must carry, in declaration order.
proc ::scidb::test::ctxegress::Fields {} {
	return [list \
		C1 {square fen} \
		C2 {base variant index ply san} \
		C3 {base variant index} \
		C4 {base} \
		C5 {kind name base} \
		C6 {engine lineId pv} \
		C7 {base mediaId path} \
		C8 {fen move} \
		C9 {paneUid} \
		C10 {table column} \
		C11 {base index ply} \
		C12 {gameSlot} \
	]
}

# ::ai::decide's contract, reduced to what these tests need: record the
# call and answer with the canned decision.
proc ::scidb::test::ctxegress::Decide {feature state question script args} {
	upvar #0 ::scidb::test::ctxegress::Calls calls
	lappend calls [dict create feature $feature state $state question $question args $args]
	after 0 [list {*}$script $::scidb::test::ctxegress::Decision]
	return
}

proc ::scidb::test::ctxegress::stub {decision} {
	variable SavedDecide
	variable Calls

	set Calls {}
	set ::scidb::test::ctxegress::Decision $decision
	if {[llength [info commands ::ai::decide]]} {
		set SavedDecide ::scidb::test::ctxegress::savedDecide
		rename ::ai::decide $SavedDecide
	}
	rename ::scidb::test::ctxegress::Decide ::ai::decide
	return
}

proc ::scidb::test::ctxegress::restore {} {
	variable SavedDecide

	if {$SavedDecide ne "" && [info commands $SavedDecide] ne ""} {
		rename ::ai::decide ::scidb::test::ctxegress::Decide
		rename $SavedDecide ::ai::decide
		set SavedDecide {}
	} elseif {[llength [info commands ::scidb::test::ctxegress::Decide]] == 0
	 && [llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::ctxegress::Decide
	}
	return
}

# The delivery sink: it replaces the assistant for the duration of a test.
proc ::scidb::test::ctxegress::Sink {record} {
	lappend ::scidb::test::ctxegress::Delivered $record
	return
}

proc ::scidb::test::ctxegress::Status {text} {
	lappend ::scidb::test::ctxegress::Messages $text
	return
}

# The gate answers from after 0; pump the event loop past it.
proc ::scidb::test::ctxegress::Pump {} {
	set ::scidb::test::ctxegress::Pumped 0
	after 50 [list set ::scidb::test::ctxegress::Pumped 1]
	vwait ::scidb::test::ctxegress::Pumped
	return
}

proc ::scidb::test::ctxegress::Setup {} {
	variable SavedMessage
	variable SavedInfo

	set ::scidb::test::ctxegress::Calls {}
	set ::scidb::test::ctxegress::Delivered {}
	set ::scidb::test::ctxegress::Messages {}
	set ::scidb::test::ctxegress::Infos {}
	set ::context::AssistantSink ::scidb::test::ctxegress::Sink
	set ::context::LastWithheld {}

	set SavedMessage ""
	if {[llength [info commands ::ui::message]]} {
		set SavedMessage ::scidb::test::ctxegress::savedMessage
		rename ::ui::message $SavedMessage
	}
	rename ::scidb::test::ctxegress::Status ::ui::message

	set SavedInfo ""
	if {[llength [info commands ::dialog::info]]} {
		set SavedInfo ::scidb::test::ctxegress::savedInfo
		rename ::dialog::info $SavedInfo
	}
	proc ::dialog::info {args} {
		lappend ::scidb::test::ctxegress::Infos $args
		return
	}
	return
}

proc ::scidb::test::ctxegress::Cleanup {} {
	variable SavedMessage
	variable SavedInfo

	set ::context::AssistantSink ""
	set ::context::LastWithheld {}

	if {[llength [info commands ::ui::message]]} {
		rename ::ui::message ::scidb::test::ctxegress::Status
	}
	if {$SavedMessage ne "" && [info commands $SavedMessage] ne ""} {
		rename $SavedMessage ::ui::message
	}
	set SavedMessage ""

	if {[llength [info commands ::dialog::info]]} {
		rename ::dialog::info {}
	}
	if {$SavedInfo ne "" && [info commands $SavedInfo] ne ""} {
		rename $SavedInfo ::dialog::info
	}
	set SavedInfo ""

	::scidb::test::ctxegress::restore
	return
}

tcltest::test ctxegress-record-fields {every context kind records exactly its VAL-CTX-002 fields} -body {
	set bad {}
	foreach {cid object} [::scidb::test::ctxegress::Objects] {
		set keys [dict keys [::context::Record $cid $object]]
		set want {}
		foreach {id fields} [::scidb::test::ctxegress::Fields] {
			if {$id eq $cid} { set want $fields }
		}
		if {$keys ne $want} { lappend bad "$cid=[list $keys] want [list $want]" }
	}
	set bad
} -result {}

tcltest::test ctxegress-every-kind-asks-the-gate {a public answer delivers every object kind} -setup {
	::scidb::test::ctxegress::Setup
	::scidb::test::ctxegress::stub {ok 1 label public confidence 0.9 source classifier}
} -body {
	set bad {}
	foreach {cid object} [::scidb::test::ctxegress::Objects] {
		set ::scidb::test::ctxegress::Calls {}
		set ::scidb::test::ctxegress::Delivered {}
		::context::Ask $cid $object
		::scidb::test::ctxegress::Pump

		set record [::context::Record $cid $object]
		set call [lindex $::scidb::test::ctxegress::Calls 0]
		set prompt [expr {[llength $call] ? [dict get $call state] : ""}]
		set question [expr {[llength $call] ? [dict get $call question] : {}}]

		if {[llength $::scidb::test::ctxegress::Calls] != 1} {
			lappend bad "$cid calls=[llength $::scidb::test::ctxegress::Calls]"
		} elseif {[dict get $call feature] ne "egress"} {
			lappend bad "$cid feature=[dict get $call feature]"
		} elseif {[dict get $question type] ne "choice"
		 || [dict keys [dict get $question criteria]] ne "private public"} {
			lappend bad "$cid question=$question"
		}
		foreach key [dict keys $record] {
			if {[string first "$key: [dict get $record $key]" $prompt] < 0} {
				lappend bad "$cid missing $key"
			}
		}
		if {[llength $::scidb::test::ctxegress::Delivered] != 1} {
			lappend bad "$cid delivered=[llength $::scidb::test::ctxegress::Delivered]"
		} elseif {[lindex $::scidb::test::ctxegress::Delivered 0] ne $record} {
			lappend bad "$cid delivered wrong record"
		}
	}
	set bad
} -cleanup {
	::scidb::test::ctxegress::Cleanup
} -result {}

tcltest::test ctxegress-denial {a private answer sends nothing and says what was withheld} -setup {
	::scidb::test::ctxegress::Setup
	::scidb::test::ctxegress::stub {ok 1 label private confidence 0.91 source classifier}
} -body {
	set object [dict create base /db/one.sci variant Normal index 7 ply 12 san Nf3]
	::context::Ask C2 $object
	::scidb::test::ctxegress::Pump

	set withheld $::context::LastWithheld
	set fields [expr {[dict exists $withheld fields] ? [dict get $withheld fields] : ""}]
	list [llength $::scidb::test::ctxegress::Calls] \
		[llength $::scidb::test::ctxegress::Delivered] \
		[expr {[dict exists $withheld cid] ? [dict get $withheld cid] : ""}] \
		[string match "*index=7*" $fields] \
		[string match "*Withheld*" [join $::scidb::test::ctxegress::Messages]] \
		[string match "*Withheld*" [join $::scidb::test::ctxegress::Infos]]
} -cleanup {
	::scidb::test::ctxegress::Cleanup
} -result {1 0 C2 1 1 1}

tcltest::test ctxegress-gate-failure {a gate error withholds as unknown} -setup {
	::scidb::test::ctxegress::Setup
} -body {
	if {[llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::ctxegress::realDecide
	}
	proc ::ai::decide {args} { error "classifier unavailable" }
	::context::Ask C9 [dict create paneUid games]
	::scidb::test::ctxegress::Pump
	set withheld $::context::LastWithheld
	list [llength $::scidb::test::ctxegress::Delivered] \
		[expr {[dict exists $withheld fields] ? [dict get $withheld fields] : ""}] \
		[string match "*Withheld: unknown*" [join $::scidb::test::ctxegress::Messages]]
} -cleanup {
	rename ::ai::decide {}
	if {[llength [info commands ::scidb::test::ctxegress::realDecide]]} {
		rename ::scidb::test::ctxegress::realDecide ::ai::decide
	}
	::scidb::test::ctxegress::Cleanup
} -result {0 unknown 1}

::tcltest::cleanupTests
return
