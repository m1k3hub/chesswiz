# ======================================================================
# Tournament Director workspace: Event / Players / Pairings / Results /
# Standings. Every mutation goes through the td.* registry preview/commit.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-ui }
package require Tcl 8.6
package require Tk 8.6

namespace eval ::td::ui {
	variable Dialog {}
	variable Path {}
	variable Notebook {}
	variable Counter 0
	variable Fields
}

proc ::td::ui::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }
proc ::td::ui::State {} { variable Path; if {$Path eq ""} { return {} }; return [dict get [::td::store::Read $Path] state] }
proc ::td::ui::Revision {} { set state [State]; return [dg $state revision 0] }
proc ::td::ui::Key {command} { variable Counter; return "ui-[pid]-$command-[incr Counter]" }

proc ::td::ui::Mutate {id domain} {
	variable Path
	if {$Path eq ""} { error "no tournament selected" }
	set domain [dict merge $domain [dict create path $Path expected_revision [Revision] idempotency [Key $id] commit 0]]
	set preview [::action::run $id $domain]
	if {[string match "error:*" $preview]} { error $preview }
	dict set domain commit 1
	set result [::action::run $id $domain]
	if {[string match "error:*" $result]} { error $result }
	Refresh
	return $result
}

proc ::td::ui::Safe {script} {
	if {[catch {uplevel 1 $script} err]} {
		catch {::dialog::error -parent [DialogOrApp] -message "Tournament Director" -detail $err}
		return {}
	}
	return $::td::ui::Result
}
proc ::td::ui::DialogOrApp {} { variable Dialog; return [expr {$Dialog ne "" && [winfo exists $Dialog] ? $Dialog : .application}] }

proc ::td::ui::Open {path {tab event}} {
	variable Dialog
	variable Path
	variable Notebook
	if {$path eq ""} { set Path [::td::store::CurrentPath] } else { set Path [file normalize $path] }
	if {$Path ne "" && [file exists $Path]} { ::td::event::Open $Path }
	if {$Dialog ne "" && [winfo exists $Dialog]} { raise $Dialog; Select $tab; return $Dialog }
	set Dialog .application.tournamentDirector
	toplevel $Dialog -class Scidb
	wm title $Dialog "Tournament Director"
	wm transient $Dialog .application
	wm protocol $Dialog WM_DELETE_WINDOW ::td::ui::Close
	set Notebook [ttk::notebook $Dialog.tabs]
	pack $Notebook -fill both -expand yes -padx 6 -pady 6
	foreach name {event players pairings results standings} {
		ttk::frame $Notebook.$name
		$Notebook add $Notebook.$name -text [string totitle $name]
	}
	BuildEvent $Notebook.event
	BuildPlayers $Notebook.players
	BuildPairings $Notebook.pairings
	BuildResults $Notebook.results
	BuildStandings $Notebook.standings
	Select $tab
	Refresh
	wm geometry $Dialog 1100x720
	wm deiconify $Dialog
	return $Dialog
}

proc ::td::ui::Close {} {
	variable Dialog
	variable Path
	if {$Dialog ne "" && [winfo exists $Dialog]} { destroy $Dialog }
	set Dialog {}
	return 1
}
proc ::td::ui::Select {tab} { variable Notebook; if {$Notebook ne "" && [winfo exists $Notebook]} { $Notebook select $Notebook.$tab }; return $tab }

proc ::td::ui::BuildEvent {f} {
	variable Fields
	ttk::frame $f.current
	pack $f.current -fill x -pady 4
	ttk::label $f.current.name
	pack $f.current.name -anchor w
	foreach key {path status revision round backend} { ttk::label $f.current.$key -justify left; pack $f.current.$key -anchor w }
	ttk::frame $f.buttons
	pack $f.buttons -fill x -pady 5
	foreach {text command} {Start Start Stop Stop Undo Undo Redo Redo Publish Publish Finish Finish} {
		ttk::button $f.buttons.[string tolower $text] -text $text -command [list ::td::ui::$command]
		pack $f.buttons.[string tolower $text] -side left -padx 3
	}
	ttk::labelframe $f.new -text "New event"
	pack $f.new -fill x -pady 8
	foreach {label key value} {Name name {Thematic event} {Time control} time_control 3+2 Opening opening {London System}} {
		ttk::label $f.new.label_$key -text $label
		ttk::entry $f.new.$key -width 32 -textvariable ::td::ui::Fields($key)
		set Fields($key) $value
		grid $f.new.label_$key -row 0 -column 0 -sticky w
		grid $f.new.$key -row 0 -column 1 -sticky ew
	}
	# Grid the three rows explicitly rather than sharing one grid row.
	grid forget $f.new.label_time_control $f.new.time_control $f.new.label_opening $f.new.opening
	grid $f.new.label_time_control -row 1 -column 0 -sticky w; grid $f.new.time_control -row 1 -column 1 -sticky ew
	grid $f.new.label_opening -row 2 -column 0 -sticky w; grid $f.new.opening -row 2 -column 1 -sticky ew
	ttk::label $f.new.kindlabel -text "Seat kind"; ttk::combobox $f.new.kind -state readonly -values {engine human} -textvariable ::td::ui::Fields(kind); set Fields(kind) engine
	ttk::label $f.new.countlabel -text "Engines"; ttk::spinbox $f.new.count -from 2 -to 16 -textvariable ::td::ui::Fields(engine_count); set Fields(engine_count) 4
	ttk::label $f.new.systemlabel -text "System"; ttk::combobox $f.new.system -state readonly -values {round-robin double-round-robin swiss} -textvariable ::td::ui::Fields(system); set Fields(system) double-round-robin
	ttk::checkbutton $f.new.start -text "Start immediately" -variable ::td::ui::Fields(start); set Fields(start) 1
	grid $f.new.kindlabel -row 3 -column 0 -sticky w; grid $f.new.kind -row 3 -column 1 -sticky w
	grid $f.new.countlabel -row 4 -column 0 -sticky w; grid $f.new.count -row 4 -column 1 -sticky w
	grid $f.new.systemlabel -row 5 -column 0 -sticky w; grid $f.new.system -row 5 -column 1 -sticky w
	grid $f.new.start -row 6 -column 1 -sticky w
	ttk::button $f.new.create -text "Preview and create" -command ::td::ui::Create
	grid $f.new.create -row 7 -column 1 -sticky e -pady 5
	grid columnconfigure $f.new 1 -weight 1
}

proc ::td::ui::Create {} {
	variable Fields
	variable Path
	set name [string trim $Fields(name)]
	set key [Key create]
	set path [::td::store::DefaultPath $name $key]
	set args [dict create path $path name $name time_control $Fields(time_control) opening $Fields(opening) \
		kind $Fields(kind) engine_count $Fields(engine_count) system $Fields(system) start $Fields(start) \
		commit 0 expected_revision 0 idempotency $key]
	set preview [::action::run td.create $args]
	if {[string match "error:*" $preview]} { error $preview }
	dict set args commit 1
	set result [::action::run td.create $args]
	if {[string match "error:*" $result]} { error $result }
	set Path $path
	Refresh
	return $result
}
proc ::td::ui::Start {} { Mutate td.start {round 0} }
proc ::td::ui::Stop {} { Mutate td.stop {} }
proc ::td::ui::Undo {} { Mutate td.undo {} }
proc ::td::ui::Redo {} { Mutate td.redo {} }
proc ::td::ui::Publish {} { Mutate td.publish {} }
proc ::td::ui::Finish {} { Mutate td.finish {} }

proc ::td::ui::MakeTree {f columns} {
	set tree [ttk::treeview $f.tree -columns $columns -show headings -selectmode browse]
	foreach column $columns { $tree heading $column -text [string totitle $column]; $tree column $column -width 110 }
	pack $tree -fill both -expand yes
	return $tree
}
proc ::td::ui::BuildPlayers {f} {
	variable Fields
	MakeTree $f {number name kind rating withdrawn}
	ttk::frame $f.add; pack $f.add -fill x
	ttk::entry $f.add.name -textvariable ::td::ui::Fields(player_name)
	ttk::combobox $f.add.kind -state readonly -values {human engine} -textvariable ::td::ui::Fields(player_kind)
	set Fields(player_name) {}; set Fields(player_kind) human
    ttk::frame $f.fide; pack $f.fide -fill x
    ttk::label $f.fide.label -text "FIDE ID"
    ttk::entry $f.fide.id -textvariable ::td::ui::Fields(fide_id)
    set Fields(fide_id) {}
    ttk::button $f.fide.add -text "Register from FIDE list" -command ::td::ui::RegisterFide
    pack $f.fide.label $f.fide.id $f.fide.add -side left
	ttk::frame $f.bye; pack $f.bye -fill x
	ttk::label $f.bye.rlabel -text "Round"
	ttk::spinbox $f.bye.round -from 1 -to 99 -width 5 -textvariable ::td::ui::Fields(bye_round); set Fields(bye_round) 1
	ttk::combobox $f.bye.cat -state readonly -values {requested-bye zero-point-bye full-point-bye pairing-bye} -textvariable ::td::ui::Fields(bye_category); set Fields(bye_category) requested-bye
	ttk::button $f.bye.record -text "Record bye" -command ::td::ui::RecordBye
	ttk::button $f.bye.withdraw -text "Withdraw selected" -command ::td::ui::WithdrawSelected
	pack $f.bye.rlabel $f.bye.round $f.bye.cat $f.bye.record $f.bye.withdraw -side left -padx 2
	ttk::button $f.add.button -text "Register" -command ::td::ui::Register
	pack $f.add.name -side left -fill x -expand yes; pack $f.add.kind -side left; pack $f.add.button -side left
}
proc ::td::ui::RecordBye {} {
	variable Fields; variable Notebook
	set player [Selected $Notebook.players.tree]
	Mutate td.bye [dict create player $player round $Fields(bye_round) category $Fields(bye_category) points -1]
}
proc ::td::ui::WithdrawSelected {} {
	variable Fields; variable Notebook
	set player [Selected $Notebook.players.tree]
	Mutate td.withdraw [dict create player $player round $Fields(bye_round)]
}
proc ::td::ui::Register {} {
	variable Fields
	Mutate td.register [dict create players [list $Fields(player_name)] kind $Fields(player_kind)]
	set Fields(player_name) {}
}
proc ::td::ui::BuildPairings {f} {
	variable Fields
	MakeTree $f {id round white black status result}
	ttk::frame $f.buttons; pack $f.buttons -fill x
	ttk::spinbox $f.buttons.round -from 0 -to 1000 -textvariable ::td::ui::Fields(pair_round); set Fields(pair_round) 0
	ttk::button $f.buttons.pair -text "Pair round (0 = all)" -command ::td::ui::PairRound
	ttk::button $f.buttons.swap -text "Swap colours (audited)" -command ::td::ui::Swap
	ttk::button $f.buttons.check -text "Check pairings" -command ::td::ui::CheckPairings
	ttk::label $f.buttons.rlabel -text "TD ruling"
	ttk::entry $f.buttons.ruling -width 24 -textvariable ::td::ui::Fields(override_ruling); set Fields(override_ruling) {}
	pack $f.buttons.round $f.buttons.pair $f.buttons.swap $f.buttons.check $f.buttons.rlabel $f.buttons.ruling -side left -padx 2
	ttk::label $f.checker -justify left -wraplength 1000
	pack $f.checker -fill x -pady 2
}
proc ::td::ui::PairRound {} { variable Fields; Mutate td.pair_round [dict create round $Fields(pair_round)] }
proc ::td::ui::Selected {tree} { set selected [$tree selection]; if {![llength $selected]} { error "select a pairing first" }; return [lindex $selected 0] }
proc ::td::ui::Swap {} {
	variable Notebook; variable Fields
	set tree $Notebook.pairings.tree
	set p {}
	foreach q [dg [State] pairings {}] { if {[dict get $q id] eq [Selected $tree]} { set p $q } }
	set result [Mutate td.override_pairing [dict create pairing [dict get $p id] white [dict get $p black] black [dict get $p white] reason "Manual colour swap in TD workspace" ruling $Fields(override_ruling)]]
	if {[winfo exists $Notebook.pairings.checker]} {
		$Notebook.pairings.checker configure -text "Compliant: [dg $result compliant 1]; violations: [llength [dg $result violations {}]]"
	}
}
proc ::td::ui::CheckPairings {} {
	variable Notebook; variable Fields; variable Path
	set res [::action::run td.check_pairings [dict create path $Path round $Fields(pair_round)]]
	if {[winfo exists $Notebook.pairings.checker]} {
		$Notebook.pairings.checker configure -text "Compliant: [dg $res compliant 1]; violations: [dg $res violations {}]"
	}
	return $res
}
proc ::td::ui::BuildResults {f} {
	variable Fields
	MakeTree $f {id round white black result category}
	ttk::frame $f.edit; pack $f.edit -fill x
	ttk::combobox $f.edit.result -state readonly -values {1-0 0-1 1/2-1/2 0-0 *} -textvariable ::td::ui::Fields(result); set Fields(result) 1/2-1/2
	ttk::combobox $f.edit.category -state readonly -values {played forfeit double-forfeit adjourned} -textvariable ::td::ui::Fields(category); set Fields(category) played
	ttk::entry $f.edit.signed -textvariable ::td::ui::Fields(signed_by)
    ttk::entry $f.edit.reason -textvariable ::td::ui::Fields(result_reason)
    set Fields(signed_by) {}; set Fields(result_reason) {}
    ttk::label $f.edit.signedlabel -text "Signed by"
    ttk::label $f.edit.reasonlabel -text "Correction reason"
    pack $f.edit.signedlabel $f.edit.signed $f.edit.reasonlabel $f.edit.reason -side left
	ttk::button $f.edit.enter -text "Enter result" -command ::td::ui::EnterResult
	ttk::button $f.edit.correct -text "Correct result" -command ::td::ui::CorrectResult
	pack $f.edit.result -side left; pack $f.edit.category -side left; pack $f.edit.enter -side left; pack $f.edit.correct -side left
	ttk::frame $f.ruling; pack $f.ruling -fill x -pady 2
	ttk::combobox $f.ruling.incident -state readonly -values {illegal-move gui-illegal-attempt flag-fall draw-claim-3fold draw-claim-50move 75-move fivefold late-arrival} -textvariable ::td::ui::Fields(ruling_incident); set Fields(ruling_incident) illegal-move
	ttk::combobox $f.ruling.regime -state readonly -values {standard A4 A5 B2 B3} -textvariable ::td::ui::Fields(ruling_regime); set Fields(ruling_regime) standard
	ttk::label $f.ruling.alabel -text "Arbiter"
	ttk::entry $f.ruling.arbiter -width 16 -textvariable ::td::ui::Fields(ruling_arbiter); set Fields(ruling_arbiter) {}
	ttk::button $f.ruling.btn -text "Record ruling" -command ::td::ui::RecordRuling
	pack $f.ruling.incident $f.ruling.regime $f.ruling.alabel $f.ruling.arbiter $f.ruling.btn -side left -padx 2
}
proc ::td::ui::RecordRuling {} {
	variable Fields; variable Notebook
	set pairing [Selected $Notebook.results.tree]
	Mutate td.ruling [dict create pairing $pairing incident $Fields(ruling_incident) regime $Fields(ruling_regime) arbiter $Fields(ruling_arbiter)]
}
proc ::td::ui::ResultCommand {id} {
	variable Fields
	variable Notebook
	set pairing [Selected $Notebook.results.tree]
	set result $Fields(result)
	if {$Fields(category) eq "double-forfeit"} { set result 0-0 }
	Mutate $id [dict create pairing $pairing result $result category $Fields(category) signed_by $Fields(signed_by) reason $Fields(result_reason)]
}
proc ::td::ui::EnterResult {} { ResultCommand td.enter_result }
proc ::td::ui::CorrectResult {} { ResultCommand td.correct_result }

proc ::td::ui::BuildStandings {f} {
	MakeTree $f {rank name score directEncounter sonnebornBerger koya gamesWon gamesWonWithBlack progressive aro tpr}
	bind $f.tree <<TreeviewSelect>> ::td::ui::Breakdown
	ttk::button $f.cross -text "Crosstable" -command ::td::ui::OpenCrosstable
	pack $f.cross -anchor e
	ttk::label $f.breakdown -justify left -wraplength 1000
	pack $f.breakdown -fill x
}
proc ::td::ui::OpenCrosstable {} { variable Path; ::crosstable::OpenTD .application $Path }
proc ::td::ui::Breakdown {} {
	variable Notebook
	set tree $Notebook.standings.tree
	set id [Selected $tree]
	set row {}
	foreach r [::td::score::Compute [State]] { if {[dict get $r id] eq $id} { set row $r } }
	if {$row eq ""} { return }
	set text [::td::score::StandingsText [list $row]]
	dict for {name value} [dg $row tiebreaks {}] {
		if {$value eq ""} { continue }
		append text "\n\n$name: [dict get $value text]\n[dict get $value breakdown]"
	}
	$Notebook.standings.breakdown configure -text $text
}

proc ::td::ui::RefreshPath {path} { variable Path; if {$path eq $Path} { Refresh } }
proc ::td::ui::Refresh {} {
	variable Dialog
	variable Path
	variable Notebook
	if {$Dialog eq "" || ![winfo exists $Dialog]} { return }
	set state [State]
	if {$state eq ""} {
		$Notebook.event.current.name configure -text "No tournament selected"
		return
	}
	set status [dict get $state status]
	$Notebook.event.current.name configure -text "[dict get $state name] — [dict get $state id]"
	$Notebook.event.current.path configure -text "Journal: $Path"
	$Notebook.event.current.status configure -text "Status: $status"
	$Notebook.event.current.revision configure -text "Revision: [dict get $state revision]; publication revision: [dg $state publication_revision 0]"
	$Notebook.event.current.round configure -text "Round: [dg $state current_round 1] / [dg $state rounds 0]"
	$Notebook.event.current.backend configure -text "Store: [::td::store::Backend]"
	foreach tree [list $Notebook.players.tree $Notebook.pairings.tree $Notebook.results.tree $Notebook.standings.tree] {
		foreach row [$tree children {}] { $tree delete $row }
	}
	foreach p [dg $state players {}] {
		$Notebook.players.tree insert {} end -id [dict get $p id] -values [list [dict get $p number] [dict get $p name] [dict get $p kind] [dg $p rating {}] [dg $p withdrawn 0]]
	}
	foreach p [dg $state pairings {}] {
		set white [expr {[dict get $p white] eq "" ? "BYE" : [dict get [::td::model::Player $state [dict get $p white]] name]}]
		set black [expr {[dict get $p black] eq "" ? "BYE" : [dict get [::td::model::Player $state [dict get $p black]] name]}]
		$Notebook.pairings.tree insert {} end -id [dict get $p id] -values [list [dict get $p id] [dict get $p round] $white $black [dg $p status pending] [dg $p result *]]
		$Notebook.results.tree insert {} end -id [dict get $p id] -values [list [dict get $p id] [dict get $p round] $white $black [dg $p result *] [dg $p category played]]
	}
	foreach row [::td::score::Compute $state] {
		set values [list [dict get $row rank] [dict get $row name] [dict get $row score text]]
		foreach key {directEncounter sonnebornBerger koya gamesWon gamesWonWithBlack progressive aro tpr} {
			set value [dg [dg $row tiebreaks {}] $key {}]
			lappend values [expr {$value eq "" ? "" : [dict get $value text]}]
		}
		$Notebook.standings.tree insert {} end -id [dict get $row id] -values $values
	}
}

# vi:set ts=3 sw=3:

proc ::td::ui::RegisterFide {} { variable Fields; Mutate td.register_fide [dict create fide_id $Fields(fide_id)] }
