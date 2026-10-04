# ======================================================================
# Plain-Language Search: a request in words becomes an editable search
# (PLAIN_LANGUAGE_SEARCH.md). ::ai::search interprets the request into the
# fixed search_games fields and a pattern id; the form shows every field
# with where it came from; Search validates the fields and filters the
# main game list. No model writes query text or CQL here. A positional
# request no library pattern covers is shown as words; Find Positions
# hands it, with the fields, to the assistant's position finder.
# ======================================================================

::util::source database-search-nl

namespace eval application {
namespace eval database {
namespace eval mc {
set PlainSearch					"Plain-Language Search"
set PlainSearchTitle				"Plain-Language Search in '%s'"
set PlainSearchAsk				"Ask"
set PlainSearchUnderstand		"Understand"
set PlainSearchExample			"e.g. \"Carlsen's losses as Black in B90-B99 since 2015\" or \"smothered mates in games rated 2500+\""
set PlainSearchUnderstood		"Understood as (edit anything before searching):"
set PlainSearchThinking			"Reading the request..."
set PlainSearchIndexing			"Searching... The first pattern search in a big database indexes all patterns (a few minutes); later ones take a second."
set PlainSearchNothing			"Nothing was understood; fill in the fields yourself."
set PlainSearchPlayer			"Player"
set PlainSearchColor				"Colour"
set PlainSearchResult			"Result"
set PlainSearchOpponent			"Opponent"
set PlainSearchEco				"ECO"
set PlainSearchFrom				"From"
set PlainSearchTo					"To"
set PlainSearchEvent				"Event"
set PlainSearchMinElo			"Minimum Elo"
set PlainSearchPattern			"Pattern"
set PlainSearchRun				"Search"
set PlainSearchShowAll			"Show All"
set PlainSearchFound				"%s games: %s"
set PlainSearchPatternSlow		"A pattern reads the moves of every candidate game; this can take a while."
set PlainSearchPosition			"Position"
set PlainSearchFindPositions	"Find Positions..."
set PlainSearchPositionNote	"No library pattern covers the position asked for: Find Positions lets the assistant write the search and show sample positions first."
} ;# namespace mc

variable PlainSearchData
variable PlainSearchFields {player color result opponent eco from to event min_elo pattern}
variable PlainSearchSerial 0

} ;# namespace database
} ;# namespace application


proc ::application::database::PlainDialogName {file variant} {
	return .plainsearch[string map {. _ / _ " " _ : _} "$file$variant"]
}


proc ::application::database::PlainPatternLabels {} {
	set labels [list ""]
	foreach id [::ai::search::patternIds] { lappend labels [dict get [::ai::search::pattern $id] label] }
	return $labels
}


proc ::application::database::PlainPatternId {label} {
	foreach id [::ai::search::patternIds] {
		if {[dict get [::ai::search::pattern $id] label] eq $label} { return $id }
	}
	return ""
}


proc ::application::database::OpenPlainSearch {parent file variant} {
	variable PlainSearchData
	variable PlainSearchFields
	variable mc
	variable PlainSearchSerial

	set dlg [PlainDialogName $file $variant]
	if {[winfo exists $dlg]} {
		raise $dlg
		focus $dlg.ask.entry
		return $dlg
	}

	set PlainSearchData($dlg,file) $file
	set PlainSearchData($dlg,epoch) [incr PlainSearchSerial]
	set PlainSearchData($dlg,job) {}
	set PlainSearchData($dlg,variant) $variant
	set PlainSearchData($dlg,request) ""
	set PlainSearchData($dlg,status) $mc::PlainSearchExample
	set PlainSearchData($dlg,positional) ""
	foreach key $PlainSearchFields {
		set PlainSearchData($dlg,$key) ""
		set PlainSearchData($dlg,$key,source) ""
	}

	tk::toplevel $dlg -class Scidb
	wm title $dlg [format $mc::PlainSearchTitle [::util::databaseName $file no]]

	set var [namespace current]::PlainSearchData

	ttk::frame $dlg.ask
	ttk::label $dlg.ask.label -text $mc::PlainSearchAsk
	ttk::entry $dlg.ask.entry -textvariable ${var}($dlg,request) -width 64
	ttk::button $dlg.ask.go -text $mc::PlainSearchUnderstand \
		-command [namespace code [list PlainUnderstand $dlg]]
	bind $dlg.ask.entry <Return> [namespace code [list PlainUnderstand $dlg]]
	grid $dlg.ask.label -row 0 -column 0 -sticky w -padx {0 6}
	grid $dlg.ask.entry -row 0 -column 1 -sticky ew
	grid $dlg.ask.go -row 0 -column 2 -sticky e -padx {6 0}
	grid columnconfigure $dlg.ask 1 -weight 1

	ttk::labelframe $dlg.form -text $mc::PlainSearchUnderstood
	set row 0
	foreach {key label widget values} [list \
		player   $mc::PlainSearchPlayer   entry {} \
		color    $mc::PlainSearchColor    combo {"" white black} \
		result   $mc::PlainSearchResult   combo {"" win draw loss 1-0 0-1 1/2-1/2} \
		opponent $mc::PlainSearchOpponent entry {} \
		eco      $mc::PlainSearchEco      entry {} \
		from     $mc::PlainSearchFrom     entry {} \
		to       $mc::PlainSearchTo       entry {} \
		event    $mc::PlainSearchEvent    entry {} \
		min_elo  $mc::PlainSearchMinElo   entry {} \
		pattern  $mc::PlainSearchPattern  combo [PlainPatternLabels] \
	] {
		ttk::label $dlg.form.l$key -text $label
		if {$widget eq "entry"} {
			ttk::entry $dlg.form.$key -textvariable ${var}($dlg,$key) -width 28
		} else {
			ttk::combobox $dlg.form.$key -textvariable ${var}($dlg,$key) \
				-values $values -state readonly -width 26
		}
		ttk::label $dlg.form.s$key -textvariable ${var}($dlg,$key,source) -foreground gray40
		grid $dlg.form.l$key -row $row -column 0 -sticky w -padx 4 -pady 1
		grid $dlg.form.$key -row $row -column 1 -sticky ew -pady 1
		grid $dlg.form.s$key -row $row -column 2 -sticky w -padx 6
		incr row
	}
	ttk::label $dlg.form.lpositional -text $mc::PlainSearchPosition
	ttk::entry $dlg.form.positional -textvariable ${var}($dlg,positional) -width 28
	ttk::button $dlg.form.findpositions -text $mc::PlainSearchFindPositions \
		-command [namespace code [list PlainFindPositions $dlg]]
	grid $dlg.form.lpositional -row $row -column 0 -sticky w -padx 4 -pady 1
	grid $dlg.form.positional -row $row -column 1 -sticky ew -pady 1
	grid $dlg.form.findpositions -row $row -column 2 -sticky w -padx 6
	grid columnconfigure $dlg.form 1 -weight 1

	ttk::frame $dlg.buttons
	ttk::button $dlg.buttons.run -text $mc::PlainSearchRun \
		-command [namespace code [list PlainRun $dlg]]
	ttk::button $dlg.buttons.all -text $mc::PlainSearchShowAll \
		-command [namespace code [list PlainShowAll $dlg]]
	ttk::button $dlg.buttons.close -text $mc::Close -command [list destroy $dlg]
	pack $dlg.buttons.close $dlg.buttons.all $dlg.buttons.run -side right -padx 3

	ttk::label $dlg.status -textvariable ${var}($dlg,status) -wraplength 560 -justify left

	pack $dlg.ask -side top -fill x -padx 8 -pady {8 4}
	pack $dlg.form -side top -fill x -padx 8 -pady 4
	pack $dlg.status -side top -fill x -padx 8 -pady 4
	pack $dlg.buttons -side top -fill x -padx 8 -pady {4 8}

	bind $dlg <Destroy> [list if {"%W" eq $dlg} [namespace code [list PlainForget $dlg]]]
	focus $dlg.ask.entry
	return $dlg
}


proc ::application::database::PlainForget {dlg} {
	variable PlainSearchData
	if {[info exists PlainSearchData($dlg,job)] && $PlainSearchData($dlg,job) ne ""} {
		::scidb::cql6::cancel $PlainSearchData($dlg,job)
	}
	array unset PlainSearchData $dlg,*
}


proc ::application::database::PlainUnderstand {dlg} {
	variable PlainSearchData
	variable mc

	set request [string trim $PlainSearchData($dlg,request)]
	if {$request eq ""} { return }
	set PlainSearchData($dlg,status) $mc::PlainSearchThinking
	::ai::search::interpret $request [namespace code [list PlainUnderstood $dlg]]
}


# Fill the form from an interpretation of ::ai::search::interpret.
proc ::application::database::PlainUnderstood {dlg interpretation} {
	variable PlainSearchData
	variable PlainSearchFields
	variable mc

	if {![info exists PlainSearchData($dlg,file)]} { return } ;# closed meanwhile

	set sources [dict get $interpretation sources]
	foreach key $PlainSearchFields {
		if {$key eq "pattern"} {
			set id [dict get $interpretation pattern]
			set value [expr {$id eq "" ? "" : [dict get [::ai::search::pattern $id] label]}]
		} else {
			set value [dict get $interpretation criteria $key]
		}
		set PlainSearchData($dlg,$key) $value
		set PlainSearchData($dlg,$key,source) \
			[expr {[dict exists $sources $key] ? "([dict get $sources $key])" : ""}]
	}
	set positional [expr {[dict exists $interpretation positional] ? [dict get $interpretation positional] : ""}]
	set PlainSearchData($dlg,positional) $positional
	set PlainSearchData($dlg,status) [expr {[dict size $sources]
		? [expr {[dict get $interpretation pattern] ne "" ? $mc::PlainSearchPatternSlow
			: $positional ne "" ? $mc::PlainSearchPositionNote : ""}]
		: $mc::PlainSearchNothing}]
}


# Hand the position asked for, with the fields, to the assistant's
# position finder, in the assistant pane: it drafts the CQL, shows sample
# positions to confirm, then fills the game list.
proc ::application::database::PlainFindPositions {dlg} {
	variable PlainSearchData

	set positional [string trim $PlainSearchData($dlg,positional)]
	if {$positional eq ""} { return }
	set fields {}
	foreach {key value} [PlainArguments $dlg] {
		if {$key ne "pattern"} { lappend fields "$key $value" }
	}
	set request "Find positions in this database: $positional."
	if {[llength $fields]} {
		append request " Search only the games with these fields: [join $fields {, }]."
	}
	if {![::application::ai::cloudReady $dlg]} { return }
	::application::database::switchToBase $PlainSearchData($dlg,file)
	::application::assistant::show
	::application::assistant::ask $request
}


# The form as search_games arguments.
proc ::application::database::PlainArguments {dlg} {
	variable PlainSearchData
	variable PlainSearchFields

	set args {}
	foreach key $PlainSearchFields {
		set value [string trim $PlainSearchData($dlg,$key)]
		if {$key eq "pattern"} { set value [PlainPatternId $value] }
		if {$value ne ""} { dict set args $key $value }
	}
	return $args
}


proc ::application::database::PlainRun {dlg} {
	variable PlainSearchData
	variable mc

	set file $PlainSearchData($dlg,file)
	set variant $PlainSearchData($dlg,variant)

	if {[catch {
		set criteria [dict get [::application::assistant::CheckArgs search_games [PlainArguments $dlg]] criteria]
		lassign [::application::assistant::BuildQuery $file $variant $criteria] query summary
	} err]} {
		return [::dialog::error -parent $dlg -message $err]
	}

	set rc [catch {
		set epoch $PlainSearchData($dlg,epoch)
		set PlainSearchData($dlg,job) [::application::assistant::SearchView $file $variant 0 $criteria \
			[namespace code [list PlainSearchFinished $dlg $epoch]] [namespace code [list PlainSearchAlive $dlg $epoch]]]
	} err options]
	if {$rc} {
		return [::dialog::error -parent $dlg -message $err]
	}

	$dlg.buttons.run configure -state disabled
	$dlg.buttons.all configure -state disabled
	set PlainSearchData($dlg,status) "Searching..."
	if {[llength [info commands ::ai::patternIndex::building]] && [::ai::patternIndex::building $file]} {
		set PlainSearchData($dlg,status) $mc::PlainSearchIndexing
	}
}

proc ::application::database::PlainSearchAlive {dlg epoch} {
	variable PlainSearchData
	expr {[info exists PlainSearchData($dlg,epoch)] && $PlainSearchData($dlg,epoch) == $epoch}
}
proc ::application::database::PlainSearchFinished {dlg epoch result} {
	variable PlainSearchData
	variable mc
	if {![PlainSearchAlive $dlg $epoch]} {return}
	set PlainSearchData($dlg,job) {}
	$dlg.buttons.run configure -state normal
	$dlg.buttons.all configure -state normal
	if {![dict get $result ok]} {set PlainSearchData($dlg,status) [dict get $result error];return}
	set PlainSearchData($dlg,status) [format $mc::PlainSearchFound \
		[::locale::formatNumber [dict get $result count]] [dict get $result summary]]
	catch {::application::switchTab database}
}


proc ::application::database::PlainShowAll {dlg} {
	variable PlainSearchData

	set file $PlainSearchData($dlg,file)
	set variant $PlainSearchData($dlg,variant)
	::scidb::view::search $file $variant 0 reset none
	set PlainSearchData($dlg,status) \
		[format $::application::database::mc::PlainSearchFound \
			[::locale::formatNumber [::scidb::view::count games $file $variant 0]] "all games"]
}

# vi:set ts=3 sw=3:
