# ======================================================================
# Lichess Tournaments & Simuls tab (::lichess::events).
# Tab "Lichess tournaments" in the Chesswiz Online window:
# - Arenas list (::lichess::api::arenas, ::lichess::api::arena) with
#   Join (::lichess::api::joinArena) and Withdraw
#   (::lichess::api::withdrawArena).
# - Team Swiss list (::lichess::api::swissOfTeam) with Join
#   (::lichess::api::joinSwiss) and Withdraw
#   (::lichess::api::withdrawSwiss).
# - Simuls list (::lichess::api::simuls); joining a simul is web-only,
#   so Open Simul opens the simul page in the browser via
#   ::lichess::api::OpenBrowser.
# ======================================================================

::util::source lichess-events

package require Tcl 8.5
package require Tk 8.5

namespace eval ::lichess::events {
namespace eval mc {

set TabTitle				"Lichess tournaments"
set ArenasGroup			"Arena tournaments"
set RefreshArenas			"Refresh arenas"
set ArenaIdLabel			"Arena ID:"
set InspectArena			"Details"
set JoinArena				"Join arena"
set WithdrawArena			"Withdraw"
set SwissGroup				"Team Swiss tournaments"
set TeamIdLabel			"Team ID:"
set LoadSwiss				"Load Swiss"
set SwissIdLabel			"Swiss ID:"
set JoinSwiss				"Join Swiss"
set WithdrawSwiss			"Withdraw Swiss"
set SimulsGroup			"Simultaneous exhibitions (Simuls)"
set RefreshSimuls			"Refresh simuls"
set SimulIdLabel			"Simul ID:"
set OpenSimulBrowser		"Open simul in browser (join on web)"
set LoadingArenas			"Loading arena tournaments…"
set LoadingSwiss			"Loading Swiss tournaments for %s…"
set LoadingSimuls			"Loading simuls…"
set JoinedArena			"Joined arena %s."
set WithdrewArena			"Withdrew from arena %s."
set JoinedSwiss			"Joined Swiss tournament %s."
set WithdrewSwiss			"Withdrew from Swiss tournament %s."
set OpenedSimul			"Opened simul %s in web browser."
set EnterArenaId			"Enter or select an arena ID first."
set EnterTeamId			"Enter a team ID first."
set EnterSwissId			"Enter or select a Swiss tournament ID first."
set EnterSimulId			"Enter or select a simul ID first."

} ;# namespace mc

array set Priv {
	tab				{}
	statusText		{}
	arenas			{}
	arenaDetail		{}
	arenaDetailText {}
	arenaId			{}
	teamId			{}
	swissList		{}
	swissId			{}
	simuls			{}
	simulId			{}
}

} ;# namespace ::lichess::events


proc ::lichess::events::open {{parent .application}} {
	variable Priv
	variable mc

	set tab [::online::window::tab lichess-events $mc::TabTitle]
	::online::window::select lichess-events
	if {[info exists Priv(widget:top)] && [winfo exists $Priv(widget:top)]} {
		return $tab
	}
	set Priv(tab) $tab

	set top [ttk::frame $tab.top]
	pack $top -fill both -expand yes
	set Priv(widget:top) $top

	# 1. Arenas section
	set af [ttk::labelframe $top.arenas -text $mc::ArenasGroup -padding 6]
	set atree [ttk::treeview $af.tree -height 6 -selectmode browse \
		-columns {id name status players variant} -show headings]
	$atree heading id -text "ID"
	$atree heading name -text "Arena"
	$atree heading status -text "State"
	$atree heading players -text "Players"
	$atree heading variant -text "Variant"
	$atree column id -width 85 -anchor w
	$atree column name -width 220 -stretch 1 -anchor w
	$atree column status -width 80 -anchor w
	$atree column players -width 70 -anchor e
	$atree column variant -width 95 -anchor w
	bind $atree <<TreeviewSelect>> [namespace code OnSelectArena]
	pack $atree -fill both -expand yes -pady {0 4}
	set Priv(widget:arenas) $atree

	set aform [ttk::frame $af.form]
	ttk::button $aform.refresh -text $mc::RefreshArenas \
		-command [namespace code RefreshArenas]
	ttk::label $aform.idl -text $mc::ArenaIdLabel
	ttk::entry $aform.ide -width 12 -textvariable [namespace current]::Priv(arenaId)
	ttk::button $aform.info -text $mc::InspectArena \
		-command [namespace code InspectArena]
	ttk::button $aform.join -text $mc::JoinArena \
		-command [namespace code JoinArena]
	ttk::button $aform.withdraw -text $mc::WithdrawArena \
		-command [namespace code WithdrawArena]
	pack $aform.refresh -side left -padx {0 6}
	pack $aform.idl -side left
	pack $aform.ide -side left -padx 4
	pack $aform.info $aform.join $aform.withdraw -side left -padx {0 4}
	pack $aform -fill x
	ttk::label $af.detail -anchor w -justify left -wraplength 650 \
		-textvariable [namespace current]::Priv(arenaDetailText)
	pack $af.detail -fill x -pady {4 0}
	pack $af -fill both -expand yes -pady {0 6}

	# 2. Team Swiss section
	set sf [ttk::labelframe $top.swiss -text $mc::SwissGroup -padding 6]
	set stree [ttk::treeview $sf.tree -height 5 -selectmode browse \
		-columns {id name status round players} -show headings]
	$stree heading id -text "ID"
	$stree heading name -text "Swiss Tournament"
	$stree heading status -text "Status"
	$stree heading round -text "Round"
	$stree heading players -text "Players"
	$stree column id -width 85 -anchor w
	$stree column name -width 220 -stretch 1 -anchor w
	$stree column status -width 80 -anchor w
	$stree column round -width 70 -anchor center
	$stree column players -width 70 -anchor e
	bind $stree <<TreeviewSelect>> [namespace code OnSelectSwiss]
	pack $stree -fill both -expand yes -pady {0 4}
	set Priv(widget:swiss) $stree

	set sform [ttk::frame $sf.form]
	ttk::label $sform.tlbl -text $mc::TeamIdLabel
	ttk::entry $sform.tentry -width 14 -textvariable [namespace current]::Priv(teamId)
	ttk::button $sform.load -text $mc::LoadSwiss \
		-command [namespace code LoadTeamSwiss]
	ttk::label $sform.slbl -text $mc::SwissIdLabel
	ttk::entry $sform.sentry -width 12 -textvariable [namespace current]::Priv(swissId)
	ttk::button $sform.join -text $mc::JoinSwiss \
		-command [namespace code JoinSwiss]
	ttk::button $sform.withdraw -text $mc::WithdrawSwiss \
		-command [namespace code WithdrawSwiss]
	pack $sform.tlbl -side left
	pack $sform.tentry -side left -padx 4
	pack $sform.load -side left -padx {0 8}
	pack $sform.slbl -side left
	pack $sform.sentry -side left -padx 4
	pack $sform.join $sform.withdraw -side left -padx {0 4}
	pack $sform -fill x
	pack $sf -fill both -expand yes -pady {0 6}

	# 3. Simuls section
	set mf [ttk::labelframe $top.simuls -text $mc::SimulsGroup -padding 6]
	set mtree [ttk::treeview $mf.tree -height 5 -selectmode browse \
		-columns {id name host status variants} -show headings]
	$mtree heading id -text "ID"
	$mtree heading name -text "Simul"
	$mtree heading host -text "Host"
	$mtree heading status -text "State"
	$mtree heading variants -text "Variants"
	$mtree column id -width 85 -anchor w
	$mtree column name -width 200 -stretch 1 -anchor w
	$mtree column host -width 120 -anchor w
	$mtree column status -width 80 -anchor w
	$mtree column variants -width 100 -anchor w
	bind $mtree <<TreeviewSelect>> [namespace code OnSelectSimul]
	bind $mtree <Double-1> [namespace code OpenSimulInBrowser]
	pack $mtree -fill both -expand yes -pady {0 4}
	set Priv(widget:simuls) $mtree

	set mform [ttk::frame $mf.form]
	ttk::button $mform.refresh -text $mc::RefreshSimuls \
		-command [namespace code RefreshSimuls]
	ttk::label $mform.idl -text $mc::SimulIdLabel
	ttk::entry $mform.ide -width 12 -textvariable [namespace current]::Priv(simulId)
	ttk::button $mform.open -text $mc::OpenSimulBrowser \
		-command [namespace code OpenSimulInBrowser]
	pack $mform.refresh -side left -padx {0 6}
	pack $mform.idl -side left
	pack $mform.ide -side left -padx 4
	pack $mform.open -side left -padx {4 0}
	pack $mform -fill x
	pack $mf -fill both -expand yes

	ttk::label $tab.status -anchor w -justify left -wraplength 700 \
		-textvariable [namespace current]::Priv(statusText)
	pack $tab.status -side bottom -fill x -pady {6 0}

	RefreshArenas
	RefreshSimuls
	return $tab
}


proc ::lichess::events::Status {text} {
	variable Priv
	set Priv(statusText) $text
	::online::window::status $text
}


# ======================================================================
# Arenas
# ======================================================================

proc ::lichess::events::RefreshArenas {} {
	variable mc
	if {![llength [info commands ::lichess::api::arenas]]} { return 0 }
	Status $mc::LoadingArenas
	::lichess::api::arenas [namespace code OnArenas]
	return 1
}


proc ::lichess::events::OnArenas {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load arenas."}]
		return
	}
	set data [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(arenas) $data
	if {![info exists Priv(widget:arenas)] || ![winfo exists $Priv(widget:arenas)]} { return }
	set tree $Priv(widget:arenas)
	$tree delete [$tree children {}]
	if {[catch {dict size $data}]} { return }
	foreach group {started created finished} {
		if {![dict exists $data $group]} { continue }
		foreach item [dict get $data $group] {
			if {[catch {dict size $item}]} { continue }
			set id [expr {[dict exists $item id] ? [dict get $item id] : ""}]
			if {$id eq ""} { continue }
			set name [expr {[dict exists $item fullName] ? [dict get $item fullName] : \
				[dict exists $item name] ? [dict get $item name] : $id}]
			set players [expr {[dict exists $item nbPlayers] ? [dict get $item nbPlayers] : ""}]
			set var [expr {[dict exists $item variant name] ? [dict get $item variant name] : \
				[dict exists $item variant key] ? [dict get $item variant key] : "standard"}]
			if {![$tree exists $id]} {
				$tree insert {} end -id $id -values [list $id $name $group $players $var]
			}
			if {$Priv(arenaId) eq ""} { set Priv(arenaId) $id }
		}
	}
}


proc ::lichess::events::OnSelectArena {} {
	variable Priv
	if {![info exists Priv(widget:arenas)] || ![winfo exists $Priv(widget:arenas)]} { return }
	set sel [$Priv(widget:arenas) selection]
	if {[llength $sel]} {
		set Priv(arenaId) [lindex $sel 0]
	}
}


proc ::lichess::events::InspectArena {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(arenaId) $id }
	set aid [string trim $Priv(arenaId)]
	if {$aid eq ""} {
		Status $mc::EnterArenaId
		return 0
	}
	::lichess::api::arena $aid [namespace code [list OnArenaDetail $aid]]
	return 1
}


proc ::lichess::events::OnArenaDetail {id reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load arena."}]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set Priv(arenaDetail) $d
	set name [expr {[dict exists $d fullName] ? [dict get $d fullName] : \
		[dict exists $d name] ? [dict get $d name] : $id}]
	set nb [expr {[dict exists $d nbPlayers] ? [dict get $d nbPlayers] : 0}]
	set mins [expr {[dict exists $d minutes] ? [dict get $d minutes] : ""}]
	set text "${name} (${id}) — ${nb} players"
	if {$mins ne ""} { append text ", ${mins} min" }
	set Priv(arenaDetailText) $text
	Status $text
}


proc ::lichess::events::JoinArena {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(arenaId) $id }
	set aid [string trim $Priv(arenaId)]
	if {$aid eq ""} {
		Status $mc::EnterArenaId
		return 0
	}
	::lichess::api::joinArena $aid [namespace code [list OnArenaJoined $aid]]
	return 1
}


proc ::lichess::events::OnArenaJoined {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::JoinedArena $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not join arena."}]
	}
}


proc ::lichess::events::WithdrawArena {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(arenaId) $id }
	set aid [string trim $Priv(arenaId)]
	if {$aid eq ""} {
		Status $mc::EnterArenaId
		return 0
	}
	::lichess::api::withdrawArena $aid [namespace code [list OnArenaWithdrawn $aid]]
	return 1
}


proc ::lichess::events::OnArenaWithdrawn {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::WithdrewArena $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not withdraw from arena."}]
	}
}


# ======================================================================
# Team Swiss tournaments
# ======================================================================

proc ::lichess::events::LoadTeamSwiss {{teamId ""}} {
	variable Priv
	variable mc
	if {$teamId ne ""} { set Priv(teamId) $teamId }
	set tid [string trim $Priv(teamId)]
	if {$tid eq ""} {
		Status $mc::EnterTeamId
		return 0
	}
	Status [format $mc::LoadingSwiss $tid]
	::lichess::api::swissOfTeam $tid [namespace code [list OnSwissList $tid]]
	return 1
}


proc ::lichess::events::OnSwissList {tid reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load Swiss tournaments."}]
		return
	}
	set items [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(swissList) $items
	if {![info exists Priv(widget:swiss)] || ![winfo exists $Priv(widget:swiss)]} { return }
	set tree $Priv(widget:swiss)
	$tree delete [$tree children {}]
	foreach item $items {
		if {[catch {dict size $item}]} { continue }
		set id [expr {[dict exists $item id] ? [dict get $item id] : ""}]
		if {$id eq ""} { continue }
		set name [expr {[dict exists $item name] ? [dict get $item name] : $id}]
		set status [expr {[dict exists $item status] ? [dict get $item status] : ""}]
		set round [expr {[dict exists $item round] ? [dict get $item round] : ""}]
		set nb [expr {[dict exists $item nbPlayers] ? [dict get $item nbPlayers] : ""}]
		$tree insert {} end -id $id -values [list $id $name $status $round $nb]
		if {$Priv(swissId) eq ""} { set Priv(swissId) $id }
	}
}


proc ::lichess::events::OnSelectSwiss {} {
	variable Priv
	if {![info exists Priv(widget:swiss)] || ![winfo exists $Priv(widget:swiss)]} { return }
	set sel [$Priv(widget:swiss) selection]
	if {[llength $sel]} {
		set Priv(swissId) [lindex $sel 0]
	}
}


proc ::lichess::events::JoinSwiss {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(swissId) $id }
	set sid [string trim $Priv(swissId)]
	if {$sid eq ""} {
		Status $mc::EnterSwissId
		return 0
	}
	::lichess::api::joinSwiss $sid [namespace code [list OnSwissJoined $sid]]
	return 1
}


proc ::lichess::events::OnSwissJoined {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::JoinedSwiss $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not join Swiss tournament."}]
	}
}


proc ::lichess::events::WithdrawSwiss {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(swissId) $id }
	set sid [string trim $Priv(swissId)]
	if {$sid eq ""} {
		Status $mc::EnterSwissId
		return 0
	}
	::lichess::api::withdrawSwiss $sid [namespace code [list OnSwissWithdrawn $sid]]
	return 1
}


proc ::lichess::events::OnSwissWithdrawn {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::WithdrewSwiss $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not withdraw from Swiss tournament."}]
	}
}


# ======================================================================
# Simuls (web-only join -> OpenBrowser)
# ======================================================================

proc ::lichess::events::RefreshSimuls {} {
	variable mc
	if {![llength [info commands ::lichess::api::simuls]]} { return 0 }
	Status $mc::LoadingSimuls
	::lichess::api::simuls [namespace code OnSimuls]
	return 1
}


proc ::lichess::events::OnSimuls {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load simuls."}]
		return
	}
	set data [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(simuls) $data
	if {![info exists Priv(widget:simuls)] || ![winfo exists $Priv(widget:simuls)]} { return }
	set tree $Priv(widget:simuls)
	$tree delete [$tree children {}]
	if {[catch {dict size $data}]} { return }
	foreach group {started created pending finished} {
		if {![dict exists $data $group]} { continue }
		foreach item [dict get $data $group] {
			if {[catch {dict size $item}]} { continue }
			set id [expr {[dict exists $item id] ? [dict get $item id] : ""}]
			if {$id eq ""} { continue }
			set name [expr {[dict exists $item fullName] ? [dict get $item fullName] : \
				[dict exists $item name] ? [dict get $item name] : $id}]
			set host [expr {[dict exists $item host name] ? [dict get $item host name] : ""}]
			set vars {}
			if {[dict exists $item variants]} {
				foreach v [dict get $item variants] {
					if {![catch {dict exists $v name}] && [dict exists $v name]} {
						lappend vars [dict get $v name]
					}
				}
			}
			if {![$tree exists $id]} {
				$tree insert {} end -id $id -values [list $id $name $host $group [join $vars ", "]]
			}
			if {$Priv(simulId) eq ""} { set Priv(simulId) $id }
		}
	}
}


proc ::lichess::events::OnSelectSimul {} {
	variable Priv
	if {![info exists Priv(widget:simuls)] || ![winfo exists $Priv(widget:simuls)]} { return }
	set sel [$Priv(widget:simuls) selection]
	if {[llength $sel]} {
		set Priv(simulId) [lindex $sel 0]
	}
}


proc ::lichess::events::OpenSimulInBrowser {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(simulId) $id }
	set sid [string trim $Priv(simulId)]
	if {$sid eq ""} {
		Status $mc::EnterSimulId
		return 0
	}
	set base [expr {[info exists ::lichess::api::Base] ? [string trimright $::lichess::api::Base /] : "https://lichess.org"}]
	set url "$base/simul/$sid"
	catch { ::lichess::api::OpenBrowser $url }
	Status [format $mc::OpenedSimul $sid]
	return $url
}

# vi:set ts=3 sw=3:
