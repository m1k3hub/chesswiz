# ======================================================================
# Static registry walk (VAL-REG-002)
# ======================================================================
# Every built menu surface and every toolbar button must dispatch through
# ::action::run. Headings and hints are non-command structural rows.
# Only the fixed dynamic row classes named in the contract may be exempt.
# This file reports the count of each surface.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::rgw {}

# Walk the actual populated state, including a loaded generated game, rather
# than relying on an empty startup menu to expose all command surfaces.
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set ::scidb::test::rgw::base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $::scidb::test::rgw::base]
::action::run open_game {number 1}

# Ordinary posting includes lazy dynamic cascades, unlike Dump mode.
proc ::scidb::test::rgw::PostTree {menu} {
    if {[tk windowingsystem] eq "x11"} {
        $menu post 20 20
    } else {
        # Native post blocks inside the OS menu loop. Populate the same lazy
        # entries through their postcommand, then inspect without posting.
        set command [$menu cget -postcommand]
        if {$command ne ""} {uplevel #0 $command}
    }
    update idletasks
    set last [$menu index end]
    if {$last ne "none"} {
        for {set i 0} {$i <= $last} {incr i} {
            if {[$menu type $i] eq "cascade"} {
                set sub [$menu entrycget $i -menu]
                if {$sub ne ""} {::scidb::test::rgw::PostTree $sub}
            }
        }
    }
    if {[tk windowingsystem] eq "x11"} {$menu unpost}
}

proc ::scidb::test::rgw::WalkMenu {menu rowsVar {surface ""}} {
	upvar $rowsVar rows
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { continue }
		if {$type eq "cascade"} {
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			if {$sub ne "" && [winfo exists $sub]} {
				::scidb::test::rgw::WalkMenu $sub rows $surface
			}
			continue
		}
		set cmd ""
		catch { set cmd [$menu entrycget $i -command] }
		set state normal
		catch { set state [$menu entrycget $i -state] }
		set label ""
		catch { set label [string trim [$menu entrycget $i -label]] }
		lappend rows [list $surface $type $state $label $cmd]
	}
}

proc ::scidb::test::rgw::Objects {} {
	return [dict create \
		C1 [dict create square e4 fen {8/8/8/8/4P3/8/8/8 w - - 0 1}] \
		C2 [dict create base b variant Normal index 5 ply 10 san Nf3] \
		C3 [dict create base b variant Normal index 1 column number \
			sortable 1 path .rgwlist view 0] \
		C4 [dict create base testbase] \
		C5.player [dict create kind player name {Carlsen, Magnus} base b] \
		C5.event [dict create kind event name Wijk base b] \
		C5.site [dict create kind site name wijk.com base b] \
		C5.annotator [dict create kind annotator name Generated rowId Generated base b variant Normal] \
		C5.position [dict create kind position name Standard rowId 518 base b variant Normal] \
		C6 [dict create engine SF lineId 1 pv {e4 e5 Nf3}] \
		C7 [dict create base b mediaId m1 path /tmp/clip.mp4] \
		C8 [dict create fen {8/8/8/8/4P3/8/8/8 w - - 0 1} move e4 table .rgwtree] \
		C9.board [dict create paneUid board frame .rgwpane] \
		C9.editor [dict create paneUid editor frame .rgwpane] \
		C9.games [dict create paneUid games frame .rgwpane] \
		C9.people [dict create paneUid players frame .rgwpane] \
		C9.tree [dict create paneUid tree frame .rgwpane] \
		C9.analysis [dict create paneUid analysis:1 frame .rgwpane] \
		C9.media [dict create paneUid media frame .rgwpane] \
		C9.report [dict create paneUid report frame .rgwpane] \
		C9.assistant [dict create paneUid assistant frame .rgwpane] \
		C9.explorer [dict create paneUid explorer frame .rgwpane] \
		C10 [dict create table .rgwlist column date] \
		C11 [dict create base b index 5 ply 10 widget .rgwtxt] \
		C12 [dict create gameSlot 1 history {G1 G2}] \
	]
}

proc ::scidb::test::rgw::WalkContexts {} {
	set objects [::scidb::test::rgw::Objects]
	set keys {}
	foreach key [dict keys $objects] { lappend keys [lindex [split $key .] 0] }
	set rows {}
	set built 0
	foreach cid [lsort -unique $keys] {
		foreach key [dict keys $objects] {
			if {[lindex [split $key .] 0] ne $cid} { continue }
			set menu .rgwctx[incr built]
			catch { destroy $menu }
			menu $menu -tearoff 0
			catch { ::context::Build $cid $menu [dict get $objects $key] }
			::scidb::test::rgw::WalkMenu $menu rows $key
			catch { destroy $menu }
		}
	}
	return $rows
}

proc ::scidb::test::rgw::Toolbars {w rowsVar} {
	upvar $rowsVar rows
	if {[winfo class $w] eq "Toolbar"} {
		foreach child [winfo children $w] {
			set cls [winfo class $child]
			if {$cls ni {Button DropdownButton Checkbutton Radiobutton}} { continue }
			set cmd ""
			catch { set cmd [$child cget -command] }
			# SetState clears native -command while disabled, retaining the
			# actual activation callback in the toolbar's own Specs table.
			if {$cmd eq "" && [info exists ::toolbar::Specs(command:$child:$w)]} {
				set cmd $::toolbar::Specs(command:$child:$w)
			}
			set type $cls
			if {$cls eq "DropdownButton" && $cmd eq ""
			 && [info exists ::toolbar::Specs(menucmd:$child:$w)]
			 && $::toolbar::Specs(menucmd:$child:$w) ne ""} {
				# This is a menu opener, like a Tk cascade; its leaves are
				# walked as menu commands, not as an empty button callback.
				set type cascade
				set popup $child.rgwmenu
				catch {destroy $popup}
				menu $popup -tearoff 0
				{*}$::toolbar::Specs(menucmd:$child:$w) $child $popup
				::scidb::test::rgw::PostTree $popup
				::scidb::test::rgw::WalkMenu $popup rows toolbar-menu
				destroy $popup
			}
			set label ""
			catch { set label [$child cget -text] }
			if {$label eq ""} { catch { set label [$child cget -tooltip] } }
			lappend rows [list toolbar $type normal $label $cmd]
			# Custom toolbar checkbuttons mutate state in widget bindings.
			# Walk activation bindings too, even when -command is empty.
			foreach event [bind $child] {
				if {![regexp {^<(Button(?:Press|Release)?-1|Key.*|Return|space)>$} $event]} {continue}
				set script [string trim [bind $child $event]]
				# Button press only hides the tooltip (or blocks a disabled
				# control). Neither performs a product operation.
				if {$script in {"" break ::tooltip::hide}} {continue}
				lappend rows [list toolbar-binding $event normal $label $script]
			}
		}
	}
	foreach child [winfo children $w] {
		::scidb::test::rgw::Toolbars $child rows
	}
}

proc ::scidb::test::rgw::BadCommands {rows} {
	set bad {}
	foreach row $rows {
		lassign $row surface type state label cmd
		if {$type eq "cascade"} { continue }
		if {![string match "::action::run *" [string trim $cmd]]} {
			lappend bad $row
		}
	}
	return $bad
}

# Replace only the final handler: real argument validation, capability,
# object, enabled, confirmation and bulk gates remain in the invoke path.
# Named real effects are tested separately without these sentinels.
proc ::scidb::test::rgw::Leaf {id args} {
    variable reached
    incr reached
    return posted-handler
}
proc ::scidb::test::rgw::Accept {args} { return 1 }

proc ::scidb::test::rgw::InvokeRow {row id} {
    variable reached
    set record [::action::get $id]
    set confirm $::action::ConfirmHook
    set bulk $::action::BulkHook
    set reached 0
    dict set ::action::Registry $id handler [list ::scidb::test::rgw::Leaf $id]
    set ::action::ConfirmHook ::scidb::test::rgw::Accept
    set ::action::BulkHook ::scidb::test::rgw::Accept
    # Bindings may end with a Tcl "break" command after the action.
    set command [lindex $row 4]
    if {[lindex $row 0] eq "toolbar-binding"} {
        set command [lindex [split $command "\n;"] 0]
    }
    set code [catch {
        set result [::action::invoke $id {*}[lrange $command 2 end]]
        # Native context rows defer until popup tracking has ended.
        update idletasks
        set result
    } reply options]
    # Restore even on exceptions so later rows cannot inherit substitutions.
    dict set ::action::Registry $id $record
    set ::action::ConfirmHook $confirm
    set ::action::BulkHook $bulk
    set expected [expr {[lindex $row 2] ne "disabled"}]
    puts [list POSTED_INVOKE [lindex $row 0] $id state [lindex $row 2] catch $code reply $reply leaf $reached expected $expected]
    if {$code} { return -options $options $reply }
    if {$reached != $expected} {
        error "posted $id: expected $expected handler calls, got $reached: $reply"
    }
}

# Resolve and invoke every registered posted row. The existing bad-command
# assertions still reject unregistered commands and count exemptions.
proc ::scidb::test::rgw::ResolveRows {rows} {
	set resolved 0
	set exempt {}
	set unresolved {}
	foreach row $rows {
		set cmd [string trim [lindex $row 4]]
		if {$cmd eq "" || ![regexp {^::action::run ([^\s]+)} $cmd -> id]} {
			lappend exempt $row
			continue
		}
		if {[catch { ::action::get $id }]} {
			lappend unresolved [list [lindex $row 0] [lindex $row 3] $id]
		} else {
			incr resolved
            ::scidb::test::rgw::InvokeRow $row $id
            puts [list POSTED_ID [lindex $row 0] $id state [lindex $row 2] resolved 1 command $cmd]
		}
	}
	return [list $resolved $exempt $unresolved]
}

tcltest::test registry-walk-empty-command-is-bad {blank command rows are not an exemption, even when disabled} -body {
    set rows {{native command disabled Games {}} {dropdown command normal Hint {}}}
    expr {[::scidb::test::rgw::BadCommands $rows] eq $rows}
} -result 1

tcltest::test registry-walk-dropdown {every drop-down command is ::action::run} -body {
	catch { destroy .rgwdd }
	menu .rgwdd -tearoff 0
	::menu::BuildDropdown .rgwdd
	::scidb::test::rgw::PostTree .rgwdd
	set rows {}
	::scidb::test::rgw::WalkMenu .rgwdd rows dropdown
	set bad [::scidb::test::rgw::BadCommands $rows]
	set ids {}
	foreach row $rows {
		if {[regexp {^::action::run (\S+)$} [lindex $row 4] -> id]} { lappend ids $id }
	}
	lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unresolved
	destroy .rgwdd
	puts "REG-002 dropdown: [llength $rows] rows, [llength [lsort -unique $ids]] actions, [llength $bad] bad, ${resolved} resolved, [llength $exempt] exempt, [llength $unresolved] unresolved"
	foreach u $unresolved { puts "  unresolved: $u" }
	list $bad [expr {[llength [lsort -unique $ids]] > 100}] $unresolved
} -result {{} 1 {}}

tcltest::test registry-walk-contexts {every C1-C12 command is ::action::run} -body {
	set rows [::scidb::test::rgw::WalkContexts]
	set bad [::scidb::test::rgw::BadCommands $rows]
	set per {}
	foreach row $rows {
		set s [lindex $row 0]
		dict incr per $s
	}
	lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unresolved
	puts "REG-002 contexts: [dict size $per] objects, [llength $rows] rows, [llength $bad] bad, ${resolved} resolved, [llength $exempt] exempt, [llength $unresolved] unresolved"
	foreach key [lsort [dict keys $per]] { puts "  $key: [dict get $per $key]" }
	foreach u $unresolved { puts "  unresolved: $u" }
	list $bad [expr {[llength $rows] > 150}] $unresolved
} -result {{} 1 {}}

tcltest::test registry-walk-toolbars {every toolbar button command is ::action::run} -body {
	set rows {}
	::scidb::test::rgw::Toolbars . rows
	set bad [::scidb::test::rgw::BadCommands $rows]
	set seen 0
	set ids {}
	foreach row $rows {
		if {[string trim [lindex $row 4]] eq ""} { continue }
		incr seen
		if {[regexp {^::action::run (\S+)$} [lindex $row 4] -> id]} { lappend ids $id }
	}
	lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unresolved
	puts "REG-002 toolbars: $seen actionable buttons, [llength [lsort -unique $ids]] actions, [llength $bad] bad, ${resolved} resolved, [llength $exempt] exempt, [llength $unresolved] unresolved"
	foreach row $bad { puts "  bad: $row" }
	foreach u $unresolved { puts "  unresolved: $u" }
	list $bad [expr {$seen > 20}] $unresolved
} -result {{} 1 {}}

# The board pane's always-visible Media button is a plain ttk::button, so the
# Toolbar walk above never reaches its popup. Walk the posted menu directly:
# its media rows, Stop and Open stream... all dispatch through registry ids.
tcltest::test registry-walk-media-button {the board Media button popup dispatches every row through registered ids} -setup {
    source tests/app_actions_support.tcl
    ::scidb::test::actions::ready
    set base [::scidb::test::actions::fixture]
    ::action::run open_database [dict create path $base]
    ::action::run open_game [dict create number 1]
    ::application::switchTab board
    update idletasks
    ::mediainset::RefreshMediaButton
    # A generated row keeps the test independent of a media fixture while
    # still exercising the real PopulateMenu path for per-item rows.
    rename ::mediainset::Entries ::scidb::test::rgw::savedEntries
    proc ::mediainset::Entries {} {
        return {{row1 Video {Generated clip} /tmp/generated-clip.mp4 0}}
    }
} -body {
    set w [::mediainset::Pane].mediaButton
    if {![winfo exists $w]} { error "board Media button was not built" }
    ::mediainset::PopulateMenu $w.menu
    set rows {}
    ::scidb::test::rgw::WalkMenu $w.menu rows media-button
    set bad [::scidb::test::rgw::BadCommands $rows]
    set ids {}
    foreach row $rows {
        if {[regexp {^::action::run (\S+)} [lindex $row 4] -> id]} { lappend ids $id }
    }
    lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unresolved
    puts "REG-002 media button: [llength $rows] rows, [llength [lsort -unique $ids]] actions, [llength $bad] bad, ${resolved} resolved, [llength $exempt] exempt, [llength $unresolved] unresolved"
    foreach b $bad { puts "  bad: $b" }
    foreach u $unresolved { puts "  unresolved: $u" }
    list $bad $unresolved [lsort -unique $ids] [expr {$resolved == [llength $rows]}]
} -cleanup {
    rename ::mediainset::Entries {}
    rename ::scidb::test::rgw::savedEntries ::mediainset::Entries
    catch { ::mediainset::PopulateMenu [[::mediainset::Pane].mediaButton].menu }
} -result {{} {} {media.play_entry media.stop open_stream} 1}

# Absent module: the stream row disappears and the action itself refuses, and
# every label is read through the message catalog on each populate.
tcltest::test registry-walk-media-stream {absent stream module hides Open stream... and its action refuses} -setup {
    source tests/app_actions_support.tcl
    ::scidb::test::actions::ready
    set ::scidb::test::rgw::savedOverrides $::capability::Overrides
    set ::scidb::test::rgw::savedMC [list $::application::media::mc::Stop \
        $::application::media::mc::OpenStream $::application::media::mc::Title]
    set ::application::media::mc::Stop "Halt"
    set ::application::media::mc::OpenStream "Fetch stream"
    set ::application::media::mc::Title "Reel"
    ::capability::Override stream 0
} -body {
    ::mediainset::RefreshMediaButton
    set w [::mediainset::Pane].mediaButton
    set labels {}
    set streamCommands 0
    for {set i 0} {$i <= [$w.menu index end]} {incr i} {
        if {[$w.menu type $i] ne "command"} { continue }
        lappend labels [$w.menu entrycget $i -label]
        if {[regexp -nocase {openstream} [$w.menu entrycget $i -command]]} {
            incr streamCommands
        }
    }
    set refused [::action::run open_stream [dict create url https://example.test/live.m3u8]]
    puts [list MEDIA_STREAM_ABSENT labels $labels streamCommands $streamCommands button [$w cget -text] refused $refused]
    list [expr {"Halt" in $labels}] [expr {"Fetch stream" ni $labels}] [$w cget -text] \
        [expr {$streamCommands == 0}] [string match {error:*unavailable*} $refused]
} -cleanup {
    set ::application::media::mc::Stop [lindex $::scidb::test::rgw::savedMC 0]
    set ::application::media::mc::OpenStream [lindex $::scidb::test::rgw::savedMC 1]
    set ::application::media::mc::Title [lindex $::scidb::test::rgw::savedMC 2]
    set ::capability::Overrides $::scidb::test::rgw::savedOverrides
    catch { ::mediainset::RefreshMediaButton }
} -result {1 1 Reel 1 1}

tcltest::test registry-walk-ask-is-action {the assistant row is a registry action, not a direct callback} -body {
	set rows [::scidb::test::rgw::WalkContexts]
	set ask {}
	foreach row $rows {
		if {[string match "*What can I do here*" [lindex $row 3]]} { lappend ask $row }
	}
	set direct {}
	foreach row $rows {
		if {[string match "::context::*" [string trim [lindex $row 4]]]} { lappend direct $row }
	}
	list [expr {[llength $ask] > 0}] $direct
} -result {1 {}}

# Native table callers append rows after context::Build returns. Walking
# only the generic builder misses those rows entirely (VS/VU-reg4).
tcltest::test registry-walk-native-named-tables {completed player/event popups, including every appended Sort leaf, resolve by id} -body {
	source tests/app_actions_support.tcl
	::scidb::test::actions::ready
	set base [::scidb::test::actions::fixture]
	::action::run open_database [list path $base]
	::application::switchTab database
	set bad {}
	set unresolved {}
	set sorts 0
	foreach kind {player event} {
		::application::database::select[string totitle $kind] $base Normal 0
		for {set i 0} {$i < 10} {incr i} {after 30; update}
		set manager $::application::database::Vars($kind).twm
		set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
		set table $frame
		if {$kind eq "player"} {append table .table}
		menu .rgwnative -tearoff 0
		::${kind}table::PopupMenu $table .rgwnative $base Normal 0 [expr {$kind eq "player" ? "lastName" : "event"}]
		::scidb::test::rgw::PostTree .rgwnative
		set rows {}
		::scidb::test::rgw::WalkMenu .rgwnative rows C5.$kind
		lappend bad {*}[::scidb::test::rgw::BadCommands $rows]
		lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unknown
		lappend unresolved {*}$unknown
		set count 0
		foreach row $rows {
			if {[string match c5.sort.* [lindex [lindex $row 4] 1]]} {incr count}
		}
		incr sorts $count
		puts [list NATIVE_REGISTRY_WALK $kind rows [llength $rows] resolved $resolved exempt [llength $exempt] sorts $count unresolved $unknown]
		destroy .rgwnative
	}
	list $bad $unresolved $sorts
} -cleanup {catch {destroy .rgwnative}} -result {{} {} 30}


tcltest::test registry-walk-html-drawable {native player-card HTML and drawable registrations are in the global census} -body {
    source tests/app_actions_support.tcl
    source tests/app_html_popup_support.tcl
    ::scidb::test::actions::ready
    set base [::scidb::test::actions::fixture]
    ::action::run open_database [dict create path $base]
    set counts {}
    foreach developer {0 1} {
        lassign [::scidb::test::htmlpop::cardRows $base $developer] dlg html drawable key
        lappend counts [list [llength $html] [llength $drawable]]
        destroy $dlg
    }
    set counts
} -result {{10 2} {12 4}}


tcltest::test registry-walk-html-secondary {all other HTML/drawable branches enter the global popup census} -body {
    source tests/app_actions_support.tcl
    source tests/app_html_popup_support.tcl
    ::scidb::test::actions::ready
    set base [::scidb::test::actions::fixture]
    ::action::run open_database [dict create path $base]
    set rows [::scidb::test::htmlpop::secondaryRows $base]
    set surfaces {}
    foreach row $rows {lappend surfaces [lindex $row 0]}
    set actual [lsort -unique $surfaces]
    puts [list REG-002_HTML_DRAWABLE surfaces $actual rows [llength $rows] exemptions 0]
    list [expr {[llength $rows] > 50}] [::scidb::test::rgw::BadCommands $rows]
} -result {1 {}}

tcltest::cleanupTests
