# ======================================================================
# Author : $Author$
# Version: $Revision: 1519 $
# Date   : $Date: 2018-09-11 07:41:52 -0400 (Tue, 11 Sep 2018) $
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
# Copyright: (C) 2011-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source crosstable-dialog

namespace eval crosstable {
namespace eval mc {

set TournamentTable			"Tournament Table"
set AverageRating				"Average Rating"
set Category					"Category"
set Games						"games"
set Game							"game"

set ScoringSystem				"Scoring System"
set Tiebreak					"Tie-break Rule"
set Settings					"Settings"
set RevertToStart				"Revert to initial values"
set UpdateDisplay				"Update display"
set SaveAsHTML					"Save as HTML file"

set Traditional				"Traditional"
set Bilbao						"Bilbao"

set None							"None"
set Buchholz					"Buchholz"
set MedianBuchholz			"Median-Buchholz"
set ModifiedMedianBuchholz "Mod. Median Buchholz"
set RefinedBuchholz			"Refined-Buchholz"
set SonnebornBerger			"Sonneborn-Berger"
set Progressive				"Progressive Score"
set KoyaSystem					"Koya-System"
set GamesWon					"Number of Games Won"
set GamesWonWithBlack		"Number of Games Won with Black"
set ParticularResult			"Particular Result"
set TraditionalScoring		"Traditional Scoring"

set Crosstable					"Crosstable"
set Scheveningen				"Scheveningen"
set Swiss						"Swiss System"
set Match						"Match"
set Knockout					"Knockout"
set RankingList				"Ranking List"
set Simultan					"Simultaneous"

set Order						"Order"
set Type							"Table Type"
set Score						"Score"
set Alphabetical				"Alphabetical"
set Rating						"Rating"
set Federation					"Federation"

set NarrateEvent				"Narrate the Standings (AI)"
set Debugging					"Debugging"
set Display						"Display"
set Style						"Style"
set Spacing						"Spacing"
set Padding						"Padding"
set ShowLog						"Show Log"
set ShowHtml					"Show HTML"
set ShowRating					"Show Rating"
set ShowPerformance			"Show Performance"
set ShowWinDrawLoss			"Show Win/Draw/Loss"
set ShowTiebreak				"Show Tiebreak"
set ShowOpponent				"Show Opponent (as Tooltip)"
set KnockoutStyle				"Knockout Table Style"
set Pyramid						"Pyramid"
set Triangle					"Triangle"

set CrosstableLimit			"The crosstable limit of %d players will be exceeded."
set CrosstableLimitDetail	"'%s' is choosing another table mode."
set CannotOverwriteFile		"Cannot overwrite file '%s': permission denied."
set CannotCreateFile			"Cannot create file '%s': permission denied."
set BaseIsClosed				"Database has been closed."

} ;# namespace mc

namespace import ::tcl::mathfunc::max

array set Nodes {}

array set Colors {
	background	crosstable,background
	highlighted	crosstable,highlighted
	mark			crosstable,mark
}

array set Scripts {
	crosstable		"crosstable.eXt"
	scheveningen	"scheveningen.eXt"
	swiss				"swiss.eXt"
	match				"match.eXt"
	knockout			"knockout.eXt"
	rankingList		"rankingList.eXt"
	simultan			"simultan.eXt"
}

array set ListEntries {
	type		{ crosstable scheveningen swiss match knockout rankingList simultan }
	scoring	{ traditional bilbao }
	tiebreak	{ none sonnebornBerger buchholz medianBuchholz modifiedMedianBuchholz refinedBuchholz
					progressive koyaSystem gamesWon gamesWonWithBlack particularResult traditionalScoring }
	order		{ score alphabetical rating federation }
}

variable RecentlyUsedHistory {}
variable MostRecentHistory {}

array set RecentlyUsedTiebreaks {
	crosstable		sonnebornBerger
	swiss				buchholz
	scheveningen	{}
	match				{}
	knockout			{}
	rankingList		{}
	simultan			{}
}

array set RecentlyUsedScoring {
	crosstable		traditional
	swiss				traditional
	scheveningen	traditional
	match				traditional
	knockout			traditional
	rankingList		traditional
	simultan			traditional
}

array set Defaults {
	scoring				traditional
	tiebreaks			{}
	bestMode				rankingList
	order					score
	browserId			{}
	overviewId			{}
	crosstableLimit	60
}

array set Options {
	debug:log			0
	debug:html			0
	fmt:padding			3
	fmt:spacing			1
	fmt:pyramid			0
	show:rating			1
	show:winDrawLoss	0
	show:performance	1
	show:tiebreak		1
	show:opponent		1
}

array set List {}
array set Key {}
array set Locked {}

variable Geometry "1024x768"
variable Counter 0
variable Reuse ""


proc open {parent base variant index view source} {
	variable ListEntries
	variable Options
	variable Defaults
	variable Geometry
	variable Counter
	variable Reuse
	variable Key

	if {$source eq "game"} {
		set number [::scidb::db::get gameNumber $base $variant $index $view]
		set info [::scidb::db::fetch eventInfo $number $base $variant -card]
	} else { ;# $source eq "event"
		set info [::scidb::db::get eventInfo $index $view $base $variant -card]
		set number [::scidb::db::get eventIndex $index $view $base $variant]
	}

	lassign $info title type date mode timeMode country site
	set key "key:$base:$variant:$site:$title:$type:$date:$mode:$timeMode"

	if {[info exists Key($key)]} {
		set dlg $Key($key)
		variable ${dlg}::Vars
		if {$Vars(open)} {
			::widget::dialogRaise $dlg
		} else {
			set Vars(open) 1
			::scidb::crosstable::release $Vars(tableId) $Vars(viewId)
			set Vars(tableId) [::scidb::crosstable::make $base $variant $Vars(viewId)]
			UpdateContent $dlg 1
		}
		return
	}

	if {[string length $Reuse]} {
		set dlg $Reuse
	} else {
		set dlg .application.crosstable_[incr Counter]
		set Reuse $dlg
	}

	namespace eval [namespace current]::$dlg {}
	variable ${dlg}::Vars
	array set Vars [array get Defaults]

	set top $dlg.top
	set canv $top.canv
	set html $canv.html

	if {[info exists Vars(tableId)]} {
		::scidb::crosstable::release $Vars(tableId) $Vars(viewId)
		if {$Vars(open)} {
			::scidb::view::close $Vars(base) $Vars(variant) $Vars(viewId)
		}
		array unset Vars viewId
	}

	set Vars(open) 1
	set Vars(html) $html
	set Vars(base) $base
	set Vars(variant) $variant
	set Vars(view) $view
	set Vars(index) $index
	set Vars(info) $info
	set Vars(key) $key
	set Vars(warning) {}
	set Vars(lastMode) ""
	set Vars(prevMode) ""
	set Vars(prevTiebreaks) ""
	set Vars(prevScoring) ""
	set Vars(tooltip) ""

	if {![info exists Vars(viewId)]} {
		set Vars(viewId) [::scidb::view::new $base $variant unused unused unused unused unused slave]
	}
	if {$source eq "game"} { set search gameevent } else { set search event }
	::scidb::view::search $base $variant $Vars(viewId) null none [list $search $number]

	if {[winfo exists $dlg]} {
		::widget::dialogRaise $dlg
		set Vars(tableId) [::scidb::crosstable::make $base $variant $Vars(viewId)]
		::scidb::view::unsubscribe {*}$Vars(subscribe)
		set Vars(subscribe) [list [namespace current]::Close $base $variant $dlg]
		::scidb::view::subscribe {*}$Vars(subscribe)
		ConfigureToolbar $dlg normal
		::toolbar::childconfigure $Vars(toolbar:refresh) -state disabled
		::toolbar::childconfigure $Vars(toolbar:reset) -state disabled
		UpdateContent $dlg 1
		return
	}

	set Vars(options) {}
	set Vars(subscribe) [list [namespace current]::Close $base $variant $dlg]
	::scidb::view::subscribe {*}$Vars(subscribe)

	tk::toplevel $dlg -class Scidb
	bind $dlg <Destroy> [namespace code [list Destroy $dlg %W 1]]
	wm withdraw $dlg

	ttk::frame $top
	ttk::frame $canv
	::font::html::setupFonts crosstable
	set css [DefaultCSS]
	set dir [file join $::scidb::dir::share scripts]
	::html $html \
		-imagecmd [namespace code GetImage] \
		-delay 10 \
		-center yes \
		-fittowidth no \
		-css $css \
		-importdir $dir \
		-fontsize [::font::html::fontSize crosstable] \
		;
	$html handler node td [namespace current]::NodeHandler
	$html handler node span [namespace current]::NodeHandler
	bind [winfo parent [$html drawable]] <ButtonPress-3> [namespace code [list PopupMenu $dlg]]

	if {![info exists List(order)]} { MakeLists }
	variable List

	::toolbar::setup $dlg -id crosstable
	set tb [::toolbar::toolbar $dlg \
		-id crosstable-settings \
		-allow {top bottom} \
		-titlevar [namespace current]::mc::Settings \
		-padx 4 \
		-pady 2 \
	]
	set Vars(widget:toolbar) $tb
	bind $tb <<ToolbarShow>> [namespace code [list SetupToolbar $dlg]]

	set f1 [::toolbar::add $tb frame]
	set f2 [::toolbar::add $tb frame]
	set f3 [::toolbar::add $tb frame]

	tk::label $f1.label_type -textvar [namespace current]::mc::Type
	::ttk::combobox $f1.choose_type \
		-takefocus 0 \
		-exportselection 0 \
		-state readonly  \
		-textvar [namespace current]::${dlg}::Vars(value:type) \
		-width 16 \
		;
	set Vars(widget:type) $f1.choose_type
	set Vars(value:type) [lindex $List(type) 0]
	lappend Vars(options) $Vars(widget:type)

	tk::label $f1.label_order -textvar [namespace current]::mc::Order
	::ttk::combobox $f1.choose_order \
		-takefocus 0 \
		-exportselection 0 \
		-state readonly  \
		-textvar [namespace current]::${dlg}::Vars(value:order) \
		-width 12 \
		;
	set Vars(widget:order) $f1.choose_order
	set Vars(value:order) [lindex $List(order) 0]
	lappend Vars(options) $Vars(widget:order)

	tk::label $f1.scoring_label -textvar [namespace current]::mc::ScoringSystem
	set Vars(widget:scoring) $f1.choose_scoring
	::ttk::combobox $Vars(widget:scoring) \
		-takefocus 0 \
		-exportselection 0 \
		-state readonly  \
		-textvar [namespace current]::${dlg}::Vars(value:scoring) \
		-width 12 \
		;
	set Vars(value:scoring) [lindex $List(scoring) 0]
	lappend Vars(options) $Vars(widget:scoring)
	
	::toolbar::add $tb separator
	set Vars(toolbar:refresh) [::toolbar::add $tb button \
		-image [list [::icon::makeStateSpecificIcons $icon::32x32::go]] \
		-command [namespace code [list Refresh $dlg]] \
		-tooltipvar [namespace current]::mc::UpdateDisplay \
		-padx 4 \
	]
	set Vars(toolbar:reset) [::toolbar::add $tb button \
		-image [list [::icon::makeStateSpecificIcons $icon::32x32::reset]] \
		-command [namespace code [list Reset $dlg]] \
		-tooltipvar [namespace current]::mc::RevertToStart \
		-padx 4 \
	]

	grid $f1.label_type     -row 1 -column 1 -sticky w
	grid $f1.choose_type    -row 1 -column 3 -sticky ew
	grid $f1.label_order    -row 3 -column 1 -sticky w
	grid $f1.choose_order   -row 3 -column 3 -sticky ew
	grid $f1.scoring_label  -row 5 -column 1 -sticky w
	grid $f1.choose_scoring -row 5 -column 3 -sticky ew

	foreach i {1 2 3 4 5 6} {
		set f [set f[expr {($i - 1)/3 + 2}]]
		set r [expr {($i*2 - 1)%6}]
		set Vars(label:tiebreak$i) {}
		tk::label $f.label$i -textvar [namespace current]::${dlg}::Vars(label:tiebreak$i)
		set Vars(widget:tiebreak$i) $f.choose$i
		set Vars(value:tiebreak$i) [lindex $List(tiebreak) 0]
		lappend Vars(options) $Vars(widget:tiebreak$i)
		::ttk::combobox $Vars(widget:tiebreak$i) \
			-takefocus 0 \
			-exportselection 0 \
			-state readonly  \
			-textvar [namespace current]::${dlg}::Vars(value:tiebreak$i) \
			-width 23 \
			-height [llength $ListEntries(tiebreak)] \
			;
		grid $f.label$i  -row $r -column 1 -sticky w
		grid $f.choose$i -row $r -column 3 -sticky ew
	}

	foreach i {1 2 3} {
		set f [set f$i]
		grid columnconfigure $f 2 -minsize $::theme::padding
		grid rowconfigure $f {0 2 4 6} -minsize 3
	}

	grid columnconfigure $f2 0 -minsize $::theme::padX
	grid columnconfigure $f3 0 -minsize $::theme::padX
	grid columnconfigure $f3 4 -minsize $::theme::padding

	set traceCmd [list \
		variable [namespace current]::${dlg}::Vars(value:type) \
		write [namespace code [list SetupToolbar $dlg]]]
	trace add {*}$traceCmd
	bind $top <Destroy> [list trace remove {*}$traceCmd]

	InsertEntries $dlg

	$html onmouseover		[namespace code [list MouseEnter $dlg]]
	$html onmouseout		[namespace code [list MouseLeave $dlg]]
	$html onmousedown1	[namespace code [list Mouse1Down $dlg]]
	$html onmousedown2	[namespace code [list Mouse2Down $dlg]]
	$html onmouseup2		[namespace code [list Mouse2Up   $dlg]]
	$html onmousedown3	[namespace code [list Mouse3Down $dlg]]

	pack $top -expand yes -fill both

	grid $canv -row 1 -column 1 -sticky nsew
	grid columnconfigure $top 1 -weight 1
	grid rowconfigure $top 1 -weight 1

	grid $html -row 0 -column 0 -sticky nsew
	grid columnconfigure $canv 0 -weight 1
	grid rowconfigure $canv 0 -weight 1

	::font::html::addChangeFontSizeBindings crosstable $dlg \
		[list [namespace current]::ChangeFontSize $dlg]
	bind $dlg <<LanguageChanged>> [namespace code [list LanguageChanged $dlg %W]]
	bind $dlg <<FontSizeChanged>> [namespace code [list FontSizeChanged %W $dlg]]

	if {$source eq "event"} {
		::widget::dialogButtons $dlg {close previous next}
		$dlg.previous configure -command [namespace code [list NextEvent $dlg -1]]
		$dlg.next configure -command [namespace code [list NextEvent $dlg +1]]
	} else {
		::widget::dialogButtons $dlg close
	}
	if {[winfo exists $dlg.close]} {
		$dlg.close configure -command [list destroy $dlg]
	}

	::update
	set Vars(tableId) [::scidb::crosstable::make $base $variant $Vars(viewId)]
	UpdateContent $dlg 1

	lassign {0 0} w h
	scan $Geometry "%dx%d" w h
	set w [max 1024 $w]
	set h [max 768 $h]
	bind $dlg <Configure> [namespace code [list RecordGeometry $dlg]]

	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm geometry $dlg "${w}x${h}"
	wm resizable $dlg yes yes
	wm deiconify $dlg

	update idletasks
	wm minsize $dlg [expr {max(840, [winfo width [::toolbar::realpath $tb]] + 4)}] 400
}


proc ConfigureToolbar {dlg state} {
	variable ${dlg}::Vars

	foreach w $Vars(options) {
		$w configure -state $state
	}
}


proc Close {dlg base variant view} {
	variable ${dlg}::Vars

	if {$Vars(viewId) == $view} {
		set [namespace current]::${dlg}::Vars(open) 0
		set Vars(index) -1
		ConfigureButtons $dlg

		::toolbar::childconfigure $Vars(toolbar:refresh) -state disabled
		::toolbar::childconfigure $Vars(toolbar:reset) -state disabled
	}

	if {$view == 0} {
		ConfigureToolbar $dlg disabled
	}
}


proc RecordGeometry {dlg} {
	variable Geometry

	set g [wm geometry $dlg]
	set n [string first "+" $g]
	if {$n == -1} { set n [string first "-" $g] }
	if {$n >= 0} { set Geometry [string range $g 0 [expr {$n - 1}]] }
}


proc NextEvent {dlg step} {
	variable ${dlg}::Vars

	::scidb::crosstable::release $Vars(tableId) $Vars(viewId)
	incr Vars(index) $step
	set view $Vars(view)
	set base $Vars(base)
	set variant  $Vars(variant)
	set index $Vars(index)
	set number [::scidb::db::get eventIndex $index $view $base $variant]
	::scidb::view::search $base $variant $Vars(viewId) null none [list event $number]
	set Vars(info) [::scidb::db::get eventInfo $index $Vars(viewId) $base $variant -card]
	set Vars(tableId) [::scidb::crosstable::make $base $variant $Vars(viewId)]
	set Vars(warning) 0
	set Vars(lastMode) ""
	set Vars(prevMode) ""
	set Vars(prevTiebreaks) ""
	set Vars(prevScoring) ""
	UpdateContent $dlg 1
}


proc MakeLists {} {
	variable ListEntries
	variable List

	foreach attr {tiebreak scoring order type} {
		set List($attr) {}
		foreach entry $ListEntries($attr) { lappend List($attr) [set mc::[string toupper $entry 0 0]] }
	}
}


proc InsertEntries {dlg} {
	variable List
	variable ${dlg}::Vars

	set parent $Vars(widget:tiebreak1)
	set toolbar $Vars(widget:toolbar)
	foreach i {1 2 3 4 5 6} {
		set n [lsearch -exact $List(tiebreak) $Vars(value:tiebreak$i)]
		set Vars(label:tiebreak$i) "$i. $mc::Tiebreak"
		$Vars(widget:tiebreak$i) configure -values $List(tiebreak)
		set clone [::toolbar::lookupClone $toolbar $Vars(widget:tiebreak$i)]
		if {[llength $clone]} { $clone configure -values $List(tiebreak) }
		if {$n >= 0} { set Vars(value:tiebreak$i) [lindex $List(tiebreak) $n] }
	}

	set n [lsearch -exact $List(scoring) $Vars(value:scoring)]
	$Vars(widget:scoring) configure -values $List(scoring)
	set clone [::toolbar::lookupClone $toolbar $Vars(widget:scoring)]
	if {[llength $clone]} { $clone configure -values $List(scoring) }
	if {$n >= 0} { set Vars(value:scoring) [lindex $List(scoring) $n] }

	set n [lsearch -exact $List(order) $Vars(value:order)]
	$Vars(widget:order) configure -values $List(order)
	set clone [::toolbar::lookupClone $toolbar $Vars(widget:order)]
	if {[llength $clone]} { $clone configure -values $List(order) }
	if {$n >= 0} { set Vars(value:order) [lindex $List(order) $n] }

	set n [lsearch -exact $List(type) $Vars(value:type)]
	$Vars(widget:type) configure -values $List(type)
	set clone [::toolbar::lookupClone $toolbar $Vars(widget:type)]
	if {[llength $clone]} { $clone configure -values $List(type) }
	if {$n >= 0} { set Vars(value:type) [lindex $List(type) $n] }
}


proc LanguageChanged {dlg w} {
	if {$dlg ne $w} { return }

	SetTitle $dlg
	MakeLists
	InsertEntries $dlg
	UpdateContent $dlg
}


proc SetTitle {dlg} {
	variable ${dlg}::Vars
	wm title $dlg "$::scidb::app: $mc::TournamentTable$Vars(eventName)"
}


proc GetImage {code} {
	return [list $::country::icon::flag($code) [namespace code DoNothing]]
}


proc DoNothing {args} {
	# nothing to do
}


proc Reset {dlg} {
	variable ${dlg}::Vars

	foreach attr [array names Vars reset:*:$dlg] {
		set Vars([string range $attr 6 end]) $Vars($attr)
	}
	Refresh $dlg
}


proc Refresh {dlg} {
	variable ${dlg}::Vars
	variable List
	variable ListEntries

	set Vars(prevMode) $Vars(bestMode)
	set Vars(prevTiebreaks) $Vars(tiebreaks)
	set Vars(prevScoring) $Vars(scoring)
	set Vars(order) [lindex $ListEntries(order) [lsearch -exact $List(order) $Vars(value:order)]]
	set Vars(bestMode) [lindex $ListEntries(type) [lsearch -exact $List(type) $Vars(value:type)]]
	set Vars(scoring) [lindex $ListEntries(scoring) [lsearch -exact $List(scoring) $Vars(value:scoring)]]
	set Vars(tiebreaks) {}
	for {set i 1} {$i <= 6} {incr i} {
		set n [lsearch -exact $List(tiebreak) $Vars(value:tiebreak$i)]
		if {$n > 0} { lappend Vars(tiebreaks) [lindex $ListEntries(tiebreak) $n] }
	}

	UpdateContent $dlg
	UpdateHistory $dlg
}


proc UpdateHistory {dlg} {
	variable RecentlyUsedTiebreaks
	variable RecentlyUsedScoring
	variable RecentlyUsedHistory
	variable MostRecentHistory
	variable ${dlg}::Vars

	set RecentlyUsedTiebreaks($Vars(bestMode)) $Vars(tiebreaks)
	set RecentlyUsedScoring($Vars(bestMode)) $Vars(scoring)

	if {	$Vars(prevMode) ne $Vars(bestMode)
		|| $Vars(prevScoring) ne $Vars(scoring)
		|| $Vars(prevTiebreaks) ne $Vars(tiebreaks)} {
		set event $Vars(event)
		set i [lsearch -exact -index 0 $RecentlyUsedHistory $event]

		if {$i >= 0} {
			set RecentlyUsedHistory [lreplace $RecentlyUsedHistory $i $i]
		} elseif {[llength $RecentlyUsedHistory] == 30} {
			set lastEntry [lindex $RecentlyUsedHistory end]
			set RecentlyUsedHistory [lreplace $RecentlyUsedHistory end end]
			# keep the evicted entry as the newest of the long-term history
			set hist $MostRecentHistory
			set k [lsearch -exact -index 0 $hist [lindex $lastEntry 0]]
			if {$k >= 0} { set hist [lreplace $hist $k $k] }
			set hist [linsert $hist 0 $lastEntry]
			if {[llength $hist] > 20} { set hist [lrange $hist 0 19] }
			set MostRecentHistory $hist
		}

		set entry [list $Vars(bestMode) $Vars(tiebreaks) $Vars(scoring)]
		set RecentlyUsedHistory [linsert $RecentlyUsedHistory 0 [list $event $entry]]
	}
}


proc UpdateContent {dlg {setup 0}} {
	variable ${dlg}::Vars
	variable List
	variable Defaults
	variable Options
	variable Scripts
	variable Highlighted
	variable Marks
	variable Nodes
	variable ListEntries

	set w $Vars(html)
	set base $Vars(base)
	set variant $Vars(variant)
	set index $Vars(index)
	set viewId $Vars(viewId)

	if {$setup} {
		variable RecentlyUsedHistory
		variable RecentlyUsedScoring
		variable RecentlyUsedTiebreaks
		variable MostRecentHistory

		set info $Vars(info)
		set name [lindex $info [::eventtable::columnIndex event]]
		set eventType [lindex $info [::eventtable::columnIndex eventType]]
		set eventDate [lindex $info [::eventtable::columnIndex eventDate]]
		set eventMode [lindex $info [::eventtable::columnIndex eventMode]]
		set timeMode [lindex $info [::eventtable::columnIndex timeMode]]
		set eventCountry [lindex $info [::eventtable::columnIndex eventCountry]]
		set site [lindex $info [::eventtable::columnIndex site]]
		if {[string length $name] <= 1} { set Vars(eventName) "" } else { set Vars(eventName) " $name" }
		set Vars(event) [list $name $eventDate $site $eventCountry $eventType $eventMode $timeMode]
		set i [lsearch -exact -index 0 $RecentlyUsedHistory $Vars(event)]

		if {$i >= 0} {
			lassign [lindex $RecentlyUsedHistory $i 1] bestMode tiebreaks scoring
		} else {
			set i [lsearch -exact -index 0 $MostRecentHistory $Vars(event)]

			if {$i >= 0} {
				lassign [lindex $MostRecentHistory $i 1] bestMode tiebreaks scoring
			} else {
				set bestMode [::scidb::crosstable::get bestMode $Vars(tableId) $viewId]
				set bestMode [string tolower $bestMode 0 0]
				set tiebreaks $RecentlyUsedTiebreaks($bestMode)
				set scoring $RecentlyUsedScoring($bestMode)
			}
		}

		set i 0
		foreach tb $tiebreaks {
			set Vars(value:tiebreak[incr i]) \
				[lindex $List(tiebreak) [lsearch -exact $ListEntries(tiebreak) $tb]]
		}
		for {incr i} {$i <= 6} {incr i} {
			set Vars(value:tiebreak$i) [lindex $List(tiebreak) 0]
		}
		set Vars(value:scoring) [lindex $List(scoring) [lsearch -exact $ListEntries(scoring) $scoring]]
		set Vars(value:type) [lindex $List(type) [lsearch -exact $ListEntries(type) $bestMode]]
		set Vars(bestMode) $bestMode
		set Vars(tiebreaks) $tiebreaks
		set Vars(scoring) $scoring
		foreach attr {	tiebreaks bestMode value:type value:tiebreak1
							value:tiebreak2 value:tiebreak3 value:tiebreak4} {
			set Vars(reset:$attr) $Vars($attr)
		}
		SetTitle [winfo toplevel $w]
		ConfigureButtons $dlg
	}

	set font [$w font]
	array set metrics [font metrics $font]

	set linespace $metrics(-linespace)
	set charWidth [font measure $font "0"]
	set order $Vars(order)
	set scoring $Vars(scoring)
	set tiebreaks $Vars(tiebreaks)
	set bestMode $Vars(bestMode)
	set searchDir [file join $::scidb::dir::share scripts]
	set script $Scripts($bestMode)
	if {$Options(fmt:pyramid)} { set knockoutOrder pyramid } else { set knockoutOrder triangle }

	set preamble "
		\\def\\Lang{$::mc::langID}
		\\def\\Title{$mc::TournamentTable:$Vars(eventName)}
		\\def\\FormatDate#date{\\%date\\%#date}
		\\def\\AverageRating{$mc::AverageRating}
		\\def\\Category{$mc::Category}
		\\def\\Games{$mc::Games}
		\\def\\Game{$mc::Game}
		\\let\\DecimalPoint[::locale::decimalPoint]
		\\let\\Linespace\\$linespace
		\\let\\CharWidth\\$charWidth
		\\let\\CellSpacing\\$Options(fmt:spacing)
		\\let\\CellPadding\\$Options(fmt:padding)
		\\let\\Tracing\\$Options(debug:log)
		\\let\\UsePyramid\\$Options(fmt:pyramid)
		\\let\\ShowRating\\$Options(show:rating)
		\\let\\ShowTiebreaks\\$Options(show:tiebreak)
		\\let\\ShowPerformance\\$Options(show:performance)
		\\let\\ShowWinDrawLoss\\$Options(show:winDrawLoss)
		\\let\\ShowChange\\1
		\\let\\ShowCountry\\1
	"

	if {$Vars(bestMode) eq "crosstable"} {
		append preamble "\\let\\TableLimit\\$Defaults(crosstableLimit)"
		set id [list $base $variant $Vars(viewId)]

		if {$Vars(warning) ne $id} {
			set playerCount [::scidb::crosstable::get playerCount $Vars(tableId) $viewId]

			if {$playerCount > $Defaults(crosstableLimit)} {
				set detail ""
				if {[string length $Vars(prevMode)] == 0} {
					set cancel [::mc::stripAmpersand $::dialog::mc::Cancel]
					set detail [format $mc::CrosstableLimitDetail $cancel]
				}
				set rc [::dialog::warning \
							-parent $Vars(html) \
							-message [format $mc::CrosstableLimit $Defaults(crosstableLimit)] \
							-detail $detail \
							-title [tk appname] \
						]
				if {$rc eq "cancel"} {
					set Vars(bestMode) $Vars(lastMode)
					if {[string length $Vars(prevMode)] == 0} {
						set Vars(bestMode) [::scidb::crosstable::get bestMode $Vars(tableId) $viewId]
						set Vars(bestMode) [string tolower $Vars(bestMode) 0 0]
						if {$Vars(bestMode) eq "crosstable"} { set Vars(bestMode) rankingList }
						set Vars(value:type) \
							[lindex $List(type) [lsearch -exact $ListEntries(type) $Vars(bestMode)]]
						UpdateHistory $dlg
						after idle [namespace code [list UpdateContent $dlg]]
					}
					return
				}
				set Vars(warning) $id
			}
		}
	} else {
		set Vars(warning) {}
	}
	set Vars(lastMode) $Vars(bestMode)

	::widget::busyCursor on
	set result [::scidb::crosstable::emit \
		$Vars(tableId) $viewId $searchDir $script $bestMode $order \
		$knockoutOrder $scoring $tiebreaks $preamble \
	]
	lassign $result html Vars(output:log)

	set i [string first "%date%" $html]
	while {$i >= 0} {
		set e [expr {$i + 15}]
		set date [string range $html [expr {$i + 6}] $e]
		set html [string replace $html $i $e [::locale::formatDate $date]]
		set i [string first "%date%" $html]
	}

	array unset Highlighted
	array unset Marks
	array unset Nodes

	$w parse $html
	::widget::busyCursor of

	set Vars(output:html) $html
	set show(log) $Options(debug:log)
	set show(html) $Options(debug:html)
	if {[string length $Vars(output:log)]} { set show(log) yes }

	set w [winfo toplevel $w]
	foreach attr {log html} {
		if {$show($attr)} {
			ShowTrace $dlg $attr
		} elseif {[winfo exists $w.$attr]} {
			destroy $w.$attr
		}
	}
	set Vars(tooltip) ""
}


proc ConfigureButtons {dlg} {
	variable ${dlg}::Vars

	set dlg [winfo toplevel $Vars(html)]
	if {![winfo exists $dlg.next]} { return }

	if {$Vars(index) == -1} {
		$dlg.previous configure -state disabled
		$dlg.next configure -state disabled
	} else {
		if {$Vars(index) == 0} { set state disabled } else { set state normal }
		$dlg.previous configure -state $state
		set count [scidb::view::count events $Vars(base) $Vars(variant) $Vars(view)]
		if {$Vars(index) + 1 == $count} { set state disabled } else { set state normal }
		$dlg.next configure -state $state
	}
}


proc LookupToolbarWidget {dlg w} {
	variable ${dlg}::Vars

	set clone [::toolbar::lookupClone $Vars(widget:toolbar) $w]
	if {[llength $clone] > 0} { return $clone }
	return $w
}


proc SetupToolbar {dlg args} {
	variable ${dlg}::Vars
	variable ListEntries
	variable List

	set n [lsearch -exact $List(type) $Vars(value:type)]
	set mode [lindex $ListEntries(type) $n]

	switch $mode {
		knockout - simultan	{ set state disabled }
		default					{ set state normal }
	}
	foreach i {1 2 3 4 5 6} {
		[LookupToolbarWidget $dlg $Vars(widget:tiebreak$i)] configure -state $state
	}
	[LookupToolbarWidget $dlg $Vars(widget:scoring)] configure -state $state
}


proc CloseTrace {dlg which} {
	variable Options
	variable ${dlg}::Vars

	set Options(debug:$which) 0
	catch { destroy [winfo toplevel $Vars(html)].$which }
}


proc ShowTrace {dlg which} {
	variable ${dlg}::Vars

	if {$which eq "log"} {
		set useHorzScroll 0
	} else {
		set useHorzScroll 1
	}
	set path [winfo toplevel $Vars(html)].$which
	set closeCmd [namespace code [list CloseTrace $dlg $which]]
	::widget::showTrace $path $Vars(output:$which) $useHorzScroll $closeCmd
}


proc ToggleTrace {dlg which} {
	variable Options

	if {$Options(debug:$which)} {
		ShowTrace $dlg $which
	} else {
		CloseTrace $dlg $which
	}
}


proc Destroy {dlg w unsubscribe} {
	if {$w ne $dlg} { return }

	variable ${dlg}::Vars
	variable Key

	catch { destroy $dlg.html }
	catch { destroy $dlg.log }

	if {$unsubscribe} { ::scidb::view::unsubscribe {*}$Vars(subscribe) }
	::scidb::crosstable::release $Vars(tableId) $Vars(viewId)
	if {$Vars(open)} {
		set Vars(open) 0
		::scidb::view::close $Vars(base) $Vars(variant) $Vars(viewId)
	}
	namespace delete [namespace current]::$dlg
	array unset Key $dlg
}


proc Open {dlg which gameIndex} {
	variable ${dlg}::Vars

	Tooltip $dlg hide

	set base $Vars(base)
	set variant $Vars(variant)

	if {![::scidb::db::get open? $base $variant]} {
		return [::dialog::error -parent $dlg -message $mc::BaseIsClosed]
	}

	set path $Vars(html)
	set viewId $Vars(viewId)

	if {$which eq "pgn"} {
		::widget::busyOperation \
			{ ::game::new $path -base $base -variant $variant -view $viewId -number $gameIndex }
	} else {
		set index [::scidb::view::map game $base $variant $viewId $gameIndex]
		set info [::scidb::db::get gameInfo $index $viewId $base $variant]
		set Vars(${which}Id) [::widget::busyOperation \
			[list ::${which}::load $path $base $variant $info $viewId $index $Vars(${which}Id)]]
	}
}


proc ShowPlayerCard {dlg rank} {
	variable ${dlg}::Vars

	Tooltip $dlg hide
	lassign [::scidb::crosstable::get playerId $Vars(tableId) $Vars(viewId) $rank] gameIndex side
	::playercard::show $Vars(base) $Vars(variant) $gameIndex $side
}


proc SelectedPlayerIndex {dlg rank} {
	variable ${dlg}::Vars

	lassign [::scidb::crosstable::get playerId $Vars(tableId) $Vars(viewId) $rank] gameIndex side
	set playerKey [::scidb::db::get playerKey $Vars(base) $Vars(variant) $gameIndex $side]
	return [::scidb::db::find player $Vars(base) $Vars(variant) $playerKey]
}


proc OpenPrepReport {dlg rank} {
	variable ${dlg}::Vars

	Tooltip $dlg hide
	set playerIndex [SelectedPlayerIndex $dlg $rank]
	if {$playerIndex < 0} { return }
	::application::database::player::OpenPrepReport $dlg $Vars(base) $Vars(variant) $playerIndex
}


proc OpenPlayerGamesInSwitcher {dlg rank} {
	variable ${dlg}::Vars

	Tooltip $dlg hide
	set playerIndex [SelectedPlayerIndex $dlg $rank]
	if {$playerIndex < 0} { return 0 }

	set label [::scidb::crosstable::get playerName $Vars(tableId) $Vars(viewId) $rank]
	set view [::scidb::view::new $Vars(base) $Vars(variant) unused unused unused unused master slave]
	::scidb::view::search $Vars(base) $Vars(variant) $view null none [list player $playerIndex]
	set rc [::application::database::OpenFilteredViewInSwitcher \
		$dlg $Vars(base) $Vars(variant) $view crosstable-player $label]
	catch { ::scidb::view::close $Vars(base) $Vars(variant) $view }
	return $rc
}


proc SavePlayerGamesWorkingSet {dlg rank} {
	variable ${dlg}::Vars

	Tooltip $dlg hide
	set playerIndex [SelectedPlayerIndex $dlg $rank]
	if {$playerIndex < 0} { return 0 }

	set label [::scidb::crosstable::get playerName $Vars(tableId) $Vars(viewId) $rank]
	set view [::scidb::view::new $Vars(base) $Vars(variant) unused unused unused unused master slave]
	::scidb::view::search $Vars(base) $Vars(variant) $view null none [list player $playerIndex]
	set rc [::application::database::SaveFilteredViewAsWorkingSet \
		$dlg $Vars(base) $Vars(variant) $view crosstable-player $label]
	catch { ::scidb::view::close $Vars(base) $Vars(variant) $view }
	return $rc
}


proc Tooltip {dlg msg} {
	variable ${dlg}::Vars

	if {$msg eq "hide"} {
		::tooltip::hide yes
	} else {
		::tooltip::hide no ;# XXX probably we need a fix in tooltip.tcl
		::tooltip::show $Vars(html) $msg
	}
}


proc NodeHandler {node} {
	variable Nodes

	set attr [$node attribute -default {} recv]
	# don't hilite "event", because we have no special action for this attribute
	if {[string length $attr] && $attr ne "event"} { set Nodes($attr) $node }
}


proc MouseEnter {dlg nodes} {
	variable ${dlg}::Vars
	variable Options

	HandleEnterLeave $nodes EnterNode

	foreach node $nodes {
		set country [$node attribute -default {} src]
		if {[llength $country]} {
			set Vars(tooltip) $node
			Tooltip $dlg [::country::name $country]
			return
		} elseif {$Options(show:opponent)} {
			set rank [$node attribute -default {} player]
			if {[llength $rank]} {
				set Vars(tooltip) $node
				Tooltip $dlg [::scidb::crosstable::get playerName $Vars(tableId) $Vars(viewId) $rank]
				return
			}
		}
	}
}


proc MouseLeave {dlg nodes {stimulate 0}} {
	variable ${dlg}::Vars

	HandleEnterLeave $nodes LeaveNode
	set hide 0

	foreach node $nodes {
		if {$Vars(tooltip) eq $node} {
			set Vars(tooltip) ""
			foreach attr {src player id} {
				if {[llength [$node attribute -default {} $attr]]} { set hide 1 }
			}
		}
	}

	if {$hide} {
		Tooltip $dlg hide
	}

	if {$stimulate} {
		after idle [list $Vars(html) stimulate]
		::tooltip::hide
	}
}


proc HandleEnterLeave {nodes action} {
	foreach node $nodes {
		set id [$node attribute -default {} recv]
		if {[string length $id]} { $action $id }
		set attr [$node attribute -default {} send]
		foreach id [split $attr :] { $action $id }
	}
}


proc EnterNode {id} {
	variable Highlighted
	variable Nodes
	variable Marks
	variable Colors

	catch {
		set node $Nodes($id)
		if {![info exists Marks($node)]} {
			$node hilite [::colors::lookup $Colors(highlighted)]
		}
		incr Highlighted($node)
	}
}


proc LeaveNode {id} {
	variable Highlighted
	variable Nodes
	variable Marks

	catch {
		set node $Nodes($id)
		if {$Highlighted($node) > 0} {
			if {[incr Highlighted($node) -1] == 0} {
				if {![info exists Marks($node)]} {
					$node hilite none
				}
			}
		}
	}

}


proc Hilite {idList} {
	variable Highlighted
	variable Marks
	variable Nodes
	variable Colors

	set oldIdList {}
	set hilightColor [::colors::lookup $Colors(highlighted)]
	set markColor [::colors::lookup $Colors(mark)]

	foreach node [array names Marks] {
		lappend oldIdList $Marks($node)
		set color none
		catch { if {$Highlighted($node) > 0} { set color $hilightColor } }
		$node hilite $color
	}
	array unset Marks

	set curr [lindex $idList end]
	foreach id [split $idList :] {
		if {$id ni $oldIdList} {
			catch {
				set node $Nodes($id)
				set Marks($node) $id
				$node hilite $markColor
			}
		}
	}
}


proc Mouse1Down {dlg nodes} {
	variable ${dlg}::Vars

	foreach node $nodes {
		set gameIndex [$node attribute -default {} game]
		if {[string length $gameIndex]} {
			::tooltip::hide
			Open $dlg browser $gameIndex
		}

		# don't use because Button-1 is used for highlighting
		# set rank [$node attribute -default {} rank]
		# if {[string length $rank]} { ShowPlayerCard $dlg $rank }

		set mark [$node attribute -default {} mark]
		if {[string length $mark]} {
			set idList [$node attribute -default {} send]
			if {[string length $idList]} { append idList : }
			append idList $mark
			Hilite $idList
		}
	}
}


proc Mouse2Down {dlg nodes} {
	variable ${dlg}::Vars

	foreach node $nodes {
		set gameIndex [$node attribute -default {} game]
		if {[string length $gameIndex]} {
			MouseEnter $dlg $node
			::gamestable::showGame $dlg $Vars(base) $Vars(variant) -1 $gameIndex 
		} else {
			set rank [$node attribute -default {} rank]
			if {[string length $rank]} {
				MouseEnter $dlg $node
				set info [::scidb::crosstable::get playerInfo $Vars(tableId) $Vars(viewId) $rank]
				::playercard::popupInfo $dlg $info
			} else {
				set id [$node attribute -default {} recv]
				if {$id eq "event"} {
					MouseEnter $dlg $node
					::eventtable::popupInfo $dlg $Vars(info)
				}
			}
		}
	}
}


proc Mouse2Up {dlg nodes} {
	::gamestable::hideGame $dlg
	::playercard::popdownInfo $dlg
	::eventtable::popdownInfo $dlg
	MouseLeave $dlg $nodes 1
}


proc Mouse3Down {dlg nodes} {
	variable Popup_
	variable ${dlg}::Vars

	set rank {}
	set gameIndex {}

	foreach node $nodes {
		set r [$node attribute -default {} rank]
		set g [$node attribute -default {} game]
		if {[llength $r]} { set rank $r }
		if {[llength $g]} { set gameIndex $g }
	}

	if {[llength $rank] == 0 && [llength $gameIndex] == 0} {
		if {[info exists Popup_]} { return }
		return [PopupMenu $dlg]
	}

	set m $dlg.popup
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }

	set base $Vars(base)
	set variant $Vars(variant)
	set isOpen [expr {[::scidb::db::get open? $base $variant]}]

	if {$isOpen} {
		if {[llength $rank]} {
			$m add command \
				-compound left \
				-image $::icon::16x16::playercard \
				-label " $::playertable::mc::ShowPlayerCard" \
				-command [namespace code [list ShowPlayerCard $dlg $rank]] \
				;
			if {[llength [info commands ::application::database::player::addPrepReportMenuEntry]]} {
				set playerIndex [SelectedPlayerIndex $dlg $rank]
				if {$playerIndex >= 0} {
					::application::database::player::addPrepReportMenuEntry \
						$m $dlg $Vars(base) $Vars(variant) $playerIndex
				}
			}
			$m add command \
				-label " $::application::database::mc::RepertoireOpenInSwitcher" \
				-command [namespace code [list OpenPlayerGamesInSwitcher $dlg $rank]] \
				;
			$m add command \
				-label " $::application::database::mc::SaveWorkingSet" \
				-command [namespace code [list SavePlayerGamesWorkingSet $dlg $rank]] \
				;
		} else {
			$m add command \
				-compound left \
				-image $::icon::16x16::browse \
				-label " $::browser::mc::BrowseGame" \
				-command [namespace code [list Open $dlg browser $gameIndex]] \
				;
			$m add command \
				-compound left \
				-image $::icon::16x16::overview \
				-label " $::overview::mc::Overview" \
				-command [namespace code [list Open $dlg overview $gameIndex]] \
				;
			$m add command \
				-compound left \
				-image $::icon::16x16::document \
				-label " $::browser::mc::LoadGame" \
				-command [namespace code [list Open $dlg pgn $gameIndex]] \
				;
			if {[::scidb::game::current] < 9} { set state normal } else { set state disabled }
			variable ${dlg}::Vars
			set secondary [list $Vars(base) $Vars(variant) $Vars(viewId) $gameIndex]
			$m add command \
				-compound left \
				-image $::icon::16x16::merge \
				-label " $::browser::mc::MergeGame..." \
				-command [list gamebar::mergeGame $dlg $secondary] \
				-state $state \
			;
		}

		$m add separator
	}

	if {[info exists m]} {
		BuildMenu $dlg $m

		MouseEnter $dlg $nodes
		set Popup_ 1
		bind $m <<MenuUnpost>> [list unset [namespace current]::Popup_]
		bind $m <<MenuUnpost>> +[namespace code [list MouseLeave $dlg $nodes 1]]
		tk_popup $m {*}[winfo pointerxy $dlg]
	}
}


proc BuildMenu {dlg m} {
	variable Options
	variable ${dlg}::Vars

	set sub [menu $m.display]
	set base $Vars(base)
	set variant $Vars(variant)
	set isOpen [expr {[::scidb::db::get open? $base $variant]}]

	if {$isOpen} {
		if {$Vars(bestMode) in {knockout simultan}} { set state disabled } else { set state normal }
		foreach opt {rating performance tiebreak winDrawLoss} {
			$sub add checkbutton \
				-label [set mc::Show[string toupper $opt 0 0]] \
				-command [namespace code [list UpdateContent $dlg]] \
				-variable [namespace current]::Options(show:$opt) \
				-state $state \
				;
			::theme::configureCheckEntry $sub
		}

		if {$Vars(bestMode) eq "swiss"} { set state normal } else { set state disabled }
		$sub add checkbutton \
			-label $mc::ShowOpponent \
			-variable [namespace current]::Options(show:opponent) \
			-state $state
			;
		::theme::configureCheckEntry $sub

		$m add command \
			-label " $mc::SaveAsHTML..." \
			-command [namespace code [list SaveAsHTML $dlg]] \
			-image $::icon::16x16::save \
			-compound left \
			;

		$m add separator
	}

	if {[winfo exists $dlg.next]} {
		set state [expr {$isOpen ? "normal" : "disabled"}]
		$m add command \
			-label " [::mc::stripAmpersand $::widget::mc::Label(previous)]" \
			-command [$dlg.previous cget -command] \
			-image $::icon::16x16::previous \
			-compound left \
			-accelerator "$::mc::Key(Alt)-[::mc::extractAccelerator $::widget::mc::Label(previous)]" \
			-state $state \
			;
		$m add command \
			-label " [::mc::stripAmpersand $::widget::mc::Label(next)]" \
			-command [$dlg.next cget -command] \
			-image $::icon::16x16::next \
			-compound left \
			-accelerator "$::mc::Key(Alt)-[::mc::extractAccelerator $::widget::mc::Label(next)]" \
			-state $state \
			;
	}
	$m add command \
		-label " [::mc::stripAmpersand $::widget::mc::Label(close)]" \
		-command [$dlg.close cget -command] \
		-image $::icon::16x16::close \
		-compound left \
		-accelerator "$::mc::Key(Alt)-[::mc::extractAccelerator $::widget::mc::Label(close)]" \
		;

	if {$isOpen} {
		$m add separator

		::font::html::addChangeFontSizeToMenu crosstable $m \
			[list [namespace current]::ChangeFontSize $dlg] [::html::minFontSize] [::html::maxFontSize]
		::font::html::addChangeFontToMenu crosstable $m [list [namespace current]::ApplyFont $dlg] yes
		$m add separator

		$m add cascade -label $mc::Display -menu $sub
		set sub [menu $m.style]

		menu $sub.spacing
		menu $sub.padding
		menu $sub.knockout

		foreach pad {1 2 3 4 5 6} {
			$sub.padding add radiobutton \
				-label $pad \
				-command [namespace code [list UpdateContent $dlg]] \
				-variable [namespace current]::Options(fmt:padding) \
				-value $pad \
				;
			::theme::configureRadioEntry $sub.padding $pad
		}
		foreach spc {0 1} {
			$sub.spacing add radiobutton \
				-label $spc \
				-command [namespace code [list UpdateContent $dlg]] \
				-variable [namespace current]::Options(fmt:spacing) \
				-value $spc \
				;
			::theme::configureRadioEntry $sub.spacing $spc
		}

		if {$Vars(bestMode) eq "knockout"} { set state normal } else { set state disabled }

		$sub add cascade -label $mc::Spacing -menu $sub.spacing
		$sub add cascade -label $mc::Padding -menu $sub.padding
		$sub add cascade -label $mc::KnockoutStyle -menu $sub.knockout -state $state

		set text $mc::Triangle
		$sub.knockout add radiobutton \
			-label $text \
			-command [namespace code [list UpdateContent $dlg]] \
			-variable [namespace current]::Options(fmt:pyramid) \
			-value 0 \
			;
		::theme::configureRadioEntry $sub.knockout $text
		set text $mc::Pyramid
		$sub.knockout add radiobutton \
			-label $text \
			-command [namespace code [list UpdateContent $dlg]] \
			-variable [namespace current]::Options(fmt:pyramid) \
			-value 1 \
			;
		::theme::configureRadioEntry $sub.knockout $text

		$m add cascade -label $mc::Style -menu $sub
	}

	set sub [menu $m.debugging]

	foreach opt {html log} {
		$sub add checkbutton \
			-label [set mc::Show[string toupper $opt 0 0]] \
			-command [namespace code [list ToggleTrace $dlg $opt]] \
			-variable [namespace current]::Options(debug:$opt) \
			;
		::theme::configureCheckEntry $sub
	}

	if {[llength [info commands ::ai::eventreport::report]]} {
		$m add separator
		$m add command \
			-label $mc::NarrateEvent \
			-command [namespace code [list NarrateEvent $dlg]] \
			;
	}

	$m add separator
	$m add cascade -label $mc::Debugging -menu $sub
}


# Audit B5: the standings as a grounded, read-only narrative (ai-eventreport).
proc NarrateEvent {dlg} {
	variable ${dlg}::Vars

	if {![info exists Vars(viewId)]} { return }
	::ai::eventreport::report $dlg $Vars(base) $Vars(variant) $Vars(viewId)
}


proc ChangeFontSize {dlg size} {
	variable ${dlg}::Vars

	set oldSize [$Vars(html) fontsize?]
	set newSize [$Vars(html) fontsize $size]

	if {$oldSize != $newSize} {
		$Vars(html) parse $Vars(output:html)
	}

	return $newSize
}


proc ApplyFont {dlg} {
	variable ${dlg}::Vars

	$Vars(html) css [DefaultCSS]
	$Vars(html) fontsize [::font::html::fontSize crosstable]
	$Vars(html) parse $Vars(output:html)
}


proc FontSizeChanged {w dlg} {
	if {$w eq $dlg} { after idle [namespace code [list ApplyFont $dlg]] }
}


proc DefaultCSS {} {
	set textFonts [::font::html::defaultTextFonts crosstable]
	set fixedFonts [::font::html::defaultFixedFonts crosstable]
	return [::html::defaultCSS $fixedFonts $textFonts]
}


proc SaveAsHTML {dlg} {
	variable ${dlg}::Vars
	variable Options

	set filetypes [list [list $::dialog::fsbox::mc::FileType(html) {.html}]]
	set eventName [lindex $Vars(event) 0]
	set save [::dialog::saveFile \
		-parent $dlg \
		-class crosstable \
		-initialdir $::scidb::dir::home \
		-initialfile $eventName.html \
		-filetypes $filetypes \
		-needencoding no \
		-geometry last \
	]

	if {[llength $save] == 0} { return }

	set file [lindex $save 0]
	if {[catch { ::open $file w } chan ]} {
		if {[file exists $file]} {
			set msg $mc::CannotOverwriteFile
		} else {
			set msg $mc::CannotCreateFile
		}
		return [::dialog::error -parent $dlg -message [format $msg $file]]
	}

	set html $Vars(output:html)
	set html [regsub -all {[ ](recv|send|game)=[\"][^\"]*[\"]} $html ""]

	append data "    " [::html::textStyle [::font::html::textFonts]] \n
	append data "    " [::html::monoStyle [::font::html::fixedFonts]] \n
	array set flags {}
	while {[set n [string first "<td><img src=" $html]] != -1} {
		set code [string range $html [expr {$n + 14}] [expr {$n + 16}]]
		set flag $::country::icon::flag($code)
		set wd [image width $flag]
		set ht [image height $flag]
		set txt "<div class=\"$code\" title=\"[::country::name $code]\"></div>"
		set html [string replace $html [expr {$n + 4}] [expr {$n + 19}] $txt]
		if {![info exists flags($code)]} {
			set flags($code) 1
			set img [string map {\t "" \n "" " " ""} [$flag cget -data]]
			append data "    .$code { width:${wd}px; height:${ht}px; background-repeat:no-repeat; "
			append data "background-image:url(data:image/png;base64,$img); }\n"
		}
	}
	if {[string length $data]} {
		append style "  <style type=\"text/css\">\n"
		append style $data
		append style "  </style>\n"
		set html [regsub {</head>} $html $style]
	}
	if {[set n [string first "<img src=" $html]] != -1} {
		set i1 [expr {$n + 10}]
		set i2 [expr {$n + 12}]
		set code [string range $html $i1 $i2]
		append src "data:image/png;base64,"
		append src [string map {\t "" \n "" " " ""} [$::country::icon::flag($code) cget -data]]
		append src "\" title=\"[::country::name $code]"
		set html [string replace $html $i1 $i2 $src]
	}

	fconfigure $chan -encoding utf-8
	puts $chan $html
	close $chan
}


proc PopupMenu {dlg} {
	variable ${dlg}::Vars

	set m .application.__crosstable_popup__
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }
	BuildMenu $dlg $m
	bind $m <<MenuUnpost>> [list $Vars(html) stimulate]
	bind $m <<MenuUnpost>> +::tooltip::hide
	tk_popup $m {*}[winfo pointerxy $dlg]
}


proc WriteOptions {chan} {
	::options::writeList $chan [namespace current]::RecentlyUsedHistory
	::options::writeList $chan [namespace current]::MostRecentHistory
	::options::writeItem $chan [namespace current]::RecentlyUsedTiebreaks
	::options::writeItem $chan [namespace current]::RecentlyUsedScoring
	::options::writeItem $chan [namespace current]::Options
}
::options::hookWriter [namespace current]::WriteOptions


namespace eval icon {
namespace eval 32x32 {

# set go [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
# ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
# ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
# MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
# Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
# IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
# YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
# cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
# aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
# b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
# b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
# d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
# b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
# IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
# c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
# REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
# TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
# SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
# SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
# RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
# V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
# SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAEkklEQVR4nNVX
# bVCUVRQ+591lP4TQWSmHQssG1BqEnDQKaghQVMZEA4NRhwQdKbawTJ2xwZYNJpvGD8gBd8QUBHVK
# ww+sGaBMYAYaksTEHBRIRaP4WBIFZHn3ffqxLK0R7PJV0/Przvuee+9zz3nOuecS/cdgewYABOuQ
# mTHOfIaGTqcT7FuNMQB4AQgBoLH5Nr5ErBsA8EzdYTi3JEprTDPkHQMQBEBGZPEGALshtId/XACA
# wMwSgIWLVsTn37jVNEGlVNJTXtMb18ZE5IS85HeQmRtsbUdKQD7UT1EUIZfLe5UKBQQm/unnq1OT
# UtLfLw6YF3y3qyvDRa0+zcz3iIgB0EhEajeWDLBZkvgRN03TZM2kzrud3cJXxWX+r615NzP76MlP
# ATynUDiBmTGSsNgnILBkNkvk6z2z5suD6SlzfGZdUzjJ6eat3ybu2XckNi5xW27FD9VbALjr9XqJ
# mTEckdo1BBEBIJNJdHZzm3ggd+/2lQnrovM8Hp3SYeoVqbKqZsaGrR+npuwwZANYCkDZpwl2xBtD
# auABQ7kAshSj8wC0r74yv2j7zqyE0ooqv/Y/OpyOnyoO/fHi5TkxUcuOAtgnE4TLzEwABIFZGkwc
# DhOwok/1HUSUC6Ci+LvyuP15+TG1ddcfu9bQ+PBHu7MSvy39PrD++m3DE9Pcv2Bmo828AdkybAJ9
# 6SmQxRt1ALYtCPI/uzvzUEJB4bnFzW3tqpLy875XrtbvCl8cPB9AJhGVMLMZAP89U4ZNwOoIq9iY
# 2UxE3wC4EB4WFLUzMye+suqSz+8tRvWBIycjyiur/eLXrMgG0F87xoIAEfV7gy1DbpMJQqZoNpcd
# P134Ru7nZ6J/ufmr5nJtvcfWD9OSXn5xXsjdrq50F7X6BDObrN4YdU1nZliJmCWJmflS5NKFG08d
# 3hOzKjKswMVZ3dUrilJBYekLb21K2UlEc6xTiRxIw9Fj6EwcVQiIiGxCIMkEgUSzefZfIbitAYic
# 1UoKDfIv/2CzNp2ILpBlgjRqAjapBQCT6xpuRGu3pK6vrLrk032/h5zkcprlNb1x3euRD1xgthgp
# AevlI/Vdz0G7MnK0Z4pKFjW3tauYiKa4abrDw4K/ToxfnUFEpWOWhjqbggLA07YQiaJIarWKnn/W
# p3rz27GGaR7ux8a8EOktp3Zt7+gI36zbkVBWUeV3r7ObZTIZeT05tSUmatnR5UtCsmSCUCMB/RsP
# 1jM4TEAUJSaL6+d+djh/w7GThUtvN7W4AiDNJNfe0KCAs0mb4jOIqIiZe8gmTEOta5dAn8RJoZB3
# trYa495J+mTdldoGz/smE6kUCvKdPfNq4vpV+5/xnpXHzE1EZHtquwezSwASBJlMoIs1td4RsRv9
# 24x3nJmZHvdwv7MiPPRE7Mrle5VKRaXJ1Es6nU5ITk7GcFo0+wSYIRMENLca3XtMvfSQ8wQpMGBu
# RdJ7b2a6uAxoySS9Xu/o3vYJyOVyFkXRqafHxCqVknyentG4dnVETkjgwKbUEXc7jAFtebTWmGY4
# NC5tuSNk/v2HyWAYj6fZ/+txOh74E8xEeOdaWuTNAAAAAElFTkSuQmCC
# }]

set go [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAEkklEQVR4nNVX
	bVCUVRQ+591lP4TQWSmHQssG1BqEnDQKaghQVMZEA4NRhwQdKbawTJ2xwZYNJpvGD8gBd8QUBHVK
	ww+sGaBMYAYaksTEHBRIRaP4WBIFZHn3ffqxLK0R7PJV0/Przvuee+9zz3nOuecS/cdgewYABOuQ
	mTHOfIaGTqcT7FuNMQB4AQgBoLH5Nr5ErBsA8EzdYTi3JEprTDPkHQMQBEBGZPEGALshtId/XACA
	wMwSgIWLVsTn37jVNEGlVNJTXtMb18ZE5IS85HeQmRtsbUdKQD7UT1EUIZfLe5UKBQQm/unnq1OT
	UtLfLw6YF3y3qyvDRa0+zcz3iIgB0EhEajeWDLBZkvgRN03TZM2kzrud3cJXxWX+r615NzP76MlP
	ATynUDiBmTGSsNgnILBkNkvk6z2z5suD6SlzfGZdUzjJ6eat3ybu2XckNi5xW27FD9VbALjr9XqJ
	mTEckdo1BBEBIJNJdHZzm3ggd+/2lQnrovM8Hp3SYeoVqbKqZsaGrR+npuwwZANYCkDZpwl2xBtD
	auABQ7kAshSj8wC0r74yv2j7zqyE0ooqv/Y/OpyOnyoO/fHi5TkxUcuOAtgnE4TLzEwABIFZGkwc
	DhOwok/1HUSUC6Ci+LvyuP15+TG1ddcfu9bQ+PBHu7MSvy39PrD++m3DE9Pcv2Bmo828AdkybAJ9
	6SmQxRt1ALYtCPI/uzvzUEJB4bnFzW3tqpLy875XrtbvCl8cPB9AJhGVMLMZAP89U4ZNwOoIq9iY
	2UxE3wC4EB4WFLUzMye+suqSz+8tRvWBIycjyiur/eLXrMgG0F87xoIAEfV7gy1DbpMJQqZoNpcd
	P134Ru7nZ6J/ufmr5nJtvcfWD9OSXn5xXsjdrq50F7X6BDObrN4YdU1nZliJmCWJmflS5NKFG08d
	3hOzKjKswMVZ3dUrilJBYekLb21K2UlEc6xTiRxIw9Fj6EwcVQiIiGxCIMkEgUSzefZfIbitAYic
	1UoKDfIv/2CzNp2ILpBlgjRqAjapBQCT6xpuRGu3pK6vrLrk032/h5zkcprlNb1x3euRD1xgthgp
	AevlI/Vdz0G7MnK0Z4pKFjW3tauYiKa4abrDw4K/ToxfnUFEpWOWhjqbggLA07YQiaJIarWKnn/W
	p3rz27GGaR7ux8a8EOktp3Zt7+gI36zbkVBWUeV3r7ObZTIZeT05tSUmatnR5UtCsmSCUCMB/RsP
	1jM4TEAUJSaL6+d+djh/w7GThUtvN7W4AiDNJNfe0KCAs0mb4jOIqIiZe8gmTEOta5dAn8RJoZB3
	trYa495J+mTdldoGz/smE6kUCvKdPfNq4vpV+5/xnpXHzE1EZHtquwezSwASBJlMoIs1td4RsRv9
	24x3nJmZHvdwv7MiPPRE7Mrle5VKRaXJ1Es6nU5ITk7GcFo0+wSYIRMENLca3XtMvfSQ8wQpMGBu
	RdJ7b2a6uAxoySS9Xu/o3vYJyOVyFkXRqafHxCqVknyentG4dnVETkjgwKbUEXc7jAFtebTWmGY4
	NC5tuSNk/v2HyWAYj6fZ/+txOh74E8xEeOdaWuTNAAAAAElFTkSuQmCC
}]

set reset [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAHTUlEQVR4nM1X
	fVBU1xX/nfvefoCywgLrKjGjpQUbxqpEbO3YkkSpScRJTaoWja3aTrWttrbazKTjFE2NzTg6xsaU
	xhRRawzgByGCKZaimDo2BnADCorfUj52gZUV1P167/QP34Pl20xn0p6ZOzvvvXP3/u7v/M655wL/
	Y6PPO4GZaYh5TET8XyFiZtIW6fteDPS+r2VmZj6Sn269HJmZ+u5AewcArD0bAdgB2ABEaG4eAC4A
	TiIKaBOJAQzHiNwLDRFrC1gkSWpTFKUbEDM/fv1mw+xd7x586vLVm0mt7e7RXq8vDCAOMxsf2GKs
	LRMT4y80NDnLHhtjKyOiRhpkU/0Y0J2YObqguHRDhaNu2rKMeTkJ8RP2MHNEk7N10ZtZ+1dUOmqn
	uu94zF5/AMwMIgIYYDAEEUwmI2KiRj34+rRJ59b9bHl2VJTlKBHdY2ZBROpQDJBG8eT9uR8ur7l0
	fZSqKgFmrtqX+8HK9w4V/6DZ2RauqowR4WbEjbV12GKsTkvESA8A3O3sinS62u2uNrelydkaVvjR
	qdQKR13yz3+0KIWZ3yCipsFA9AqB1+s1KEFFNRlkFWD/wcNFv/nj7vcX+/1+mIxGTJmUeCl9Tuqx
	9O+klsuyfA1AhzY1yufzfaXwbyefPl5yel5N3dX4xmZnxObtu9e0td+JYeb1Goh+4egFQJZlZkAI
	SYiaC/VJZeXnbIFAAJGREb4VGfMPLl8yfxcAxwA7aQFQx8zFC1949v3dew/9cl/eh9/r7LpnzMrJ
	z4iKtHQw8ytaOHqBEH0pYWYSRGh2tT/mDwaMsdaojqytGzYvXzJ/DRFVEZGqpaRgZtLSTmgUK0R0
	7ifLFqzZsH7lLsvI8MADr4/fzs5d1tTk/L4Qop8YewGQZZlBxARACKEQiL81I/mTO533TH/NO/Zb
	V3v7ImY2agwwEfGmTZtUIlI1YJSfzxIRuZ+bNfP3K5a8mGsyGqjZ2R62PWvvSkVRxmti7163rwak
	YCAoqczMqkJCEB8rOZVWdKJ8jspA2cdnG3N2bbkF4F/oEW63adQqzCwRUQczbztb4Ug5+2l1YoWj
	dsqFuivPE9GfQuf1YsBsNrvHxdnvSJJEkiwLISQhSbKQJAmsPnqFJSIlMzNTmEzG6hfnpR0eOSKc
	Ojxd8vG/n56tqmq4xgIB/euAsbXVPb/8bOWTKqtBHScTWCJJPDMzucpqtRYSkX+4AqOnHTOnvvTD
	tfl19TdivzFtcv2et177LhFd0r/LIdSBiPwA8gDkEQEGgwHgnjX8gWBfuh/Fro6125rOX6i3uVyt
	YwDEAbikfxwoCxKZOU1VOdrvD8AfCJI+MjMz+/kPYTrNbc/OnlmWNDHeM2P6ZAeAhoE8hfabsHlb
	Vnn64tUdRSfKtzOzabDTcTDTQFLIADNHM3MaMycOBlUHMGvuwlWeCcnP8epXXq9i5rjQ749qRoPc
	M4wG0BDw5T7PjTZbdMv1200RzS2uOADxABqHWzBUxG63+4Wyf1YlK6yoxNpxT4AgIafOeLIyNtZa
	ECpiHYAuqIaEL4+vrXDUJfy72WUrOXlmttFgOL1x48bhMOg1IXnd77btcNRciTMa5W79Ej0UcMnk
	Jxre3bnpBoBz+pzuLGBmEkLcc9TUlR4v/Tjd7fZIhwtLFvj8/kNEVKMVF2U4JABAgqAoCphZfXhk
	MxRFoYbGliiv12sN9Q2NLTEzvpaUWJwy5QkHQHS++tLEnPcK1jNzJBEp+czSIILUGaza+tr6db9a
	tXTLzj+8unnunNRSVWUiITERkWyQFbPZ3GsT3RrQa7kkSTcbGpreqb5wJamltd2cfeBIht0e28bM
	W4ioHQAymcVGAKGh0WLqB5DHzEU1Fy//+szZ89MZTKqqSpoTBYPBXhsYqCcEM484Wly69Y0df/mp
	1+eHZeQI/9KF6UdWLl/0JoDKwUKhZcvUPQeOrs45+MFiT2eXMcxs8sVaI123Gp3jxj8+xlOwf+dC
	g8FwolclDGGBNRBdzPy6p+Nu5J/3HsrwdHYZd+8/knHm08+mp6d9+5jX6z1pMpmuArij0R+FIL5U
	UFT6VHHJ6XmO2suJPt/DJmbtqpcPV9fWx9xoaI4jhtqXgb5pqIMQRNTIzOtjoqPa3s7OW9bY7Iqo
	dFyMr718be2+3MIVo2OtToslogMA7nZ2WVxtbruz1T3q/n0vhCCMsdvuv7zg+X0ZL819p7r2yg5f
	ICgkWRJmszkwJIAQPQitjXo19Zsp57a+lf3jTyprUtrcnvAbt5ss1241WkiLYHdTajTAbov2pkxN
	qvrFyqV7xtpj84ioq/7ajQNCSIZpU75aAeAzPWL9NDBATEPb8rhmp/Ppwo/Kn6m7fG2Sq9Vt9/n8
	YSozzGajNzba2jIxYcLFubNmnho/ftw/iOi2/h+SJLGiKDEA7mpC7dnsUAC6QTykRQdiwMNLyWgA
	Fs2tEz0XE30B0lr3gS46n//6pvd/w/kNdjUb7FD7/7ucftH2H8kOFUtGlfFPAAAAAElFTkSuQmCC
}]

} ;# namespace 32x32
} ;# namespace icon
} ;# namespace crosstable

# vi:set ts=3 sw=3:
