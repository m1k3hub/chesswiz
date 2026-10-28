# ======================================================================
# Scidb App Test — context menus C1-C12 (VAL-CTX-001..004)
# ======================================================================
# One builder per object: the menus built by ::context::Build must equal
# the frozen lists in tests/fixtures/context-expected/ (generated from
# PROPOSAL section 3 before implementation, task B0-baseline).
#
# Two frozen lines predate later decisions and are handled explicitly:
#   * the first row says "Ask about this ..."; decision 004 relabels it
#     "What can I do here?" (VAL-CTX-002) -- both normalise to ASK;
#   * C3 has no Copy/Paste rows because decision 006 came later
#     (VAL-CTX-005) -- those two rows are removed before comparing and
#     are asserted by the copy/paste tests instead.
# Parenthesised cascade descriptions in the fixture are prose, not
# labels, so a cascade compares by its label only.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::ctx {}

if {[llength [info commands ::context::Build]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
	source [file join [file dirname [file normalize [info script]]] .. tcl context.tcl]
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-egress.tcl]
}

set ::scidb::test::ctx::dir [file dirname [file normalize [info script]]]
set ::scidb::test::ctx::fixtures [file join $::scidb::test::ctx::dir fixtures context-expected]

# --- objects -----------------------------------------------------------

proc ::scidb::test::ctx::Objects {} {
	return [dict create \
		C1 [dict create square e4 fen {8/8/8/8/4P3/8/8/8 w - - 0 1}] \
		C2 [dict create base b variant Normal index 5 ply 10 san Nf3] \
		C3 [dict create base b variant Normal index 1 column number \
			sortable 1 path .ctxlist view 0] \
		C4 [dict create base testbase] \
		C5.player [dict create kind player name {Carlsen, Magnus} base b] \
		C5.event [dict create kind event name Wijk base b] \
		C5.site [dict create kind site name wijk.com base b] \
		C6 [dict create engine SF lineId 1 pv {e4 e5 Nf3}] \
		C7 [dict create base b mediaId m1 path /tmp/clip.mp4] \
		C8 [dict create fen {8/8/8/8/4P3/8/8/8 w - - 0 1} move e4 table .ctxtree] \
		C9.board [dict create paneUid board frame .ctxpane] \
		C9.editor [dict create paneUid editor frame .ctxpane] \
		C9.games [dict create paneUid games frame .ctxpane] \
		C9.people [dict create paneUid players frame .ctxpane] \
		C9.tree [dict create paneUid tree frame .ctxpane] \
		C9.analysis [dict create paneUid analysis:1 frame .ctxpane] \
		C9.media [dict create paneUid media frame .ctxpane] \
		C9.report [dict create paneUid report frame .ctxpane] \
		C9.assistant [dict create paneUid assistant frame .ctxpane] \
		C9.explorer [dict create paneUid explorer frame .ctxpane] \
		C10 [dict create table .ctxlist column date] \
		C11 [dict create base b index 5 ply 10 widget .ctxtxt] \
		C12 [dict create gameSlot 1 history {G1 G2}] \
	]
}

# --- building ----------------------------------------------------------

proc ::scidb::test::ctx::BuildRows {cid object} {
	variable Build
	if {![info exists Build]} { set Build 0 }
	set menu .ctxmenu[incr Build]
	catch { destroy $menu }
	menu $menu -tearoff 0
	set ok [::context::Build $cid $menu $object]
	set rows [List $menu]
	destroy $menu
	return [list $ok $rows]
}

# The rows of a built menu: {ROW label accel state}, {CASCADE label state
# children}, {HEADER label}, SEP. A disabled command whose label is not a
# registered action label is the object header row (C4, C10, C12).
proc ::scidb::test::ctx::List {menu} {
	set out {}
	set end [$menu index end]
	if {$end eq "" || $end eq "none"} { return $out }
	for {set i 0} {$i <= $end} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { lappend out SEP; continue }
		set label [string trimleft [$menu entrycget $i -label] " "]
		set state normal
		catch { set state [$menu entrycget $i -state] }
		if {$type eq "cascade"} {
			regsub { ▸$} $label "" label
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			lappend out [list CASCADE $label $state [List $sub]]
			continue
		}
		set accel ""
		catch { set accel [$menu entrycget $i -accelerator] }
		if {$state eq "disabled" && ![ActionLabel $label]} {
			lappend out [list HEADER $label]
			continue
		}
		lappend out [list ROW $label $accel $state]
	}
	return $out
}

proc ::scidb::test::ctx::ActionLabel {label} {
	foreach id [array names ::context::Labels] {
		if {$label eq $::context::Labels($id)} { return 1 }
		if {[string match "$::context::Labels($id) (*" $label]} { return 1 }
	}
	return 0
}

# --- fixtures ----------------------------------------------------------

proc ::scidb::test::ctx::SectionKey {name} {
	switch -glob -- [string tolower $name] {
		players* { return people }
		player* { return player }
		event* { return event }
		site* { return site }
		board* { return board }
		notation* { return editor }
		game\ list* { return games }
		tree* { return tree }
		analysis* { return analysis }
		media* { return media }
		report* { return report }
		assistant* { return assistant }
		explorer* { return explorer }
		common* { return common }
	}
	return other
}

# Returns the fixture as {default rows} for one-section files, or a dict
# of section rows for C5/C9.
proc ::scidb::test::ctx::Fixture {cid} {
	variable fixtures
	set fh [open [file join $fixtures $cid.txt] r]
	set data [read $fh]
	close $fh

	set sections [dict create]
	set key ""
	set rows {}
	foreach line [split $data "\n"] {
		set line [string trim $line]
		if {$line eq ""} { continue }
		if {[regexp {^# (.+):$} $line -> name]} {
			set next [SectionKey $name]
			if {$key eq ""} {
				# The Ask row and its separator open every section.
				dict set sections prefix $rows
				set key $next
				set rows {}
				continue
			}
			dict set sections $key $rows
			set key $next
			set rows {}
			continue
		}
		lappend rows $line
	}
	if {$key ne ""} {
		dict set sections $key $rows
	} else {
		dict set sections default $rows
	}
	return $sections
}

proc ::scidb::test::ctx::FixtureRow {line} {
	if {$line eq "---"} { return SEP }
	if {[string match "<*" $line]} { return HEADER }
	if {[regexp {^(.*?) ▸(?: \([^)]*\))?$} $line -> label]} {
		return [list CASCADE $label]
	}
	if {[regexp {^(.*) \(([^()]*)\)$} $line -> label accel]} {
		return [list ROW $label $accel]
	}
	return [list ROW $line ""]
}

# --- canonical form ----------------------------------------------------

proc ::scidb::test::ctx::Canon {rows askVar} {
	upvar 1 $askVar seenAsk
	set out {}
	foreach row $rows {
		switch -- [lindex $row 0] {
			SEP {
				if {[llength $out] && [lindex $out end] ne "SEP"} {
					lappend out SEP
				}
			}
			ROW {
				set label [lindex $row 1]
				set accel [lindex $row 2]
				if {!$seenAsk && [regexp {^(Ask about this.*|What can I do here\?)$} $label]} {
					set seenAsk 1
					lappend out ASK
					continue
				}
				lappend out "ROW|$label|$accel"
			}
			CASCADE { lappend out "CASCADE|[lindex $row 1]" }
			HEADER { lappend out HEADER }
		}
	}
	while {[llength $out] && [lindex $out 0] eq "SEP"} {
		set out [lrange $out 1 end]
	}
	while {[llength $out] && [lindex $out end] eq "SEP"} {
		set out [lrange $out 0 end-1]
	}
	return $out
}

proc ::scidb::test::ctx::Expected {cid {section default}} {
	set sections [Fixture $cid]
	if {$section eq "default"} {
		set rows [dict get $sections default]
	} else {
		set rows {}
		if {[dict exists $sections prefix]} {
			set rows [dict get $sections prefix]
		}
		set rows [concat $rows [dict get $sections $section]]
		# The fixture writes the separator before the common block once;
		# every pane menu has it before its common block.
		while {[llength $rows] && [lindex $rows end] eq "---"} {
			set rows [lrange $rows 0 end-1]
		}
		if {[dict exists $sections common]} {
			set rows [concat $rows [list ---] [dict get $sections common]]
		}
	}
	set parsed {}
	foreach line $rows {
		# Round 5: the synthetic C3 object has no real game/site URL.
		# URL visibility and dispatch are covered by test_app_menu_round5.
		if {$cid eq "C3" && [string match {Open URL*} $line]} continue
		# Worker ruling: remove unimplemented leaves and their empty source
		# group; the board's existing tablebase toggle is now a command.
		# The frozen proposal remains untouched; dispatch-removed separately
		# asserts that the removed controls cannot be invoked.
		if {$cid eq "C9"} {
			if {$section eq "report" && $line eq "Print…"} {continue}
			if {$section eq "assistant" && [string match {Source ▸*} $line]} {continue}
			if {$section eq "explorer" && $line eq "Online Tablebase"} {continue}
			if {$section eq "board" && $line eq "Show Tablebase ▸"} {set line "Show Tablebase"}
		}
		lappend parsed [FixtureRow $line]
	}
	set seen 0
	return [Canon $parsed seen]
}

proc ::scidb::test::ctx::Built {cid object} {
	lassign [BuildRows $cid $object] ok rows
	set parsed $rows
	set seen 0
	if {$cid eq "C3"} {
		set parsed {}
		foreach row $rows {
			if {[lindex $row 0] eq "ROW"
			 && ([lindex $row 1] eq "Copy Game"
			     || [lindex $row 1] eq "Copy Games"
			     || [string match "Paste Game(s)*" [lindex $row 1]])} {
				continue
			}
			lappend parsed $row
		}
	}
	return [Canon $parsed seen]
}

# --- VAL-CTX-001: built menus equal the frozen lists -------------------

proc ::scidb::test::ctx::CheckFixture {cid object {section default}} {
	set expected [Expected $cid $section]
	set built [Built $cid $object]
	if {$expected ne $built} {
		return [list mismatch $expected $built]
	}
	set builtAgain [Built $cid $object]
	if {$builtAgain ne $built} {
		return [list unstable $built $builtAgain]
	}
	# The first posted row is decision 004's label, in every menu.
	set rows [lindex [BuildRows $cid $object] 1]
	set first [lindex $rows 0]
	if {[lindex $first 0] ne "ROW" || [lindex $first 1] ne $::context::mc::WhatCanIDo} {
		return [list first-row $first]
	}
	return 1
}

# C10 now populates its cascade from the actual registered table columns.
# The former path-only object never created a table (IdMap(.ctxlist) missing).
::table::table .ctxlist
::table::addcol .ctxlist date -text Date

set ::scidb::test::ctx::objects [::scidb::test::ctx::Objects]

foreach cid {C1 C2 C3 C4 C6 C7 C8 C10 C11 C12} {
	tcltest::test context-fixture-$cid "C$cid menu equals the frozen list" -body {
		set object [dict get $::scidb::test::ctx::objects $cid]
		::scidb::test::ctx::CheckFixture $cid $object
	} -result 1
}

foreach kind {player event site} {
	tcltest::test context-fixture-C5-$kind "C5 $kind menu equals the frozen list" -body {
		set object [dict get $::scidb::test::ctx::objects C5.$kind]
		::scidb::test::ctx::CheckFixture C5 $object $kind
	} -result 1
}

foreach pane {board editor games people tree analysis media report assistant explorer} {
	tcltest::test context-fixture-C9-$pane "C9 $pane header menu equals the frozen list" -body {
		set object [dict get $::scidb::test::ctx::objects C9.$pane]
		::scidb::test::ctx::CheckFixture C9 $object $pane
	} -result 1
}

# --- C4 without a base (R5) -------------------------------------------

tcltest::test context-C4-empty {a base-less switcher menu offers new/open/recent} -body {
	lassign [::scidb::test::ctx::BuildRows C4 [dict create]] ok rows
	set labels {}
	foreach row $rows {
		if {[lindex $row 0] eq "CASCADE"} { lappend labels [lindex $row 1] }
	}
	list $ok [lsearch -exact $labels "Search"] \
		[expr {[lsearch -exact $labels "New Database"] >= 0}] \
		[expr {[lsearch -exact $labels "Open Recent"] >= 0}]
} -result {1 -1 1 1}

# --- VAL-CTX-002: the structured record --------------------------------

proc ::scidb::test::ctx::Pass {record script} {
	uplevel #0 [list {*}$script [list ok 1 label send confidence 1.0 source rules]]
}

proc ::scidb::test::ctx::Receive {record} {
	set ::scidb::test::ctx::Received $record
	return
}

set ::scidb::test::ctx::fields [dict create \
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
	C12 {gameSlot}]

proc ::scidb::test::ctx::CheckRecord {cid object} {
	set savedDecide {}
	if {[llength [info commands ::ai::egress::ContextDecide]]} {
		rename ::ai::egress::ContextDecide ::scidb::test::ctx::savedDecide
		set savedDecide 1
	}
	rename ::scidb::test::ctx::Pass ::ai::egress::ContextDecide
	set savedSink $::context::AssistantSink
	set ::context::AssistantSink [list ::scidb::test::ctx::Receive]
	set ::scidb::test::ctx::Received {}
	set code [catch { ::context::Ask $cid $object } err]
	set got $::scidb::test::ctx::Received
	set ::context::AssistantSink $savedSink
	rename ::ai::egress::ContextDecide ::scidb::test::ctx::Pass
	if {$savedDecide ne ""} {
		rename ::scidb::test::ctx::savedDecide ::ai::egress::ContextDecide
	}
	if {$code} { return "error: $err" }
	set expected [lsort [dict get $::scidb::test::ctx::fields $cid]]
	set actual [lsort [dict keys $got]]
	if {$expected ne $actual} {
		return "keys: expected {$expected} got {$actual}"
	}
	foreach key $actual {
		if {[dict get $got $key] eq ""} { return "empty field: $key" }
	}
	return 1
}

set ::scidb::test::ctx::recordObjects [dict merge $::scidb::test::ctx::objects [dict create \
	C5 [dict get $::scidb::test::ctx::objects C5.player] \
	C9 [dict get $::scidb::test::ctx::objects C9.analysis] \
]]

foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
	tcltest::test context-record-$cid "the $cid Ask row passes exactly the contract fields" -body {
		::scidb::test::ctx::CheckRecord $cid [dict get $::scidb::test::ctx::recordObjects $cid]
	} -result 1
}

# --- VAL-CTX-002: no object under the pointer, no menu -----------------

tcltest::test context-no-object-no-menu {every menu refuses to post without its object} -body {
	set posted {}
	foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
		if {[::context::HasObject $cid [dict create]]} { lappend posted $cid }
	}
	set posted
} -result {}

# --- VAL-CTX-004: pane uids and per-pane fonts -------------------------

tcltest::test context-pane-uids {C9 keeps the pane uids and twm leaf names unchanged} -body {
	set got {}
	foreach {uid key} {
		board board editor editor games games dbgames games
		players people events people sites people annotators people positions people
		tree tree analysis:2 analysis media media report report information report
		assistant assistant explorer explorer
	} {
		lappend got [list $uid [::context::ObjectKey C9 [dict create paneUid $uid]] $key]
	}
	set bad {}
	foreach entry $got {
		lassign $entry uid actual expected
		if {$actual ne $expected} { lappend bad $entry }
	}
	set bad
} -result {}

tcltest::test context-pane-font-per-pane {a pane font change leaves the other pane and the base alone} -body {
	set globalBase [::font::currentFontSize text]
	set base [expr {abs($globalBase)}]
	set beforeBoard [::context::PaneFontSize board]
	set beforeEditor [::context::PaneFontSize editor]
	::context::PaneFont [dict create paneUid board] +1
	set afterBoard [::context::PaneFontSize board]
	set afterEditor [::context::PaneFontSize editor]
	set global [::font::currentFontSize text]
	::context::PaneFont [dict create paneUid board] reset
	list [expr {$afterBoard == $beforeBoard + 1}] \
		[expr {$afterEditor == $beforeEditor}] \
		[expr {$global == $globalBase}] \
		[expr {[::context::PaneFontSize board] == $base}]
} -result {1 1 1 1}

# --- VAL-CTX-007: PaneFont changes the pane's real text widgets ---------

proc ::scidb::test::ctx::PaneDescendants {w} {
	set out {}
	foreach child [winfo children $w] {
		lappend out $child
		lappend out {*}[::scidb::test::ctx::PaneDescendants $child]
	}
	return $out
}

proc ::scidb::test::ctx::Ancestor {w class} {
	while {$w ne ""} {
		if {[winfo class $w] eq $class} { return $w }
		set w [winfo parent $w]
	}
	return ""
}

proc ::scidb::test::ctx::PaneByFont {root prefix} {
	foreach w [::scidb::test::ctx::PaneDescendants $root] {
		if {[winfo class $w] ne "Text"} { continue }
		set font ""
		catch { set font [$w cget -font] }
		if {[string match "${prefix}*" $font]} {
			set frame [::scidb::test::ctx::Ancestor $w TwmFrame]
			if {$frame ne ""} { return [list $w $frame] }
		}
	}
	return {}
}

tcltest::test context-pane-font-live-text {C9 resizes the pane's own text widgets and no other pane} -setup {
	set ::scidb::test::ctx::editorText ""
	set ::scidb::test::ctx::editorFrame ""
	set ::scidb::test::ctx::otherText ""
	set ::scidb::test::ctx::editorUid ""
	lassign [::scidb::test::ctx::PaneByFont .application "::font::text(editor:*"] \
		::scidb::test::ctx::editorText ::scidb::test::ctx::editorFrame
	lassign [::scidb::test::ctx::PaneByFont .application "::font::text(text:*"] \
		::scidb::test::ctx::otherText
	if {$::scidb::test::ctx::editorFrame ne ""} {
		catch { set ::scidb::test::ctx::editorUid \
			[.application.nb.board get $::scidb::test::ctx::editorFrame id] }
	}
} -body {
	set editorText $::scidb::test::ctx::editorText
	set editorFrame $::scidb::test::ctx::editorFrame
	set otherText $::scidb::test::ctx::otherText
	set editorUid $::scidb::test::ctx::editorUid
	if {$editorText eq "" || $editorFrame eq "" || $otherText eq "" || $editorUid eq ""} {
		return no-live-text-widgets
	}
	set otherFont [$otherText cget -font]
	set beforeEditor [font actual [$editorText cget -font] -size]
	set beforeOther [font actual $otherFont -size]
	set object [dict create paneUid $editorUid frame $editorFrame]
	set err [catch { ::context::PaneFont $object +1 } value]
	set afterEditor [font actual [$editorText cget -font] -size]
	set afterOther [font actual [$otherText cget -font] -size]
	set otherFontSame [expr {[$otherText cget -font] eq $otherFont}]

	set stored ""
	catch { set stored $::font::Options(pane:$editorUid:size) }
	set path [file join [file dirname [file normalize [info script]]] tmp-app \
		"panefont_[pid].opt"]
	catch { file delete $path }
	set persisted 0
	catch {
		set fh [open $path w]
		::font::WriteOptions $fh
		close $fh
		set fh [open $path r]
		set written [read $fh]
		close $fh
		set persisted [expr {[string first "pane:$editorUid:size" $written] >= 0}]
	}
	catch { file delete $path }

	set rerr [catch { ::context::PaneFont $object reset } rvalue]
	set resetEditor [font actual [$editorText cget -font] -size]
	set resetOther [font actual [$otherText cget -font] -size]
	unset -nocomplain ::font::Options(pane:$editorUid:size)

	list \
		[expr {$err == 0}] \
		[expr {$afterEditor == $beforeEditor + 1}] \
		[expr {$afterOther == $beforeOther}] \
		$otherFontSame \
		[expr {$stored == $value}] \
		$persisted \
		[expr {$rerr == 0}] \
		[expr {$resetEditor == $beforeEditor}] \
		[expr {$resetOther == $beforeOther}]
} -cleanup {
	if {$::scidb::test::ctx::editorFrame ne "" && $::scidb::test::ctx::editorUid ne ""} {
		catch { ::context::PaneFont [dict create paneUid $::scidb::test::ctx::editorUid \
			frame $::scidb::test::ctx::editorFrame] reset }
		unset -nocomplain ::font::Options(pane:$::scidb::test::ctx::editorUid:size)
	}
} -result {1 1 1 1 1 1 1 1 1}

# --- VAL-CTX-006: the live Sites popup is the C5 builder --------------

proc ::scidb::test::ctx::PopupCmd {table} {
	if {![info exists ::scrolledtable::${table}::(popupcmd)]} { return "" }
	return [set ::scrolledtable::${table}::(popupcmd)]
}

proc ::scidb::test::ctx::FindSiteTable {w} {
	foreach child [winfo children $w] {
		set popup [::scidb::test::ctx::PopupCmd $child]
		if {[string match "*sitetable::PopupMenu*" $popup]
			|| [string match "*::sitetable PopupMenu*" $popup]} { return $child }
		set found [::scidb::test::ctx::FindSiteTable $child]
		if {$found ne ""} { return $found }
	}
	return ""
}

proc ::scidb::test::ctx::Settle {ms} {
	set ::scidb::test::ctx::settled 0
	after $ms {set ::scidb::test::ctx::settled 1}
	vwait ::scidb::test::ctx::settled
	update
}

proc ::scidb::test::ctx::RowIds {menu} {
	set ids {}
	set end [$menu index end]
	if {$end eq "" || $end eq "none"} { return $ids }
	for {set i 0} {$i <= $end} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { lappend ids SEP; continue }
		if {$type eq "cascade"} { lappend ids cascade; continue }
		set cmd ""
		catch { set cmd [$menu entrycget $i -command] }
		if {[regexp {::action::run (\S+)} $cmd -> id]} {
			lappend ids $id
		} else {
			lappend ids header
		}
	}
	return $ids
}

tcltest::test context-live-site-popup {the Sites table's registered -popupcmd posts the C5 menu} -setup {
	set dir [file join [file dirname [file normalize [info script]]] tmp-app]
	file mkdir $dir
	set ::scidb::test::ctx::sitePgn [file join $dir "ctxsite_[pid]_[clock microseconds].pgn"]
	set fh [open $::scidb::test::ctx::sitePgn w]
	puts $fh {[Event "Site Test 1"]}
	puts $fh {[Site "https://example.com"]}
	puts $fh {[Date "2026.10.20"]}
	puts $fh {[Round "1"]}
	puts $fh {[White "W1"]}
	puts $fh {[Black "B1"]}
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. e4 e5 1-0}
	puts $fh ""
	puts $fh {[Event "Site Test 2"]}
	puts $fh {[Site "Local Club"]}
	puts $fh {[Date "2026.10.20"]}
	puts $fh {[Round "2"]}
	puts $fh {[White "W2"]}
	puts $fh {[Black "B2"]}
	puts $fh {[Result "0-1"]}
	puts $fh ""
	puts $fh {1. d4 d5 0-1}
	close $fh
	catch { ::application::database::openBase .application $::scidb::test::ctx::sitePgn yes }
	::scidb::test::ctx::Settle 500
	catch { ::application::switchTab database }
	::scidb::test::ctx::Settle 500
	catch { ::application::database::site::InitBase \
		.application.nb.database.contents.site.twm $::scidb::test::ctx::sitePgn Normal }
	::scidb::test::ctx::Settle 500
	set ::scidb::test::ctx::siteTable ""
	set tries 0
	while {$::scidb::test::ctx::siteTable eq "" && $tries < 20} {
		set ::scidb::test::ctx::siteTable [::scidb::test::ctx::FindSiteTable .application]
		if {$::scidb::test::ctx::siteTable eq ""} {
			incr tries
			::scidb::test::ctx::Settle 100
		}
	}
} -body {
	set table $::scidb::test::ctx::siteTable
	if {$table eq ""} { return no-live-sites-table }
	set popup [::scidb::test::ctx::PopupCmd $table]
	if {[llength $popup] == 0} { return no-popupcmd }
	set base $::scidb::test::ctx::sitePgn
	set path [winfo parent [winfo parent $table]]
	catch { ::sitetable::update $path $base Normal 2 }
	::scidb::test::ctx::Settle 200
	set menu .ctxsite
	catch { destroy $menu }
	menu $menu -tearoff 0
	{*}$popup $path $menu $base Normal 0 site
	set ids [::scidb::test::ctx::RowIds $menu]
	set seenAsk 0
	set labels [::scidb::test::ctx::Canon [::scidb::test::ctx::List $menu] seenAsk]
	destroy $menu
	set expected [::scidb::test::ctx::Expected C5 site]
	set expectedIds {context.ask SEP c5.site_url SEP c5.open_switcher c5.save_working_set}
	list [expr {$labels eq $expected}] [expr {$ids eq $expectedIds}] $ids
} -cleanup {
	catch { destroy .ctxsite }
	catch { ::application::database::closeBase .application $::scidb::test::ctx::sitePgn }
	catch { $::application::database::Vars(switcher) remove $::scidb::test::ctx::sitePgn }
	catch { ::scidb::db::close $::scidb::test::ctx::sitePgn }
	catch { file delete -force $::scidb::test::ctx::sitePgn }
} -result {1 1 {context.ask SEP c5.site_url SEP c5.open_switcher c5.save_working_set}}

# --- VAL-CTX-003: one builder per object -------------------------------

tcltest::test context-one-builder {each object menu is built by ::context::Build, not a copy} -body {
	set dir [file dirname [file normalize [info script]]]
	set bad {}
	foreach {file proc} {
		app-board.tcl	::application::board::PopupMenu
		app-pgn.tcl		::application::pgn::PopupMenu
		gametable.tcl	::gamestable::PopupMenu
		app-database.tcl ::application::database::PopupMenu
		app-analysis.tcl ::application::analysis::PopupMenu
		app-tree.tcl	::application::tree::PopupMenu
		playertable.tcl ::playertable::popupMenu
		eventtable.tcl	::eventtable::popupMenu
		sitetable.tcl	::sitetable::popupMenu
		sitetable.tcl	::sitetable::PopupMenu
		app-twm.tcl		::application::twm::Menu
	} {
		set body ""
		if {[llength [info procs $proc]]} { set body [info body $proc] }
		if {[string first "::context::Build" $body] < 0
		 && [string first "::context::Post" $body] < 0} { lappend bad $proc }
	}
	set bad
} -result {}


destroy .ctxlist
tcltest::cleanupTests
