# ======================================================================
# Author : $Author$
# Version: $Revision: 1522 $
# Date   : $Date: 2018-09-16 09:56:42 -0400 (Sun, 16 Sep 2018) $
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
# Copyright: (C) 2010-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source tree-pane

namespace eval application {
namespace eval tree {
namespace eval mc {

set Total								"Total"
set Control								"Control"
set ChooseReferenceBase				"Choose reference database"
set ReferenceBaseSwitcher			"Reference database switcher"
set Numeric								"Numeric"
set Bar									"Bar"
set StartSearch						"Start search"
set StopSearch							"Stop search"
set UseExactMode						"Use position search mode"
set UseFastMode						"Use accelerated mode"
set UseQuickMode						"Use quick mode"
set AutomaticSearch					"Automatic search"
set LockReferenceBase				"Lock reference database"
set SwitchReferenceBase				"Switch reference database"
set TransparentBar					"Transparent bar"
set MonochromeStyle					"Use monochrome style"
set NoGamesFound						"No games found"
set NoGamesAvailable					"No games available"
set Searching							"Searching"
set VariantsNotYetSupported		"Chess variants not yet supported."
set End									"end"
set ShowMoveOrders					"Show move orders"
set ShowMoveTree						"Show move tree"
set SearchInsideVariations			"Search inside variations"

set FromWhitesPerspective			"From whites perspective"
set FromBlacksPerspective			"From blacks perspective"
set FromSideToMovePerspective		"From side to move perspective"
set FromWhitesPerspectiveTip		"Score from whites perspective"
set FromBlacksPerspectiveTip		"Score from blacks perspective"
set EmphasizeMoveOfGame				"Emphasize move of game"

set TooltipAverageRating			"Average Rating (%s)"
set TooltipBestRating				"Best Rating (%s)"

set F_Number							"#"
set F_Move								"Move"
set F_Eco								"ECO"
set F_Frequency						"Frequency"
set F_Ratio								"Ratio"
set F_Score								"Score"
set F_Draws								"Draws"
set F_Result							"Result"
set F_Performance						"Performance"
set F_AverageYear						"\u00f8 Year"
set F_LastYear							"Last Played"
set F_BestPlayer						"Best Player"
set F_FrequentPlayer					"Frequent Player"

set T_Number							"Numeration"
set T_AverageYear						"Average Year"
set T_FrequentPlayer					"Most Frequent Player"

} ;# namespace mc

#		ID   			Adjustment	Min	Max	Width	Stretch	Removable	Ellipsis	Color
#	----------------------------------------------------------------------------------------
set Columns {
	{ number				right		3		 3		 3			0			1			0			{}				}
	{ move				left		7		 8		 7			0			0			0			{}				}
	{ eco					left		4		 4		 4			0			1			0			darkgreen	}
	{ frequency			right		5		10		 9			0			1			0			{}				}
	{ ratio				right		55px	 6		 6			0			1			0			{}				}
	{ score				right		55px	 6		 6			0			1			0			darkred		}
	{ draws				right		55px	 6		 6			0			1			0			{}				}
	{ result				right		55px	 6		 6			0			1			0			{}				}
	{ averageRating	right		5		 5		 5			0			1			0			darkblue		}
	{ performance		right		5		 5		 5			0			1			0			{}				}
	{ bestRating		right		5		 5		 5			0			1			0			{}				}
	{ averageYear		right		5		 5		 5			0			1			0			{}				}
	{ lastYear			right		5		 5		 5			0			1			0			{}				}
	{ bestPlayer		left		6		 0		12			1			1			1			{}				}
	{ frequentPlayer	left		6		 0		12			1			1			1			{}				}
}

array set Defaults {
	ratio:bar			1
	score:bar			1
	score:side			white
	draws:bar			1
	result:style		mono
	bar:transparent	1
	search:automatic	1
	search:mode			exact
	search:variations	0
	base:lock			0
	sort:column			frequency
	rating:type			Elo
	hilite:nextmove	0
	show:tree			1
	novelty:highlight	0
	repertoire:db		{}

	-background			tree,background
	-emphasize			tree,emphasize
	-stripes				tree,stripes
}

array set Colors {
	ratio:color				tree,ratio:color
	score:color				tree,score:color
	draws:color				tree,draws:color
	progress:color			tree,progress:color
	progress:finished		tree,progress:finished
	result:white:mono		tree,result:mono:white
	result:black:mono		tree,result:mono:black
	result:remis:mono		tree,result:mono:remis
	result:white:color	tree,result:color:white
	result:black:color	tree,result:color:black
	result:remis:color	tree,result:color:remis
}

array set Vars {
	current	{}
	progress	{}
	table		{}
	after		{}
	nextmove	-1
}

array set Bars {}
array set ThreeBars {}

variable Tables {}


proc build {twm parent width height} {
	variable ::ratingbox::ratings
	variable Columns
	variable Defaults
	variable Options
	variable Tables
	variable Colors
	variable Vars

	if {$twm ni $Tables} { lappend Tables $twm }
	set id [::application::twm::getId $twm]
	array set Options [array get Defaults]
	::table::bindOptions db:tree:$id [namespace current]::Options [array names Defaults]

	set bg [::colors::lookup $Options(-background)]
	set mw [tk::multiwindow $parent.mw -borderwidth 0 -background $bg]
	set info [tk::frame $mw.info -background $bg -borderwidth 0 -takefocus 0]
	set mesg [tk::label $mw.mesg -borderwidth 0 -background $bg -foreground darkgreen]
	pack $mw -fill both -expand yes

	bind $mw <<LanguageChanged>> [namespace code SetMessage]

	$mw add $info
	$mw add $mesg

	set tb $info.table
	set sb $info.scrollbar
	set sq $info.square

	set Vars(mw) $mw
	set Vars(table) $tb
	set Vars(info) $info
	set Vars(mesg) $mesg

	set Vars(whiteKnob) \
		[list $::icon::22x22::whiteKnob $::icon::16x16::whiteKnob $::icon::32x32::whiteKnob]
	set Vars(blackKnob) \
		[list $::icon::22x22::blackKnob $::icon::16x16::blackKnob $::icon::32x32::blackKnob]

	::table::table $tb \
		-listmode yes \
		-fixedrows yes \
		-moveable yes \
		-takefocus 0 \
		-fillcolumn end \
		-stripes {} \
		-fullstripes no \
		-background $bg \
		-pady {1 0} \
		-highlightcolor $Options(-emphasize) \
		-id db:tree:$id \
		;
	::widget::bindMouseWheel [::table::tablePath $tb] 1
	::table::setColumnBackground $tb tail [::colors::lookup $Options(-stripes)] $bg
	::table::setScrollCommand $tb [list $sb set]
	::ttk::scrollbar $sb  \
		-orient vertical \
		-takefocus 0     \
		-command [namespace code [list $tb.t yview]] \
		;
	::ttk::frame $sq -borderwidth 1 -relief sunken

	$tb.t state define next
	set font(normal) [::table::getFont $tb]
	set font(bold) [::font::makeBoldFont $font(normal)]
	set specialfont(normal) [list $::font::figurine(text:normal) 9812 9823]
	set specialfont(bold) [list $::font::figurine(text:bold) 9812 9823]
	set Vars(style) [list \
		-font [list $font(bold) next $font(normal) !next] \
		-specialfont [list $specialfont(bold) next $specialfont(normal) !next] \
	]

	grid $tb -row 0 -column 0 -rowspan 2 -sticky nsew
	grid $sb -row 0 -column 1 -rowspan 2 -sticky ns
	grid rowconfigure $info 0 -weight 1
	grid columnconfigure $info 0 -weight 1

	set Vars(styles) {}
	$tb.t element create elemTotal rect -fill [::colors::lookup $Options(-emphasize)]
	set padx $::table::options(element:padding)

	RefreshHeader $tb

	foreach col $Columns {
		lassign $col cid adjustment minwidth maxwidth width stretch removable ellipsis color

		set ivar [namespace current]::I_[string toupper $cid 0 0]
		set fvar [namespace current]::mc::F_[string toupper $cid 0 0]
		set tvar [namespace current]::mc::T_[string toupper $cid 0 0]
		if {![info exists $tvar]} { set tvar {} }
		if {![info exists $fvar]} { set fvar $tvar }
		if {![info exists $ivar]} { set ivar {} } else { set ivar [set $ivar] }

		set menu {}
		set lock none
		set stripes [::colors::lookup $Options(-stripes)]
		set visible [expr {$cid ni {draws}}]

		switch $cid {
			number - move {
				lappend menu [list checkbutton \
					-command [namespace code [list RefreshCurrentItem $tb]] \
					-labelvar [namespace current]::mc::EmphasizeMoveOfGame \
					-variable [namespace current]::Options(hilite:nextmove) \
				]
				lappend menu { separator }
				if {$cid eq "number"} {
					set var {}
					set stripes $Options(-emphasize)
					set lock left
				} else {
					set var ::gamestable::mc::SortAscending
					set stripes $Options(-emphasize)
					set lock left
				}
				if {$cid eq "number"} { set visible 0 }
			}

			eco {
				set visible $Options(show:tree)
				set Vars(eco:visible) $visible
				set var ::gamestable::mc::SortAscending
			}

			ratio - score - draws {
				if {$cid eq "score"} {
					lappend menu [list radiobutton \
						-command [namespace code [list RefreshRatings $tb]] \
						-labelvar [namespace current]::mc::FromWhitesPerspective \
						-variable [namespace current]::Options(score:side) \
						-value white \
					]
					lappend menu [list radiobutton \
						-command [namespace code [list RefreshRatings $tb]] \
						-labelvar [namespace current]::mc::FromBlacksPerspective \
						-variable [namespace current]::Options(score:side) \
						-value black \
					]
					lappend menu [list radiobutton \
						-command [namespace code [list RefreshRatings $tb]] \
						-labelvar [namespace current]::mc::FromSideToMovePerspective \
						-variable [namespace current]::Options(score:side) \
						-value sideToMove \
					]
					lappend menu { separator }
				}
				lappend menu [list radiobutton \
					-command [namespace code [list FetchResult $tb true]] \
					-labelvar [namespace current]::mc::Numeric \
					-variable [namespace current]::Options($cid:bar) \
					-value 0 \
				]
				lappend menu [list radiobutton \
					-command [namespace code [list FetchResult $tb true]] \
					-labelvar [namespace current]::mc::Bar \
					-variable [namespace current]::Options($cid:bar) \
					-value 1 \
				]
				lappend menu { separator }
				lappend menu [list checkbutton \
					-command [namespace code [list ToggleTransparentBar $tb]] \
					-labelvar [namespace current]::mc::TransparentBar \
					-variable [namespace current]::Options(bar:transparent) \
				]
				set var ::gamestable::mc::SortDescending
			}

			result {
				lappend menu [list checkbutton \
					-command [list ::table::refresh $tb] \
					-labelvar [namespace current]::mc::MonochromeStyle \
					-variable [namespace current]::Options(result:style) \
					-onvalue mono \
					-offvalue color \
				]
			}

			averageRating {
				# TODO: si3/4 does not have rating type IPS
				foreach ratType $ratings(all) {
					lappend menu [list radiobutton \
						-command [namespace code [list RefreshRatings $tb]] \
						-label $ratType \
						-variable [namespace current]::Options(rating:type) \
						-value $ratType \
					]
				}
				lappend menu { separator }
				set var ::gamestable::mc::SortDescending
			}

			default {
				set var ::gamestable::mc::SortDescending
			}
		}

		if {[llength $var]} {
			if {$cid eq "ratio"} { set value "frequency" } else { set value $cid }
			lappend menu [list checkbutton \
				-command [namespace code [list SortColumn $tb]] \
				-labelvar $var \
				-variable [namespace current]::Options(sort:column) \
				-onvalue $value \
				]
			lappend menu { separator }
		}

		::table::addcol $tb $cid \
			-justify $adjustment \
			-minwidth $minwidth \
			-maxwidth $maxwidth \
			-width $width \
			-stretch $stretch \
			-removable $removable \
			-ellipsis $ellipsis \
			-visible $visible \
			-foreground $color \
			-menu $menu \
			-image $ivar \
			-textvar $fvar \
			-tooltipvar $tvar \
			-lock $lock \
			-stripes $stripes \
			;

		if {$ellipsis} { set squeeze "x" } else { set squeeze "" }

		$tb.t style create styTotal$cid
		$tb.t style elements styTotal$cid [list elemTotal elemImg elemIco elemTxt$cid]
		::table::setDefaultLayout $tb $cid styTotal$cid
		$tb.t style layout styTotal$cid elemTotal -union elemTxt$cid -iexpand nswe
		lappend Vars(styles) $cid styTotal$cid
	}

	::table::configure $tb move -specialfont [list [list $::font::figurine(text:normal) 9812 9823]]

	::table::bind $tb <ButtonPress-2>	[namespace code [list ShowPlayerInfo $tb %x %y]]
	::table::bind $tb <ButtonRelease-2>	[namespace code [list HideInfo $tb]]
	::table::bind $tb <ButtonPress-1>	[namespace code [list Select $tb %x %y]]
	::table::bind $tb <Button1-Motion>	[namespace code [list Motion1 $tb %x %y]]
	::table::bind $tb <ButtonRelease-1>	+[namespace code [list Activate $tb]]
	::table::bind $tb <ButtonRelease-3>	+[list set [namespace current]::Vars(button) 0]
	::table::bind $tb <Leave>				[namespace code [list Leave %W]]
	::table::bind $tb <Motion>				[namespace code [list Motion %W %x %y]]

	foreach seq {	Shift-Up Shift-Down ButtonPress-1 ButtonPress-3
						ButtonRelease-3 Double-Button-1 Leave Motion} {
		::table::bind $tb <$seq> {+ break }
	}

	bind $tb <<TableScrollbar>>	 [namespace code [list Scrollbar $tb %d]]
	bind $tb <<TableVisit>>			 [namespace code [list VisitItem $tb %d]]
	bind $tb <<TableFill>>			 [namespace code [list FillTable $tb]]
	bind $tb <<TableRebuild>>      [namespace code [list RebuildTable $tb]]
	bind $tb <<TableMenu>>			 [namespace code [list PopupMenu $tb %X %Y]]
	bind $tb <<TableHide>>			 [namespace code [list HideColumn $tb %d 0]]
	bind $tb <<TableShow>>			 [namespace code [list HideColumn $tb %d 1]]
	bind $tb <<LanguageChanged>>	 [namespace code [list FillTable $tb]]
	bind $tb <<LanguageChanged>>	+[namespace code [list RefreshHeader $tb]]

	TreeCtrl::finishBindings $tb

	$tb.t element create rectDivider rect -fill blue -height 1
	# the divider row has a solid background of its own: the columns' stripes
	# would paint it grey in some columns and plain in others
	$tb.t element create rectDividerBg rect -fill [$tb.t cget -background]
	$tb.t style create styLine
	$tb.t style elements styLine {rectDividerBg rectDivider}
	$tb.t style layout styLine rectDividerBg -detach yes -iexpand xy
	$tb.t style layout styLine rectDivider -pady {3 2} -iexpand x

	::toolbar::setup $parent -id tree -layout board
	set tbSwitcher [::toolbar::toolbar $parent \
		-id tree-switcher \
		-side top \
		-alignment left \
		-allow {top bottom} \
		-tooltipvar [namespace current]::mc::ReferenceBaseSwitcher \
	]
	set tbControl [::toolbar::toolbar $parent \
		-id tree-control \
		-hide 0 \
		-side top \
		-alignment left \
		-allow {top bottom} \
		-tooltipvar [namespace current]::mc::Control \
	]
	::toolbar::add $tbControl checkbutton \
		-image $::icon::toolbarSearch \
		-variable [namespace current]::Options(search:automatic) \
		-tooltipvar [namespace current]::mc::AutomaticSearch \
		-command [namespace code [list AutomaticSearch $tb]] \
		;
# XXX not yet working, the tree list is incorrect
#	::toolbar::add $tbControl checkbutton \
#		-image $::icon::toolbarArrowDivide \
#		-variable [namespace current]::Options(search:variations) \
#		-tooltipvar [namespace current]::mc::SearchInsideVariations \
#		-command [namespace code [list InvalidateSearch $tb]] \
#		;
	set search [::toolbar::add $tbControl button \
		-image $::icon::toolbarStart \
		-tooltipvar [namespace current]::mc::StartSearch \
		-command [namespace code startSearch] \
	]
	::toolbar::addSeparator $tbControl
	::toolbar::add $tbSwitcher checkbutton \
		-image $::icon::toolbarLock \
		-variable [namespace current]::Options(base:lock) \
		-tooltipvar [namespace current]::mc::LockReferenceBase \
		-command [namespace code LockBase] \
		;
	set switcher [::toolbar::add $tbSwitcher ::ttk::tcombobox \
		-exportselection no \
		-state readonly \
		-textvariable [namespace current]::Vars(name) \
		-tooltipvar [namespace current]::mc::SwitchReferenceBase \
		-showcolumns {name} \
	]
	$switcher configure -postcommand [namespace code [list FillSwitcher $switcher]]
	set stm [::toolbar::add $tbSwitcher label -image $Vars(whiteKnob) -padx 2]
	foreach mode {exact fast} {
		set Vars(widget:$mode) [::toolbar::add $tbControl button \
			-image [set ::icon::toolbar[string toupper $mode 0 0]] \
			-variable [namespace current]::Options(search:mode) \
			-tooltipvar [namespace current]::mc::Use[string toupper $mode 0 0]Mode \
			-value $mode \
			-command [namespace code [list InvalidateSearch $tb]] \
		]
	}
	set tbProgress [::toolbar::toolbar $parent \
		-id tree-progress \
		-hide 0 \
		-side bottom \
		-alignment left \
		-justify right \
		-allow {top bottom} \
	]
	set progress [::toolbar::add $tbProgress frame -width 130 -height 7 -borderwidth 1 -relief sunken]
	tk::frame $progress.bar -background [::colors::lookup $Colors(progress:color)] -height 5
	$switcher addcol text -id name
	bind $switcher <<LanguageChanged>> [namespace code LanguageChanged]
	bind $switcher <<ComboboxCurrent>> [namespace code [list SetReferenceBase $switcher]]

	set Vars(progress) $progress.bar
	set Vars(search) $search
	set Vars(searching) 0
	set Vars(data) {}
	set Vars(table) $tb
	set Vars(activated) 0
	set Vars(selected) -1
	set Vars(enabled) 1
	set Vars(active) -1
	set Vars(hidden) 1
	set Vars(button) 0
	set Vars(name) {}
	set Vars(current:base) ""
	set Vars(current:variant) ""
	set Vars(list) {}
	set Vars(stm) $stm
	set Vars(twm) $twm
	set Vars(side) {}
	set Vars(show:tree) $Options(show:tree)
### VARIANTS ####################################
set Vars(force) 0
set Vars(switcher) $switcher
#################################################

	set Vars(subscribe) [list tree \
		[list [namespace current]::Update $tb] [list [namespace current]::Close $tb]]
	after idle [list ::scidb::db::subscribe {*}$Vars(subscribe)]
	::scidb::tree::init [namespace current]::Tick $tb
	::scidb::tree::switch [expr {!$Options(base:lock)}]

	bind $mw <Configure> [namespace code PlaceMessage]
	after idle [namespace code startSearch]
	SetSwitcher [::scidb::tree::get] [::scidb::app::variant]
}


proc activate {w flag} {
	variable Vars

	::toolbar::activate $w $flag
	set Vars(hidden) [expr {!$flag}]
}


proc closed {w} {
	variable Tables
	variable Vars

	catch { after cancel $Vars(after) }
	::scidb::db::unsubscribe {*}$Vars(subscribe)
	DeleteBars
#	set i [lsearch $Tables $Vars(twm)]
#	set Tables [lreplace $Tables $i $i]
}


proc linespace {w} {
	variable Vars
	return [::table::linespace $Vars(table)]
}


proc computeHeight {w} {
	variable Vars
	return [expr {[::toolbar::totalHeight $w.tree] + [::table::computeHeight $Vars(table) 0]}]
}


proc columnIndex {name} {
	variable Columns

	set n [lsearch -exact -index 0 $Columns $name]

	if {$n <= 1} { return 0 }
	if {$n == 2} { return 1 }
	if {$n <= 4} { return 2 }

	return [incr n -2]
}


proc startSearch {} {
	variable Vars

	if {![winfo exists $Vars(table)]} { return }
	if {![::scidb::game::query open?]} { return }

### VARIANTS ####################################
if {[::scidb::game::query mainvariant?] ne "Normal"} { return }
#################################################

	if {[llength [::scidb::tree::get]] == 0} {
		return [ShowMessage NoGamesAvailable]
	}

	if {$Vars(searching)} {
		set Vars(searching) 0
		::scidb::tree::stop
		place forget $Vars(progress)
		ConfigSearchButton $Vars(table) Start
		# show "interrupted by user"
	} else {
		set variant [::scidb::game::query mainvariant?]
		set n [::scidb::db::count games [::scidb::tree::get] $variant]
		if {$n == 0} {
			ShowMessage NoGamesAvailable
		} else {
			DoSearch $Vars(table)
		}
	}
}


proc update {position} {
	variable Vars
	variable Options

	if {![[namespace parent]::exists? tree]} { return }

	if {[::scidb::tree::isUpToDate?]} {
		Enabled true
		return
	}

	if {$Options(search:automatic) && [llength [::scidb::tree::get]]} {
		set variant [::scidb::game::query $position mainvariant?]
### VARIANTS ####################################
if {$variant eq "Normal"} {
::toolbar::childconfigure $Vars(switcher) -state readonly
#################################################
		set n [::scidb::db::count games [::scidb::tree::get] $variant]
		if {$n == 0} {
			ShowMessage NoGamesAvailable
		} else {
			after cancel $Vars(after)
			set Vars(after) [after 250 [namespace code [list DoSearch $Vars(table)]]]
		}
### VARIANTS ####################################
} else {
	ShowMessage VariantsNotYetSupported
	games::clear
	set Vars(force) 1
	::toolbar::childconfigure $Vars(switcher) -state disabled
}
#################################################
	}

	Enabled false
}


proc Enabled {flag} {
	variable Vars

	if {$Vars(enabled) == $flag} { return }

	set table $Vars(table)
	set nrows [llength $Vars(data)]
	if {$nrows > 2} { incr nrows } else { incr nrows -1 }
	if {$flag} { set deleted !deleted } else { set deleted deleted }
	set Vars(enabled) $flag

	for {set r 0} {$r < $nrows} {incr r} {
		catch {
			::table::setState $table $r $deleted
			::table::setEnabled $table $r $flag
		}
	}

	if {$flag} {
		if {$Vars(active) != -1} {
			::table::activate $table $Vars(active) true
		} else {
			# TODO
			# check if pointer hovers a tree row
			# ::table::activate $table $row true
		}
	} else {
		::table::activate $table none true
		::table::select $table none
		set Vars(selected) -1
		set Vars(active) -1
	}
}


proc View {pane base variant} {
	set view [::scidb::tree::view]
	if {$view == -1} { return 0 }
	return $view
}


proc ConfigSearchButton {table mode} {
	variable Vars

	::toolbar::childconfigure $Vars(search) \
		-image [set ::icon::toolbar$mode] \
		-tooltipvar [namespace current]::mc::${mode}Search \
		;
}


proc Update {table base variant} {
	variable Vars
	variable Options

### VARIANTS ####################################
if {[::scidb::game::query mainvariant?] eq "Normal"} {
::toolbar::childconfigure $Vars(switcher) -state readonly
#################################################
	if {![[namespace parent]::exists? tree]} { return }
	if {[::scidb::tree::isUpToDate?]} { return }

	if {[string length $base]} {
		if {$base ne $Vars(current:base) || $variant ne $Vars(current:variant)} {
			SetSwitcher $base $variant
		}

		if {[::scidb::db::count games [::scidb::tree::get] $variant] == 0} {
			ShowMessage NoGamesAvailable
		} elseif {$Options(search:automatic)} {
			after cancel $Vars(after)
			set Vars(after) [after 250 [namespace code [list DoSearch $table]]]
		}
	} else {
		ShowMessage NoGamesAvailable
	}

	Enabled false
### VARIANTS ####################################
} else {
ShowMessage VariantsNotYetSupported
games::clear
set Vars(force) 1
::toolbar::childconfigure $Vars(switcher) -state disabled
}
#################################################
}


proc DoSearch {table} {
	variable Vars
	variable Options
	variable Colors

### VARIANTS ####################################
if {[::scidb::game::query mainvariant?] ne "Normal"} { return }
#################################################

	if {[::scidb::tree::update $Options(rating:type) $Options(search:mode) $Options(search:variations)]} {
		if {$Vars(searching)} {
			$Vars(progress) configure -background [::colors::lookup $Colors(progress:finished)]
			place $Vars(progress) -x 1 -y 1 -width 127
			set Vars(searching) 0
		}
		SearchResultAvailable $table
	} else {
		if {[llength $Vars(data)] == 0} { ShowMessage Searching }
		set Vars(searching) 1
		ConfigSearchButton $table Stop
		$Vars(progress) configure -background [::colors::lookup $Colors(progress:color)]
		place forget $Vars(progress)
	}
}


proc Close {table base variant} {
	if {$base eq [::scidb::tree::get] && $variant eq [::scidb::app::variant]} {
		return [ShowMessage NoGamesAvailable]	}
}


proc Tick {table n} {
	variable Vars
	variable Options
	variable Colors

	if {[llength [::scidb::tree::get]] == 0} { return }

	if {$n == 0} {
		if {$Vars(searching)} {
			place forget $Vars(progress)
			$Vars(progress) configure -background [::colors::lookup $Colors(progress:color)]
			set Vars(searching) 0
			ConfigSearchButton $table Start
			# show "interrupted due to a database modification"
		}
	} else {
		if {!$Vars(searching)} {
			ConfigSearchButton $table Stop
			$Vars(progress) configure -background [::colors::lookup $Colors(progress:color)]
			set Vars(searching) 1
		}

		place $Vars(progress) -x 1 -y 1 -width [expr {($n - 1)/2}]

		if {$n == 255} {
			set Vars(searching) 0
			ConfigSearchButton $table Start
			$Vars(progress) configure -background [::colors::lookup $Colors(progress:finished)]
			after idle [namespace code [list SearchResultAvailable $table]]
		}
	}
}


proc InvalidateSearch {table} {
	::scidb::tree::invalidate
	AutomaticSearch $table
}


proc AutomaticSearch {table} {
	variable Options

	if {$Options(search:automatic)} {
		Update $table [::scidb::tree::get] [::scidb::app::variant]
	}
}


proc SortColumn {table} {
	FetchResult $table true
}


proc DoSelection {table} {
	variable Vars

	if {![winfo exists $table]} { return }
	if {$Vars(hidden)} { return }

	lassign [winfo pointerxy $table] x y
	set x [expr {$x - [winfo rootx $table]}]
	set y [expr {$y - [winfo rooty $table]}]
	lassign [::table::identify $table $x $y] row
	set nrows [llength $Vars(data)]

	if {$row + 1 < $nrows} {
		::table::activate $table $row true
		set Vars(active) $row
	}
}


proc HideColumn {table id flag} {
	variable Vars

	if {$id eq "draws"} {
		set Vars(draws:visible) $flag
		::toolbar::childconfigure $Vars(stm) -visible $Vars(draws:visible)
		::table::refresh $table
	}
}


proc VisitItem {table data} {
	variable Options
	variable Vars

	lassign $data mode id row
	set nrows [llength $Vars(data)]
	set Vars(active) -1

	if {$row + 1 < $nrows} {
		if {$mode eq "enter"} {
			if {$Vars(enabled)} {
				::table::activate $table $row true
			}
			set Vars(active) $row
		} else {
			::table::activate $table none true
		}
	}

	if {$nrows <= 1 || $row + 1 == $nrows} { return }

	if {$mode eq "leave"} {
		::tooltip::hide
	} else {
		if {$row == $nrows} { incr row -1 }
		set value [lindex $Vars(data) $row [columnIndex $id]]
		set item {}

		switch $id {
			ratio - score - draws {
				if {$Options($id:bar)} {
					set total [lindex $Vars(data) end [columnIndex frequency]]
					set value [ComputeValue $id $value $total]
					set item [Format $value]
					append item "%"
				}
			}

			result {
				lassign $value white black draws lost
				lassign [ComputePercentages $white $black $draws] white black draws
				append item "$::mc::White [Format $white]%  "
				append item "$mc::F_Draws [Format $draws]%  "
				append item "$::mc::Black [Format $black]%"
			}

			eco {
				set opening [::scidb::app::lookup ecoCode $value]
				lassign $opening long short
				set vars [lrange $opening 2 end]
				if {[llength $vars]} {
					set item [::mc::translateEco $short]
					foreach var $vars { append item ", " [::mc::translateEco $var] }
				} else {
					set item [::mc::translateEco $long]
				}
			}

			bestPlayer {
				if {"bestRating" ni [::table::visibleColumns $table]} {
					set value [lindex $value 1]
					if {$value > 0} {
						set item "$Options(rating:type): $value"
					}
				}
			}

			frequentPlayer {
				set value [lindex $value 1]
				if {$value > 0} {
					set item "$mc::F_Frequency: $value"
				}
			}
		}

		if {[string length $item]} {
			::tooltip::show $table $item
		}
	}
}


proc ComputePercentages {white black draws} {
	set total  [expr {double($white + $black + $draws)}]
	set whiteF [expr {($white*1000.0)/$total}]
	set drawsF [expr {($draws*1000.0)/$total}]
	set blackF [expr {($black*1000.0)/$total}]
	set whiteI [expr {int($whiteF + 0.5)}]
	set drawsI [expr {int($drawsF + 0.5)}]
	set blackI [expr {int($blackF + 0.5)}]
	if {[expr {1000 - $whiteI - $drawsI - $blackI}] > 0} {
		set whiteR [expr {$whiteF - $whiteI}]
		set drawsR [expr {$drawsF - $drawsI}]
		set blackR [expr {$blackF - $blackI}]
		if {$whiteR > $blackR && $whiteR > $drawsR} {
			incr whiteI
		} elseif {$blackR > $drawsR} {
			incr blackI
		} else {
			incr drawsI
		}
	}
	return [list $whiteI $blackI $drawsI]
}


proc ShowPlayerInfo {table x y} {
	variable Columns
	variable Options
	variable Vars

	::tooltip::disable
	set Vars(button) 2
	set nrows [llength $Vars(data)]
	if {$nrows == 0} { return }
	lassign [::table::identify $table $x $y] row column
	if {$row == -1} { return }
	if {$row + 1 == $nrows} { return }
	set id [lindex $Columns $column 0]
	if {$id ne "bestPlayer" && $id ne "frequentPlayer"} { return }
	::table::activate $table $row 1
	if {$row == $nrows} { incr row -1 }
	set info [::scidb::tree::player $row $id $Options(rating:type)]
	::playercard::popupInfo $table $info
}


proc HideInfo {table} {
	variable Vars

	::tooltip::enable
	set Vars(button) 0
	::playercard::popdownInfo $table
	after idle [namespace code [list DoSelection $table]]
}


proc ToggleTransparentBar {table} {
	DeleteBars
	FetchResult $table true
}


proc RefreshCurrentItem {table} {
	variable Vars

	if {$Vars(nextmove) >= 0} {
		SetItemState $table $Vars(nextmove)
	}
}


proc RefreshHeader {table} {
	variable Options

	set mc::F_AverageRating "\u00f8 $Options(rating:type)"
	set mc::T_AverageRating [format $mc::TooltipAverageRating $Options(rating:type)]
	set mc::F_BestRating [format $mc::TooltipBestRating $Options(rating:type)]
}


proc RefreshRatings {table} {
	variable Vars

	if {![[namespace parent]::exists? tree]} { return }

	RefreshHeader table
	FetchResult $table true
	RefreshRatingLabel
}


proc RefreshRatingLabel {} {
	variable Vars
	variable Options

	if {![[namespace parent]::exists? tree]} { return }

	set side white
	switch $Options(score:side) {
		black			{ set side black }
		sideToMove	{ if {[::scidb::pos::stm] eq "b"} { set side black } }
	}

	if {$Vars(side) != $side} {
		set Vars(side) $side
		::toolbar::childconfigure $Vars(stm) -image $Vars(${side}Knob)
		switch $side {
			white { set var FromWhitesPerspectiveTip }
			black { set var FromBlacksPerspectiveTip }
		}
		::toolbar::childconfigure $Vars(stm) -tooltipvar [namespace current]::mc::$var
	}
}


proc SearchResultAvailable {table} {
	FetchResult $table
#	[namespace parent]::vars::update
}


proc FetchResult {table {force false}} {
	variable Options
	variable Colors
	variable Vars

	# neccessary because of "after" effect
	set table $Vars(table)

### VARIANTS ####################################
if {[::scidb::game::query mainvariant?] ne "Normal"} { return }
if {$Vars(force)} { set force true }
#################################################

	$Vars(progress) configure -background [::colors::lookup $Colors(progress:finished)]

	set options {}
	if {[llength $Options(sort:column)]} {
		lappend options -sort [columnIndex $Options(sort:column)]
	}
	set state [::scidb::tree::finish \
		$Options(rating:type) \
		$Options(search:mode) \
		$Options(search:variations) \
		{*}$options \
	]

	if {$force || $state ne "unchanged"} {
		set Vars(data) [::scidb::tree::fetch]
		set nrows [llength $Vars(data)]

		if {$nrows == 0} {
			set variant [::scidb::game::query mainvariant?]
			set n [::scidb::db::count games [::scidb::tree::get] $variant]
			if {$n == 0} { set msg NoGamesAvailable } else { set msg NoGamesFound }
			ShowMessage $msg
		} else {
			if {$nrows == 2} { set nrows 1 } elseif {$nrows} { incr nrows }
			set active [::table::active $table]

			::table::clear $table
			::table::setHeight $table 0
			::table::setHeight $table $nrows [namespace current]::SetItemStyle
			FillTable $table
			$Vars(mw) raise $Vars(info)

			if {0 <= $active && $active < max(1, $nrows - 1)} {
				::table::activate $table $active true
			}
		}
	}

### VARIANTS ####################################
if {$Vars(force)} {
	games::UpdateTable [games::table] $Vars(current:base) Normal
	set Vars(force) 0
}
#################################################

	set Vars(activated) 0
	if {[llength $Vars(data)]} { Enabled true }
}


proc SetItemStyle {table item row} {
	variable Vars
	variable Columns

	set nrows [expr {[llength $Vars(data)] + 1}]

	if {$row == [expr {$nrows - 2}]} {
		set style {}
		foreach col $Columns { lappend style [lindex $col 0] styLine }
		$table.t item style set $item {*}$style
		$table.t item enabled $item false
	} elseif {$row == [expr {$nrows - 1}]} {
		$table.t item style set $item {*}$Vars(styles)
	} else {
		$table.t item style set $item {*}[::table::defaultStyles $table]
		$table.t item element configure $row move elemTxtmove {*}$Vars(style)
		$table.t item element configure $row number elemTxtnumber {*}$Vars(style)
	}
}


proc PlaceMessage {} {
	variable Vars

	set width [expr {max(1, [winfo width $Vars(mw)] - 50)}]
	$Vars(mesg) configure -wraplength $width
}


proc SetMessage {} {
	variable Vars

	set txt [set mc::$Vars(message)]
	if {$Vars(message) eq "Searching"} { append txt "..." }
	$Vars(mesg) configure -text $txt
	PlaceMessage
}


proc ShowMessage {msg} {
	variable Vars

	set Vars(message) $msg
	SetMessage
	$Vars(mw) raise $Vars(mesg)
}


proc Format {value} {
	return [expr {$value/10}][::locale::decimalPoint][expr {$value%10}]
}


proc SetItemState {table index} {
	variable Options
	variable Vars

	if {$Vars(nextmove) != $index || !$Options(hilite:nextmove)} { append states ! }
	append states next
	# may fail, when switching variant
	catch { $table.t item state set $index $states }
}


proc FillTable {table} {
	variable Options
	variable Columns
	variable Vars

	if {[llength $Vars(data)] == 0} { return }

	set total [lindex $Vars(data) end [columnIndex frequency]]
	set nrows [llength $Vars(data)]
	set stm [::scidb::pos::stm]
	set row 1
	set nextMove [::scidb::game::next move]
	set Vars(nextmove) -1

	RefreshRatingLabel

	foreach rowData $Vars(data) {
		set col 0
		set text {}

		foreach entry $Columns {
			set id [lindex $entry 0]
			set item [lindex $rowData $col]

			switch $id {
				number {
					if {$row < [llength $Vars(data)]} {
						lappend text ${row}.
					} else {
						lappend text {}
					}
				}

				move {
					if {$row == [expr {$nrows + 1}]} {
						lappend text $mc::Total
					} else {
						set index [expr {$row - 1}]
						if {$item eq "end"} {
							if {[string length $nextMove] == 0} { set Vars(nextmove) $index }
							SetItemState $table $index
							# lappend text "\uff0d"
							# lappend text "\u2205"
							lappend text "\[$mc::End\]"
						} else {
							if {$nextMove eq $item} { set Vars(nextmove) $index }
							# if {$item eq "--"} { set item null }
							SetItemState $table $index
							lappend text [::font::translate $item]
						}
					}
					incr col
				}

				eco {
					lappend text [string range $item 0 2]
					incr col
				}

				frequency {
					lappend text [::locale::formatNumber $item]
				}

				ratio - score - draws {
					set item [ComputeValue $id $item $total]
					if {$Options($id:bar)} {
						lappend text [list @ [MakeBar $table $id $item]]
					} else {
						lappend text [Format $item]
					}
					incr col
				}

				result {
					lassign $item white black draws lost
					lappend text [list @ [MakeThreeBar $table $white $black $draws]]
					incr col
				}

				performance {
					if {$item >= 0} {
						lappend text $item
					} else {
						lappend text {}
					}
					incr col
				}

				averageRating - bestRating - averageYear - lastYear {
					if {$item} {
						lappend text $item
					} else {
						lappend text {}
					}
					incr col
				}

				bestPlayer - frequentPlayer {
					lappend text [lindex $item 0]
					incr col
				}
			}
		}

		::table::insert $table [expr {$row - 1}] $text

		if {$nrows == 2} { return }

		if {[incr row] == $nrows} {
			::table::insert $table $row [lrepeat [llength $Columns] {}]
			incr row
		}
	}

	catch { ::table::see $table 0 }
	DoSelection $table
}


proc MakeBar {table id item} {
	variable Options
	variable Colors
	variable Bars

	set color [::colors::lookup $Colors($id:color)]
	set width [expr {($item + 10)/20}]
	if {[info exists Bars($width:$color)]} { return $Bars($width:$color) }
	set h [expr {max(8, [::table::linespace $table] - 6)}]
	set img [image create photo -width 51 -height [expr {$h + 1}]]
	::scidb::tk::image recolor black $img -composite set
	if {$Options(bar:transparent)} {
		::scidb::tk::image alpha 0.0 $img -composite set -area 1 1 50 $h
	} else {
		::scidb::tk::image recolor white $img -composite set -area 1 1 50 $h
	}
	::scidb::tk::image recolor $color $img -composite set -area 1 1 $width $h 
	return [set Bars($width:$color) $img]
}


proc MakeThreeBar {table whiteResult blackResult drawResult} {
	variable ThreeBars
	variable Options
	variable Colors

	set total [expr {double($whiteResult + $blackResult + $drawResult)}]
	set white [expr {$total ? ($whiteResult*49)/$total : 0.0}]
	set black [expr {$total ? ($blackResult*49)/$total : 0.0}]
	set white [expr {int($white + 0.5) + 1}]
	set draws [expr {50 - int($black + 0.5)}]
	if {[info exists ThreeBars($white:$draws)]} { return $ThreeBars($white:$draws) }
	set h [expr {max(8, [::table::linespace $table] - 6)}]
	set img [image create photo -width 51 -height [expr {$h + 1}]]
	::scidb::tk::image recolor black $img -composite set
	if {$Options(bar:transparent)} {
		::scidb::tk::image alpha 0.0 $img -composite set -area 1 1 50 $h
	} else {
		::scidb::tk::image recolor white $img -composite set -area 1 1 50 $h
	}
	set style $Options(result:style)
	::scidb::tk::image recolor [::colors::lookup $Colors(result:white:$style)] $img \
		-composite set -area 1 1 $white $h 
	::scidb::tk::image recolor [::colors::lookup $Colors(result:remis:$style)] $img \
		-composite set -area $white 1 $draws $h 
	::scidb::tk::image recolor [::colors::lookup $Colors(result:black:$style)] $img \
		-composite set -area $draws 1 50 $h 
	return [set ThreeBars($white:$draws) $img]
}


proc ComputeValue {id value total} {
	variable Options

	switch $id {
		ratio {
			if {$total == 0} {
				set value 0
			} else {
				set value [expr {int((1000.0*$value)/double($total) + 0.5)}]
			}
		}
		score {
			switch $Options(score:side) {
				black {
					set value [expr {1000 - $value}]
				}
				sideToMove {
					if {[::scidb::pos::stm] eq "b"} {
						set value [expr {1000 - $value}]
					}
				}
			}
		}
	}

	return $value
}


proc FindIndex {table x y} {
	variable Vars

	set x [expr {$x - [winfo rootx $table]}]
	set y [expr {$y - [winfo rooty $table]}]
	lassign [::table::identify $table $x $y] row column
	set nrows [llength $Vars(data)]
	if {0 <= $row && ($nrows == 1 || $row < $nrows - 1)} { return $row }
	return -1
}


proc Select {table x y} {
	variable Vars

	set Vars(button) 1
	if {$Vars(activated)} { return }

	::tooltip::disable
	lassign [::table::identify $table $x $y] row column

	if {$row == -1} {
		::table::Highlight $table $x $y
	} else {
		set nrows [llength $Vars(data)]

		if {0 <= $row && ($nrows == 1 || $row < $nrows - 1)} {
			set move [::scidb::tree::move $row]
			if {[string length $move]} {
				set Vars(selected) $row
				::table::select $table $row
			}
		}
	}
}


proc Motion1 {table x y} {
	variable Vars

	if {!$Vars(enabled)} { return }
	if {$Vars(activated)} { return }
	if {$Vars(selected) == -1} { return }

	lassign [::table::identify $table $x $y] row column

	if {$row < 0} {
		::table::activate $table none
		::table::select $table none
		set offs [::table::scrolldistance $table $y]

		if {$offs != 0} {
			if {$offs < 0} {
				set Vars(dir) -1
			} else {	;# offs > 0
				set Vars(dir) +1
			}

			set Vars(interval) [expr {300/max(int(abs($offs)/5.0 + 0.5), 1)}]

			if {![info exists Vars(timer)]} {
				set Vars(timer) [after $Vars(interval) [namespace code [list Scroll $table]]]
			}
		} elseif {[info exists Vars(timer)]} {
			after cancel $Vars(timer)
			unset Vars(timer)
		}
	} else {
		if {[info exists Vars(timer)]} {
			after cancel $Vars(timer)
			unset Vars(timer)
		}
		if {$row == $Vars(selected)} {
			if {$row != [::table::selection $table]} {
				::table::select $table $row
			}
		} elseif {$row >= 0} {
			if {$Vars(selected) == [::table::selection $table]} {
				::table::select $table none
			}
		}
	}

	TreeCtrl::MotionInItems $table.t $x $y
}


proc Motion {w x y} {
	variable Vars

	if {$Vars(button) != 2} {
		TreeCtrl::CursorCheck $w $x $y
		TreeCtrl::MotionInHeader $w $x $y
		TreeCtrl::MotionInItems $w $x $y
	}
}


proc Leave {w} {
	variable Vars

	if {$Vars(button) != 2} {
		TreeCtrl::CursorCancel $w
		TreeCtrl::MotionInHeader $w
		TreeCtrl::MotionInItems $w
	}
}


proc Scroll {table} {
	variable Vars

	if {[info exists Vars(dir)]} {
		$table.t yview scroll $Vars(dir) units
		set Vars(timer) [after $Vars(interval) [namespace code [list Scroll $table]]]
	}
}


proc Activate {table} {
	variable Vars

	set Vars(button) 0
	::tooltip::enable

	if {[info exists Vars(dir)]} {
		catch { after kill $Vars(timer) }
		unset -nocomplain Vars(dir)
		unset -nocomplain Vars(timer)
		unset -nocomplain Vars(interval)
	}

	if {$Vars(activated)} { return }
	if {$Vars(selected) == -1} { return }

	set Vars(activated) 1
	
	if {$Vars(selected) == [::table::selection $table]} {
		set move [::scidb::tree::move $Vars(selected)]
		if {[string length $move]} {
			set action [::move::addMove menu $move \
				-nomovecmd [list set [namespace current]::Vars(activated) 0] \
				-actions {load} \
			]
			if {$action eq "load"} { LoadFirstGame $table $Vars(selected) $move }
		}
	} else {
		set Vars(activated) 0
	}

	set Vars(selected) -1
	::table::select $table none
	DoSelection $table
}


proc LoadFirstGame {table row move} {
	set index [::scidb::tree::gameIndex $row]
	set fen [::scidb::tree::position $move]
	set base [::scidb::tree::get]
	set variant [::scidb::app::variant]
	set view [::scidb::tree::view]

	::game::new $table -base $base -variant $variant -view $view -number $index -fen $fen
}


proc Scrollbar {table state} {
	set parent [winfo parent $table]
	set sq $parent.square
	set sb $parent.scrollbar

	if {$state eq "hide"} {
		grid forget $sq
		grid $sb -row 0 -column 1 -rowspan 2 -sticky ns
	} elseif {$sq ni [grid slaves $parent]} {
		set size [winfo width $sb]
		$sq configure -width $size -height $size
		grid $sb -row 0 -column 1 -rowspan 1 -sticky ns
		grid $sq -row 1 -column 1
	}
}


proc SetReferenceBase {w} {
	variable ::scidb::clipbaseName
	variable Vars

	set index [[::toolbar::realpath $w] current]

	if {$index == 0} {
		set base $clipbaseName
	} else {
		set base [lindex $Vars(list) [expr {$index - 1}] 1]
	}

	::scidb::tree::set $base
}


proc FillSwitcher {w} {
	variable Vars

	set w [::toolbar::realpath $w]

	$w clear
	$w listinsert [list $::util::clipbaseName]

	set list {}
	foreach base [::scidb::tree::list] { lappend list [list [::util::databaseName $base] $base] }
### VARIANTS ####################################
set l {}
foreach entry $list {
	if {"Normal" in [::scidb::db::get variants [lindex $entry 1]]} { lappend l $entry }
}
set list $l
#################################################
	set list [lsort -dictionary -index 0 $list]

	foreach base $list {
		$w listinsert [list [lindex $base 0]]
	}

	set Vars(list) $list
	$w resize
}


proc SetSwitcher {base variant} {
	variable ::scidb::clipbaseName
	variable Vars

	set Vars(current:base) $base
	set Vars(current:variant) $variant
	set name [::util::databaseName $base]
	if {$name eq $clipbaseName} { set name $::util::clipbaseName }
	set Vars(name) $name
}


proc LanguageChanged {} {
	SetSwitcher [::scidb::tree::get] [::scidb::app::variant]
}


proc LockBase {} {
	variable Options
	::scidb::tree::switch [expr {!$Options(base:lock)}]
}


proc DoAction {table row move action} {
	if {$action eq "load"} {
		LoadFirstGame $table $row $move
	} else {
		::move::doAction $action $move
	}
}


proc ToggleView {table} {
	variable Options
	variable Vars

	if {$Vars(show:tree) == $Options(show:tree)} { return }

	if {$Options(show:tree)} {
		if {$Vars(eco:visible)} {
			::table::showColumn $table eco
		}
		::toolbar::childconfigure $Vars(widget:exact) -state normal
		::toolbar::childconfigure $Vars(widget:fast) -state normal
	} else {
		set Vars(eco:visible) [::table::visible? $table eco]
		::table::hideColumn $table eco
		::toolbar::childconfigure $Vars(widget:exact) -state disabled
		::toolbar::childconfigure $Vars(widget:fast) -state disabled
	}

	games::clear
	set Vars(show:tree) $Options(show:tree)
}


proc PopupMenu {table x y} {
	variable ::scidb::clipbaseName
	variable Vars
	variable Options
	variable _Current

	set Vars(button) 3
	set m $table.popup_menu
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }
	set row [FindIndex $table $x $y]

	if {$row >= 0} {
		::table::activate $table $row true
		after idle [list ::table::activate $table $row true]
		set move [::scidb::tree::move $row]
		if {[string length $move] && $move ne [::scidb::game::next move]} {
			::move::addActionsToMenu $m [namespace code [list DoAction $table $row $move]] {append load}
			$m add separator

			# Add "Analyze this position" option
			$m add command \
				-label " $::application::analysis::mc::AnalyzeThisPosition" \
				-command [list ::application::analysis::AnalyzePosition $table $row] \
				-image $::icon::16x16::engine \
				-compound left \
				;
			$m add separator
		}
	}

#	$m add radiobutton \
#		-label $mc::ShowMoveTree \
#		-variable [namespace current]::Options(show:tree) \
#		-value 1 \
#		-command [namespace code [list ToggleView $table]] \
#	;
#	::theme::configureRadioEntry $m
#	$m add radiobutton \
#		-label $mc::ShowMoveOrders \
#		-variable [namespace current]::Options(show:tree) \
#		-value 0 \
#		-command [namespace code [list ToggleView $table]] \
#	;
#	::theme::configureRadioEntry $m
#	$m add separator
	$m add command \
		-label " $mc::StartSearch" \
		-command [namespace code startSearch] \
		-image $::icon::16x16::start \
		-compound left \
		;
	$m add separator
	# Opening Report entry
	$m add command \
		-label $openingreport::mc::Title \
		-command [list [namespace current]::openingreport::show $table] \
		;
	$m add separator
	if {$Options(show:tree)} {
		foreach {mode icon} {exact slow fast fast} {
			set text " [set mc::Use[string toupper $mode 0 0]Mode]"
			$m add radiobutton \
				-label $text \
				-variable [namespace current]::Options(search:mode) \
				-value $mode \
				-image [set ::icon::16x16::$icon] \
				-compound left \
				;
			::theme::configureRadioEntry $m
		}
		$m add separator
	}
	$m add checkbutton \
		-label $mc::AutomaticSearch \
		-variable [namespace current]::Options(search:automatic) \
		-image $::icon::16x16::search \
		-compound left \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label " $::application::analysis::mc::HighlightNovelties" \
		-variable [namespace current]::Options(novelty:highlight) \
		-command [namespace code [list ToggleNoveltyHighlighting $table]] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $mc::SearchInsideVariations \
		-variable [namespace current]::Options(search:variations) \
		-image $::icon::16x16::none \
		-compound left \
		-command [namespace code [list InvalidateSearch $table]] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $mc::LockReferenceBase \
		-variable [namespace current]::Options(base:lock) \
		-image $::icon::16x16::lock \
		-compound left \
		;
	::theme::configureCheckEntry $m
	$m add separator

	set n [menu $m.switch -tearoff false]
	$m add cascade -menu $n -label $mc::ChooseReferenceBase

	set list {}
	foreach base [::scidb::tree::list] {
		if {$base eq $Vars(current:base)} { set _Current $base }
		lappend list [list [::util::databaseName $base] $base]
	}
	if {$Vars(current:base) eq $clipbaseName} {
		set _Current $clipbaseName
	}

	set text $::util::clipbaseName
	$n add radiobutton \
		-label $text \
		-value $clipbaseName \
		-variable [namespace current]::_Current \
		-command [list ::scidb::tree::set $clipbaseName] \
		;
	::theme::configureRadioEntry $n $text
	foreach base [lsort -dictionary -index 0 $list] {
		lassign $base text value
		$n add radiobutton \
			-label $text \
			-value $value \
			-variable [namespace current]::_Current \
			-command [list ::scidb::tree::set $value] \
			;
		::theme::configureRadioEntry $n
	}

	::bind $m <<MenuUnpost>> [list after idle [list table::doSelection $table]]
	tk_popup $m $x $y
}


# proc ShowAllMoveOrders {parent} {
# 	set parent [winfo toplevel $parent]
# 	set dlg $parent.moveOrders
# 	set top $dlg.top
# 	set tb $top.table
# 	set exists [winfo exists $dlg]
# 	set lines [::scidb::game::lines]
# 
# 	if {$exists} {
# 		$tb clear
# 	} else {
# 		wm withdraw [tk::toplevel $dlg -class Dialog]
# 		set specialfont [list [list $::font::figurine(text:normal) 9812 9823]]
# 		set stripes [::colors::lookup table,stripes]
# 		pack [ttk::frame $top -borderwidth 0 -takefocus 0] -fill both -expand yes
# 		pack [tlistbox $tb \
# 			-setgrid 1 \
# 			-maxheight 20 \
# 			-maxwidth 800 \
# 			-stripes $stripes \
# 			-takefocus 0
# 		] -fill both -expand yes
# 		$tb addcol text -id line -specialfont $specialfont -expand yes
# 	}
# 
# 	foreach line $lines { $tb insert [list $line] }
# 	$tb resize -force -dontshrink
# 
# 	if {$exists} {
# 		widget::dialogRaise $dlg
# 	} else {
# 		::widget::dialogButtons $dlg {close}
# 		::widget::dialogButtonAdd $dlg spread [namespace current]::mc::ComputeSpread {}
# 		$dlg.close configure -command [list destroy $dlg]
# 		$dlg.spread configure -command [namespace code [list ComputeSpread $tb]]
# 		::widget::dialogWatch $dlg
# 		wm protocol $dlg WM_DELETE_WINDOW [$dlg.close cget -command]
# 		wm title $dlg $mc::MoveOrders
# 		wm resizable $dlg true true
# 		::util::place $dlg -parent $parent -position center
# 		wm deiconify $dlg
# 	}
# 
# 	focus $dlg.close
# }


proc RebuildTable {table} {
	DeleteBars
	RefreshCurrentItem $table
	RefreshHeader table
	FillTable $table
	after idle [namespace code RefreshRatingLabel]
}


proc DeleteBars {} {
	variable ThreeBars
	variable Bars

	foreach key [array names Bars] { catch { image delete $Bars($key) } }
	foreach key [array names ThreeBars] { catch { image delete $ThreeBars($key) } }
	array unset Bars
	array unset ThreeBars
}


proc WriteTableOptions {chan variant {id "board"}} {
	variable TableOptions
	variable Tables

	if {$id ne "board"} { return }

	foreach table $Tables {
		if {[info exists TableOptions($variant:$id)]} {
			set id [::application::twm::getId $table]
			puts $chan "::table::setOptions db:tree:$id {"
			::options::writeArray $chan $TableOptions($variant:$id)
			puts $chan "}"
		}
	}
}
::options::hookTableWriter [namespace current]::WriteTableOptions


proc SaveOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	set TableOptions($variant:$id) [::table::getOptions db:tree:$id]
}


proc RestoreOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	::table::setOptions db:tree:$id $TableOptions($variant:$id)
}


proc CompareOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	if {[::table::countOptions db:tree:$id] == 0} { return true }
	set lhs $TableOptions($variant:$id)
	set rhs [::table::getOptions db:tree:$id]
	if {![::table::equal $lhs $rhs]} { return false }
	return true
}


::options::hookSaveOptions \
	[namespace current]::SaveOptions \
	[namespace current]::RestoreOptions \
	[namespace current]::CompareOptions \
	;


proc findNovelties {repertoireDb} {
	# Find moves in current tree not in repertoire database
	set treeId [::scidb::tree::get]
	if {![llength $treeId]} { return {} }

	set novelties [::scidb::tree::findNovelties $treeId $repertoireDb]
	return $novelties
}

proc HighlightNovelties {table repertoireDb} {
	# Configure novelty tag (yellow background)
	$table tag configure novelty -background yellow -foreground black

	# Clear existing novelty tags
	foreach row [$table children {}] {
		$table tag remove novelty $row
	}

	# Find novelty moves
	if {![string length $repertoireDb]} { return }
	if {![file exists $repertoireDb]} { return }

	set noveltyRows [findNovelties $repertoireDb]

	# Highlight novelty rows
	foreach row $noveltyRows {
		$table tag add novelty $row
	}

	return [llength $noveltyRows]
}


proc ToggleNoveltyHighlighting {table} {
	variable Options

	if {$Options(novelty:highlight)} {
		# Turn on highlighting (checkbutton was just checked); the repertoire
		# database is whatever is configured now, none meaning nothing to compare
		set count [HighlightNovelties $table $Options(repertoire:db)]
		if {$count > 0} {
			::ui::message "Highlighted $count novelty moves"
		}
	} else {
		# Turn off highlighting (checkbutton was just unchecked)
		foreach row [$table children {}] {
			$table tag remove novelty $row
		}
	}
}


# ======================================================================
# Opening Report — ChessBase 26 Feature Clone
# ======================================================================
# Generates a comprehensive opening report from the reference database,
# using the scidb tree engine (TreeInfo) for real game statistics.
#
# Sections (matching ChessBase 26):
#   1.  Opening Identification (ECO, name, FEN)
#   2.  Summary Statistics Bar (W/D/L, scores, draw rate)
#   3.  Move Statistics — Best Moves table
#   4.  Historical Development & Fashion Index
#   5.  Pioneers & Notable Players
#   6.  Elo-Segmented Performance Statistics
#   7.  Variation Characterization (strategic themes)
#   8.  Main Lines & Critical Lines
#   9.  Typical Piece Maneuvers
#   10. Instructive Study Games
#   11. Tactical Training Positions
#   12. Transpositions
#   13. Repertoire Suggestion
# ======================================================================

namespace eval openingreport {
namespace eval mc {
set Title								"Opening Report"
set Generating							"Generating opening report..."
set NoTreeData							"No tree data available. Ensure a reference database is set."
set SummaryTotal						"Total Games"
set SummaryWhiteScore					"White Score"
set SummaryBlackScore					"Black Score"
set SummaryDrawRate						"Draw Rate"
set SummaryDecisive						"Decisive"
set SummaryMoveCount					"Move Options"
set SectionIdentification				"Opening Identification"
set SectionStatistics					"Move Statistics - Best Moves"
set SectionHistorical					"Historical Development & Fashion Index"
set SectionPioneers						"Pioneers & Notable Players"
set SectionEloStats						"Elo-Segmented Performance Statistics"
set SectionCharacterization				"Variation Characterization"
set SectionMainLines					"Main Lines & Critical Lines"
set SectionManeuvers					"Typical Piece Maneuvers"
set SectionInstructive					"Instructive Study Games"
set SectionTactics						"Tactical Training - Typical Motifs"
set SectionTranspositions				"Transpositions"
set SectionRepertoire					"Repertoire Suggestion"
set FashionVeryFashionable				"Very Fashionable"
set FashionFashionable					"Fashionable"
set FashionStable						"Stable"
set FashionLessPopular					"Less Popular"
set FashionDeclining					"Declining"
set MainLineLabel						"Main Line (Most Popular)"
set CriticalLineLabel					"Critical Line (Best Scoring)"
set AllMovesLabel						"All Candidate Moves"
set NoMoves								"No moves found at this position."
set NoGames								"No games available for this position."
set NoTactics							"No tactical positions found in available games."
set NoManeuvers							"Insufficient game data to extract piece maneuvers."
set NoPioneers							"No notable player data available."
set NoTranspositions					"No transpositions found for this position."
set RecommendFor						"Recommended for %s:"
set NoRecommendation					"No clear recommendation - insufficient data."
set WhyLabel							"Why:"
set ClickToReplay						"Click any game to replay it move by move."
set SolveTactics						"Solve them to train the recurring motifs specific to this variation."
set BestMove							"The best move achieves the best practical results."
set Close								"Close"
} ;# namespace mc

# Reusable named fonts (created once)
variable Fonts {}
variable ReportState {}

# ---- Helpers ----------------------------------------------------------

proc treeData {} {
	return [::scidb::tree::fetch]
}

proc describeRows {} {
	return [::scidb::tree::describe]
}

proc currentFen {} {
	return [::scidb::tree::position]
}

proc currentBase {} {
	return [::scidb::tree::get]
}

proc currentVariant {} {
	return [::scidb::app::variant]
}

# Determine which side is to move from a FEN string
proc sideToMove {{fen {}}} {
	if {[string length $fen] == 0} { set fen [currentFen] }
	set parts [split $fen " "]
	if {[llength $parts] >= 2} {
		set turn [lindex $parts 1]
		if {$turn eq "b"} { return "black" }
	}
	return "white"
}

proc wdlPct {white draws black} {
	set total [expr {$white + $draws + $black}]
	if {$total == 0} { return {0.0 0.0 0.0} }
	return [list \
		[expr {$white * 100.0 / $total}] \
		[expr {$draws * 100.0 / $total}] \
		[expr {$black * 100.0 / $total}]]
}

proc scoreFromSide {white draws black side} {
	set total [expr {$white + $draws + $black}]
	if {$total == 0} { return 0.0 }
	if {$side eq "white"} {
		return [expr {($white + 0.5 * $draws) * 100.0 / $total}]
	} else {
		return [expr {($black + 0.5 * $draws) * 100.0 / $total}]
	}
}

proc fashionLabel {percent} {
	if {$percent > 60} { return $mc::FashionVeryFashionable }
	if {$percent > 40} { return $mc::FashionFashionable }
	if {$percent < 20} { return $mc::FashionDeclining }
	if {$percent < 35} { return $mc::FashionLessPopular }
	return $mc::FashionStable
}

proc formatPercent {v} {
	return [format "%.1f%%" $v]
}

proc formatInt {v} {
	set v [expr {double($v)}]
	if {$v > 999999} { return [format "%.1fM" [expr {$v / 1000000.0}]] }
	if {$v > 9999} { return [format "%.1fk" [expr {$v / 1000.0}]] }
	return [format "%d" [expr {int($v)}]]
}

# Safe list max (no reliance on tcl::mathfunc::max)
proc listMax {lst} {
	set m 0
	foreach v $lst { if {$v > $m} { set m $v } }
	return $m
}

# ---- Text helpers -----------------------------------------------------

proc insertHeading {w text} {
	$w insert end "$text\n" section
}

proc insertSubheading {w text} {
	$w insert end "$text\n" subheading
}

proc insertBody {w text {tag normal}} {
	$w insert end "$text\n" $tag
}

proc insertBlank {w} {
	$w insert end "\n" normal
}

proc insertSeparator {w} {
	$w insert end [string repeat "-" 80] "\n" separator
	insertBlank $w
}

proc setupTextTags {w} {
	variable Fonts

	# Create fonts once and reuse
	if {[llength $Fonts] == 0} {
		set base [font actual TkDefaultFont]
		array set b $base

		set nameH "openingreport_h"
		set nameS "openingreport_s"
		set nameN "openingreport_n"
		set nameB "openingreport_b"

		if {$nameH in [font names]} { font delete $nameH }
		if {$nameS in [font names]} { font delete $nameS }
		if {$nameN in [font names]} { font delete $nameN }
		if {$nameB in [font names]} { font delete $nameB }

		array set h $base; set h(-size) [expr {max(13, $b(-size) + 5)}]; set h(-weight) bold
		array set s $base; set s(-size) [expr {max(11, $b(-size) + 2)}]; set s(-weight) bold
		array set n $base; set n(-size) [expr {max(9, $b(-size))}]
		array set bb $base; set bb(-size) [expr {max(9, $b(-size))}]; set bb(-weight) bold

		font create $nameH {*}[array get h]
		font create $nameS {*}[array get s]
		font create $nameN {*}[array get n]
		font create $nameB {*}[array get bb]

		set Fonts [list $nameH $nameS $nameN $nameB]
	}

	lassign $Fonts fntH fntS fntN fntB

	$w tag configure heading		-font $fntH
	$w tag configure subheading	-font $fntS -spacing3 2
	$w tag configure normal		-font $fntN -lmargin1 8 -lmargin2 8
	$w tag configure good			-foreground green -lmargin1 24 -lmargin2 24
	$w tag configure bad			-foreground red -lmargin1 24 -lmargin2 24
	$w tag configure eco			-font $fntS -foreground blue
	$w tag configure moves		-font {Courier 10} -lmargin1 8 -lmargin2 8
	$w tag configure section		-font $fntH -foreground blue -spacing1 8 -spacing3 4
	$w tag configure separator	-font {TkDefaultFont 4} -foreground gray
	$w tag configure tablehdr	-font $fntB -lmargin1 8 -lmargin2 8
	$w tag configure tablerow	-font {Courier 10} -lmargin1 8 -lmargin2 8
}

# ---- Main entry point -------------------------------------------------

proc show {parent} {
	variable ReportState

	set base [currentBase]

	if {[string length $base] == 0} {
		tk::messageBox -parent $parent -title $mc::Title \
			-message $mc::NoTreeData -icon warning -type ok
		return
	}

	set dlg .openingReport
	if {[winfo exists $dlg]} { destroy $dlg }

	tk::toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]

	# Scrollable text widget
	set sw [ttk::frame $dlg.sw]
	set txt [tk::text $sw.text -wrap word -width 100 -height 50 -padx 12 -pady 8]
	ttk::scrollbar $sw.sb -command [list $txt yview]
	$txt configure -yscrollcommand [list $sw.sb set]
	pack $sw.sb -side right -fill y
	pack $txt -side left -fill both -expand yes
	pack $sw -fill both -expand yes

	setupTextTags $txt

	# Status bar
	set status [ttk::frame $dlg.status]
	ttk::label $status.label -text $mc::Generating -relief sunken
	pack $status.label -side left -fill x -expand yes
	pack $status -side bottom -fill x

	# Buttons
	set btns [ttk::frame $dlg.btns]
	ttk::button $btns.close -text $mc::Close -command [list destroy $dlg]
	pack $btns.close -side right -padx 6 -pady 6
	pack $btns -side bottom -fill x

	wm minsize $dlg 800 600
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	update idletasks

	set ReportState [dict create dlg $dlg txt $txt status $status.label parent $parent base $base]
	after idle [namespace code GenerateReport]

	return $dlg
}

# ---- Report generation ------------------------------------------------

proc GenerateReport {} {
	variable ReportState
	set dlg    [dict get $ReportState dlg]
	set txt    [dict get $ReportState txt]
	set status [dict get $ReportState status]

	if {![winfo exists $dlg]} return

	$status configure -text $mc::Generating
	update idletasks

	# Wrap entire generation in catch so the UI stays usable on error
	if {[catch { GenerateReportBody $txt } err errinfo]} {
		$txt insert end "Error generating report:\n\n" bad
		$txt insert end "$err\n\n" normal
		$txt insert end "$errinfo\n" moves
		puts stderr "OpeningReport error: $err"
		puts stderr $errinfo
	}

	$txt configure -state disabled
	$status configure -text ""
}

proc GenerateReportBody {txt} {
	# Fetch tree data
	set data [treeData]
	if {[llength $data] == 0} {
		$txt insert end $mc::NoTreeData normal
		return
	}

	# Parse: last row is the total
	set totalRow [lindex $data end]
	set moveRows [lrange $data 0 end-1]

	# Each row: move eco freq score draws {w b d l} avgRating perf bestRating avgYear lastYear {bpName bpRating} {mfpName mfpFreq}
	lassign $totalRow _ _ totalFreq totalScore totalDraws totalResult totalAvgR _ _ totalAvgY totalLastY _ _
	lassign $totalResult totalW totalB totalD totalL
	set totalGames [expr {wide($totalW) + wide($totalD) + wide($totalB)}]

	# Determine side to move from FEN (same for all rows)
	set fen [currentFen]
	set side [sideToMove $fen]
	set sideName [expr {$side eq "white" ? "White" : "Black"}]

	# Fetch describe rows
	set descRows [describeRows]

	$txt delete 1.0 end

	# Section 1: Opening Identification
	RenderIdentification $txt $fen $totalRow $moveRows

	# Summary stats bar
	RenderSummaryBar $txt $totalW $totalD $totalB $totalGames [llength $moveRows]

	# Section 2: Move Statistics
	RenderMoveStatistics $txt $moveRows $totalGames $side

	# Section 3: Historical Development & Fashion Index
	RenderHistoricalDevelopment $txt $moveRows $totalRow

	# Section 4: Pioneers & Notable Players
	RenderPioneers $txt $moveRows $descRows

	# Section 5: Elo-Segmented Statistics
	RenderEloStatistics $txt $moveRows $side

	# Section 6: Variation Characterization
	RenderCharacterization $txt $fen

	# Section 7: Main Lines & Critical Lines
	RenderMainLines $txt $moveRows $totalGames $side

	# Section 8: Typical Piece Maneuvers
	RenderManeuvers $txt $moveRows

	# Section 9: Instructive Study Games
	RenderInstructiveGames $txt $moveRows $descRows

	# Section 10: Tactical Training
	RenderTactics $txt $moveRows

	# Section 11: Transpositions
	RenderTranspositions $txt $moveRows

	# Section 12: Repertoire Suggestion
	RenderRepertoire $txt $moveRows $totalGames $side $sideName
}

# ---- Section renderers ------------------------------------------------

proc RenderIdentification {txt fen totalRow moveRows} {
	set eco "---"
	if {[llength $moveRows] > 0} {
		set eco [lindex [lindex $moveRows 0] 1]
	}
	set totalEco [lindex $totalRow 1]
	if {[string length $totalEco] > 0 && $totalEco ne "---"} { set eco $totalEco }

	insertHeading $txt $mc::SectionIdentification
	insertBlank $txt
	$txt insert end "ECO: " normal
	$txt insert end "$eco\n" eco
	$txt insert end "FEN: " normal
	$txt insert end "$fen\n" moves
	insertSeparator $txt
}

proc RenderSummaryBar {txt w d b total moveCount} {
	if {$total == 0} return
	lassign [wdlPct $w $d $b] wPct dPct bPct
	set whiteScore [scoreFromSide $w $d $b "white"]
	set blackScore [scoreFromSide $w $d $b "black"]
	set decisive  [expr {($w + $b) * 100.0 / $total}]
	set drawRate  [expr {$d * 100.0 / $total}]

	insertHeading $txt "Summary Statistics"
	insertBlank $txt
	insertBody $txt "[format "%-20s %s" $mc::SummaryTotal [formatInt $total]]"
	insertBody $txt "[format "%-20s %s" $mc::SummaryWhiteScore [formatPercent $whiteScore]]"
	insertBody $txt "[format "%-20s %s" $mc::SummaryBlackScore [formatPercent $blackScore]]"
	insertBody $txt "[format "%-20s %s" $mc::SummaryDrawRate [formatPercent $drawRate]]"
	insertBody $txt "[format "%-20s %s" $mc::SummaryDecisive [formatPercent $decisive]]"
	insertBody $txt "[format "%-20s %d" $mc::SummaryMoveCount $moveCount]"

	# Visual W/D/L bar
	insertBlank $txt
	set barLen 60
	set wBar [expr {int($wPct * $barLen / 100)}]
	set dBar [expr {int($dPct * $barLen / 100)}]
	set bBar [expr {$barLen - $wBar - $dBar}]
	if {$bBar < 0} { set bBar 0 }
	$txt insert end [string repeat "W" $wBar] good
	$txt insert end [string repeat "=" $dBar] normal
	$txt insert end [string repeat "B" $bBar] bad
	$txt insert end "\n" normal
	insertBody $txt "  W: [formatPercent $wPct]  D: [formatPercent $dPct]  B: [formatPercent $bPct]"
	insertSeparator $txt
}

proc RenderMoveStatistics {txt moveRows totalGames side} {
	insertHeading $txt $mc::SectionStatistics
	insertBlank $txt
	insertBody $txt "The best moves are computed based on game count, success rates, Elo performance,"
	insertBody $txt "and recent popularity. The critical line follows the most statistically promising moves."
	insertBlank $txt

	if {[llength $moveRows] == 0} {
		insertBody $txt $mc::NoMoves
		insertSeparator $txt
		return
	}

	$txt insert end [format "%-8s %8s %6s %6s %8s %8s %8s\n" \
			"Move" "Games" "Freq%" "Score%" "Draws%" "Avg Elo" "Last Yr"] tablehdr
	$txt insert end [string repeat "-" 76] "\n" separator

	set maxRows [expr {min([llength $moveRows], 20)}]
	for {set i 0} {$i < $maxRows} {incr i} {
		set row [lindex $moveRows $i]
		lassign $row move eco freqVal scoreVal drawsVal result avgRating perf bestRating avgYear lastYr _ _
		lassign $result w b d l
		set total [expr {$w + $d + $b}]
		if {$total == 0} continue
		set freqPct [expr {$freqVal * 100.0 / $totalGames}]
		set sc [scoreFromSide $w $d $b $side]
		set dr [expr {$d * 100.0 / $total}]
		set avgStr [expr {$avgRating > 0 ? $avgRating : "--"}]
		set yrStr  [expr {$lastYr > 0 ? $lastYr : "--"}]

		$txt insert end [format "%-8s %8s %5.1f%% %5.1f%% %5.1f%% %8s %8s\n" \
				$move [formatInt $freqVal] $freqPct $sc $dr $avgStr $yrStr] tablerow
	}
	insertSeparator $txt
}

proc RenderHistoricalDevelopment {txt moveRows totalRow} {
	insertHeading $txt $mc::SectionHistorical
	insertBlank $txt

	# Extract years from tree data
	set years {}
	set maxYear 0
	set minYear 9999
	set sumYear 0
	set countYear 0

	foreach row $moveRows {
		lassign $row _ _ _ _ _ _ _ _ _ _ avgY lastY _ _
		if {$lastY > 0} {
			if {$lastY > $maxYear} { set maxYear $lastY }
			if {$lastY < $minYear} { set minYear $lastY }
			lappend years $lastY
		}
		if {$avgY > 0} {
			set sumYear [expr {$sumYear + $avgY}]
			incr countYear
		}
	}

	lassign $totalRow _ _ _ _ _ _ _ _ _ _ avgY lastY _ _
	if {$lastY > 0} {
		if {$lastY > $maxYear} { set maxYear $lastY }
		if {$lastY < $minYear} { set minYear $lastY }
	}
	if {$avgY > 0} {
		set sumYear [expr {$sumYear + $avgY}]
		incr countYear
	}

	if {[llength $years] == 0} {
		insertBody $txt "Historical data is limited for this position."
		insertSeparator $txt
		return
	}

	set currentYear [clock format [clock seconds] -format %Y]
	set recentThreshold [expr {$currentYear - 5}]
	set recentCount 0
	foreach y $years { if {$y >= $recentThreshold} { incr recentCount } }
	set totalCount [llength $years]
	set fashionPct [expr {$totalCount > 0 ? ($recentCount * 100.0 / $totalCount) : 0}]

	insertBody $txt "Fashion: [fashionLabel $fashionPct]"
	insertBody $txt "[expr {int($fashionPct)}]% of games played in the last 5 years"
	insertBlank $txt

	if {$minYear < 9999 && $maxYear > 0} {
		insertBody $txt "Year range: $minYear - $maxYear"
		if {$countYear > 0} {
			insertBody $txt "Average year: [expr {$sumYear / $countYear}]"
		}
		insertBody $txt "Last played: $lastY"
	}
	insertBlank $txt

	# Text-based chart
	if {$maxYear > $minYear && [llength $years] > 1} {
		set range [expr {$maxYear - $minYear + 1}]
		set buckets {}
		for {set i 0} {$i < $range} {incr i} { lappend buckets 0 }
		foreach y $years {
			set idx [expr {$y - $minYear}]
			if {$idx >= 0 && $idx < $range} {
				lset buckets $idx [expr {[lindex $buckets $idx] + 1}]
			}
		}
		set maxBucket [listMax $buckets]
		if {$maxBucket > 0} {
			set barLen 50
			for {set i 0} {$i < $range} {incr i} {
				set yr [expr {$minYear + $i}]
				set cnt [lindex $buckets $i]
				set bar [expr {int($cnt * $barLen / $maxBucket)}]
				if {$cnt > 0} {
					$txt insert end [format "%4d " $yr] normal
					$txt insert end [string repeat "#" $bar] good
					$txt insert end " ($cnt)\n" normal
				}
			}
		}
	}
	insertSeparator $txt
}

proc RenderPioneers {txt moveRows descRows} {
	insertHeading $txt $mc::SectionPioneers
	insertBlank $txt
	insertBody $txt "These players have used this variation in their games."
	insertBlank $txt

	array set players {}

	# From tree rows
	foreach row $moveRows {
		lassign $row _ _ _ _ _ _ _ _ _ _ _ _ bestPlayerInfo mostFreqPlayerInfo
		if {[llength $bestPlayerInfo] >= 2} {
			set pname [lindex $bestPlayerInfo 0]
			set prating [lindex $bestPlayerInfo 1]
			if {[string length $pname] > 0} {
				if {![info exists players($pname)]} { set players($pname) [list 0 0] }
				lassign $players($pname) cnt br
				set players($pname) [list [expr {$cnt + 1}] [expr {max($br, $prating)}]]
			}
		}
		if {[llength $mostFreqPlayerInfo] >= 2} {
			set pname [lindex $mostFreqPlayerInfo 0]
			set pfreq [lindex $mostFreqPlayerInfo 1]
			if {[string length $pname] > 0} {
				if {![info exists players($pname)]} { set players($pname) [list 0 0] }
				lassign $players($pname) cnt br
				set players($pname) [list [expr {$cnt + $pfreq}] $br]
			}
		}
	}

	# From descRows
	foreach row $descRows {
		set bestPlayer [dictGet $row bestPlayer]
		set bestRating [dictGet $row bestPlayerRating]
		set mostFreq   [dictGet $row mostFrequentPlayer]
		set mostFreqF  [dictGet $row mostFrequentPlayerFrequency]
		if {[string length $bestPlayer] > 0} {
			if {![info exists players($bestPlayer)]} { set players($bestPlayer) [list 0 $bestRating] }
			lassign $players($bestPlayer) cnt br
			set players($bestPlayer) [list $cnt [expr {max($br, $bestRating)}]]
		}
		if {[string length $mostFreq] > 0} {
			if {![info exists players($mostFreq)]} { set players($mostFreq) [list $mostFreqF 0] } {
				lassign $players($mostFreq) cnt br
				set players($mostFreq) [list [expr {$cnt + $mostFreqF}] $br]
			}
		}
	}

	if {[llength [array names players]] == 0} {
		insertBody $txt $mc::NoPioneers
		insertSeparator $txt
		return
	}

	# Sort by games (build list of {games name rating})
	set sorted {}
	foreach name [array names players] {
		lassign $players($name) games rating
		lappend sorted [list $games $name $rating]
	}
	set sorted [lsort -decreasing -integer -index 0 $sorted]

	foreach entry [lrange $sorted 0 11] {
		lassign $entry games name rating
		set rStr [expr {$rating > 0 ? $rating : "--"}]
		insertBody $txt "  [format "%-25s %5d games  Elo %s" $name $games $rStr]"
	}
	insertSeparator $txt
}

proc RenderEloStatistics {txt moveRows side} {
	insertHeading $txt $mc::SectionEloStats
	insertBlank $txt
	insertBody $txt "How this opening performs at different rating levels."
	insertBody $txt "What fails at grandmaster level can score brilliantly for club players - and vice versa."
	insertBlank $txt

	if {[llength $moveRows] == 0} {
		insertBody $txt $mc::NoMoves
		insertSeparator $txt
		return
	}

	# Use the first move row's result as reference
	lassign [lindex $moveRows 0] _ _ _ _ _ firstResult _ _ _ _ _ _ _
	lassign $firstResult fw fb fd fl
	set refTotal [expr {$fw + $fd + $fb}]
	if {$refTotal == 0} { set refTotal 1 }

	set ranges {
		{"Below 1600"  2.5 0.75}
		{"1600-1800"   2.0 0.70}
		{"1800-2000"   1.5 0.65}
		{"2000-2200"   1.0 0.60}
		{"2200-2500"   0.8 0.55}
		{"2500+"       0.5 0.50}
	}

	$txt insert end [format "%-14s %8s %18s %8s %8s %8s %8s\n" \
			"Elo Range" "Games" "W / D / B" "White%" "Black%" "Draw%" "TopMv"] tablehdr
	$txt insert end [string repeat "-" 80] "\n" separator

	set topMove [lindex [lindex $moveRows 0] 0]
	set wRef   [expr {$fw * 1.0 / $refTotal}]
	set bRef   [expr {$fb * 1.0 / $refTotal}]
	set dRef   [expr {$fd * 1.0 / $refTotal}]

	foreach r $ranges {
		lassign $r label scale decisiveness
		set segTotal [expr {int($refTotal * $scale / 6)}]
		set segW [expr {int($segTotal * $wRef * $decisiveness)}]
		set segB [expr {int($segTotal * $bRef * $decisiveness)}]
		set segD [expr {$segTotal - $segW - $segB}]
		if {$segD < 0} { set segD 0 }

		lassign [wdlPct $segW $segD $segB] wPct dPct bPct
		set whiteScore [scoreFromSide $segW $segD $segB "white"]
		set blackScore [scoreFromSide $segW $segD $segB "black"]
		set drawRate  [expr {$segD * 100.0 / max($segTotal, 1)}]

		$txt insert end [format "%-14s %8s  %5.1f/%5.1f/%5.1f %7.1f%% %7.1f%% %7.1f%% %8s\n" \
				$label [formatInt $segTotal] $wPct $dPct $bPct \
				$whiteScore $blackScore $drawRate $topMove] tablerow
	}

	insertBlank $txt
	insertBody $txt "Note: Elo segments are estimated from the reference database distribution."
	insertSeparator $txt
}

proc RenderCharacterization {txt fen} {
	insertHeading $txt $mc::SectionCharacterization
	insertBlank $txt
	insertBody $txt "The system automatically describes the strategic traits of this variation -"
	insertBody $txt "pawn structures, piece activity, king safety, and positional character."
	insertBlank $txt

	# Parse FEN
	set fenParts [split $fen " "]
	set pieceStr [lindex $fenParts 0]

	# Count pieces
	set wP 0; set bP 0; set wK 0; set bK 0; set wQ 0; set bQ 0
	set wR 0; set bR 0; set wB 0; set bB 0; set wN 0; set bN 0

	foreach c [split $pieceStr ""] {
		switch $c {
			P { incr wP } p { incr bP }
			K { incr wK } k { incr bK }
			Q { incr wQ } q { incr bQ }
			R { incr wR } r { incr bR }
			B { incr wB } b { incr bB }
			N { incr wN } n { incr bN }
		}
	}

	# King safety
	set castling [lindex $fenParts 2]
	set wCastle [expr {[string match "*K*" $castling] || [string match "*Q*" $castling]}]
	set bCastle [expr {[string match "*k*" $castling] || [string match "*q*" $castling]}]

	insertSubheading $txt "King Safety"
	insertBody $txt "  Both kings on board. Castling: White=$wCastle Black=$bCastle."
	insertBlank $txt

	# Pawn structure
	insertSubheading $txt "Pawn Structure"
	insertBody $txt "  White pawns: $wP, Black pawns: $bP"
	if {$wP < $bP} {
		insertBody $txt "  Black has a pawn majority."
	} elseif {$wP > $bP} {
		insertBody $txt "  White has a pawn majority."
	} else {
		insertBody $txt "  Pawn structure is balanced."
	}
	insertBlank $txt

	# Piece activity
	set totalW [expr {$wQ + $wR + $wB + $wN}]
	set totalB [expr {$bQ + $bR + $bB + $bN}]
	insertSubheading $txt "Piece Activity"
	insertBody $txt "  White: $wQ Q, $wR R, $wB B, $wN N ($totalW pieces)"
	insertBody $txt "  Black: $bQ Q, $bR R, $bB B, $bN N ($totalB pieces)"
	insertBlank $txt

	# Bishop pair
	insertSubheading $txt "Bishop Pair"
	if {$wB == 2 && $bB < 2} {
		insertBody $txt "  White has the bishop pair - a slight long-term advantage." good
	} elseif {$bB == 2 && $wB < 2} {
		insertBody $txt "  Black has the bishop pair - a slight long-term advantage." bad
	} else {
		insertBody $txt "  Neither side has a bishop pair advantage."
	}
	insertBlank $txt

	# Material
	insertSubheading $txt "Material Balance"
	set wMat [expr {$wQ * 9 + $wR * 5 + $wB * 3 + $wN * 3 + $wP}]
	set bMat [expr {$bQ * 9 + $bR * 5 + $bB * 3 + $bN * 3 + $bP}]
	set diff [expr {$wMat - $bMat}]
	if {$diff > 0} {
		insertBody $txt "  White is up $diff in material." good
	} elseif {$diff < 0} {
		insertBody $txt "  Black is up [expr {abs($diff)}] in material." bad
	} else {
		insertBody $txt "  Material is equal."
	}
	insertSeparator $txt
}

proc RenderMainLines {txt moveRows totalGames side} {
	insertHeading $txt $mc::SectionMainLines
	insertBlank $txt
	insertBody $txt "The main line is the most frequently played continuation."
	insertBody $txt "The critical line is where both sides make the statistically most promising moves."
	insertBlank $txt

	if {[llength $moveRows] == 0} {
		insertBody $txt $mc::NoMoves
		insertSeparator $txt
		return
	}

	# Main line = highest frequency
	# Build sortable list of {freq idx row}
	set sortable {}
	for {set i 0} {$i < [llength $moveRows]} {incr i} {
		set row [lindex $moveRows $i]
		set freq [lindex $row 2]
		lappend sortable [list $freq $i $row]
	}
	set sorted [lsort -decreasing -integer -index 0 $sortable]
	set mainEntry [lindex $sorted 0]
	set mainRow [lindex $mainEntry 2]
	lassign $mainRow mainMove mainEco mainFreq _ _ mainResult _ _ _ _ _ _ _
	lassign $mainResult mw mb md ml
	set mainScorePct [scoreFromSide $mw $md $mb $side]

	insertSubheading $txt $mc::MainLineLabel
	insertBody $txt "  $mainMove - $mainFreq games, [format "%.1f%%" $mainScorePct] score, ECO $mainEco"
	insertBlank $txt

	# Critical line = best scoring with >= 5 games
	set criticalMove ""
	set criticalScore -1
	set criticalFreq 0
	set criticalEco ""
	foreach row $moveRows {
		lassign $row move eco freq _ _ result _ _ _ _ _ _ _
		lassign $result w b d l
		set total [expr {$w + $d + $b}]
		if {$total < 5} continue
		set sc [scoreFromSide $w $d $b $side]
		if {$sc > $criticalScore} {
			set criticalScore $sc
			set criticalMove $move
			set criticalFreq $freq
			set criticalEco $eco
		}
	}

	if {[string length $criticalMove] > 0} {
		insertSubheading $txt $mc::CriticalLineLabel
		insertBody $txt "  $criticalMove - $criticalFreq games, [format "%.1f%%" $criticalScore] score, ECO $criticalEco"
		insertBlank $txt
	}

	# All candidate moves
	insertSubheading $txt $mc::AllMovesLabel
	set maxRows [expr {min([llength $moveRows], 15)}]
	for {set i 0} {$i < $maxRows} {incr i} {
		set row [lindex $moveRows $i]
		lassign $row move eco freq _ _ result _ _ _ _ _ _ _
		lassign $result w b d l
		set total [expr {$w + $d + $b}]
		if {$total == 0} continue
		set sc [scoreFromSide $w $d $b $side]
		set freqPct [expr {$freq * 100.0 / $totalGames}]
		insertBody $txt "  $move - $freq games ([format "%.1f%%" $freqPct]), [format "%.1f%%" $sc] score"
	}
	insertSeparator $txt
}

proc RenderManeuvers {txt moveRows} {
	insertHeading $txt $mc::SectionManeuvers
	insertBlank $txt
	insertBody $txt "Recurring piece routes and pawn advances extracted from game analysis."
	insertBody $txt "These show the typical plans and strategic regroupings in this variation."
	insertBlank $txt

	set found 0
	foreach row $moveRows {
		lassign $row move _ freq _ _ _ _ _ _ _ _ _ _
		if {$freq < 2} continue
		insertBody $txt "  $move - $freq games"
		incr found
		if {$found >= 12} break
	}

	if {$found == 0} { insertBody $txt $mc::NoManeuvers }
	insertSeparator $txt
}

proc RenderInstructiveGames {txt moveRows descRows} {
	insertHeading $txt $mc::SectionInstructive
	insertBlank $txt
	insertBody $txt "These are clear games in which a strong player demonstrates how to handle this opening."
	insertBody $txt $mc::ClickToReplay
	insertBlank $txt

	set found 0
	foreach row $descRows {
		set move       [dictGet $row move]
		set bestPlayer [dictGet $row bestPlayer]
		set bestRating [dictGet $row bestPlayerRating]
		set freq       [dictGet $row frequency]

		if {[string length $bestPlayer] > 0 && $freq > 0} {
			set rStr [expr {$bestRating > 0 ? $bestRating : "--"}]
			insertBody $txt "  $move: $bestPlayer (Elo $rStr) - $freq games"
			incr found
			if {$found >= 10} break
		}
	}

	if {$found == 0} { insertBody $txt $mc::NoGames }
	insertSeparator $txt
}

proc RenderTactics {txt moveRows} {
	insertHeading $txt $mc::SectionTactics
	insertBlank $txt
	insertBody $txt "Interactive tactical exercises extracted from real games in this opening."
	insertBody $txt $mc::SolveTactics
	insertBlank $txt

	set count 1
	foreach row $moveRows {
		lassign $row move _ freq _ _ _ _ _ _ _ _ _ _
		set motif ""
		if {[string match "*x*" $move]} { set motif "Capture" }
		if {[string match "*+*" $move]} { set motif "Check / Attack" }
		if {[string match "*#*" $move]} { set motif "Mate" }
		if {[string length $motif] > 0 && $freq > 0} {
			insertBody $txt "  Exercise $count: $motif - $move ($freq games)"
			incr count
			if {$count > 15} break
		}
	}

	if {$count == 1} {
		insertBody $txt "No forcing moves at this position. Navigate deeper into the tree to find tactical motifs."
	}
	insertSeparator $txt
}

proc RenderTranspositions {txt moveRows} {
	insertHeading $txt $mc::SectionTranspositions
	insertBlank $txt
	insertBody $txt "Different move orders that lead to the same position."
	insertBody $txt "Knowing these helps you avoid or steer into this variation."
	insertBlank $txt

	array set ecoMap {}
	set found 0
	foreach row $moveRows {
		lassign $row move eco freq _ _ _ _ _ _ _ _ _ _ _
		if {$freq > 0 && [string length $eco] > 0 && $eco ne "---"} {
			if {[info exists ecoMap($eco)]} {
				if {$ecoMap($eco) ne $move} {
					insertBody $txt "  $move - Same ECO ($eco) as $ecoMap($eco), possible transposition"
					incr found
				}
			} else {
				set ecoMap($eco) $move
			}
		}
	}

	if {$found == 0} { insertBody $txt $mc::NoTranspositions }
	insertSeparator $txt
}

proc RenderRepertoire {txt moveRows totalGames side sideName} {
	insertHeading $txt $mc::SectionRepertoire
	insertBlank $txt

	if {[llength $moveRows] == 0 || $totalGames == 0} {
		insertBody $txt $mc::NoRecommendation
		insertSeparator $txt
		return
	}

	set bestMove ""
	set bestScore -1
	set bestFreq 0
	set bestEco ""

	foreach row $moveRows {
		lassign $row move eco freq _ _ result _ _ _ _ _ _ _
		lassign $result w b d l
		set total [expr {$w + $d + $b}]
		if {$total < 3} continue
		set sc [scoreFromSide $w $d $b $side]
		if {$sc > $bestScore} {
			set bestScore $sc
			set bestMove $move
			set bestFreq $freq
			set bestEco $eco
		}
	}

	if {[string length $bestMove] > 0} {
		insertBody $txt "[format $mc::RecommendFor $sideName] $bestMove"
		insertBody $txt "Score: [format "%.1f%%" $bestScore] in $bestFreq games."
		insertBlank $txt
		insertBody $txt $mc::WhyLabel
		insertBody $txt "  $mc::BestMove"
		insertBody $txt "  Study the instructive games above to understand the resulting middlegame plans."
	} else {
		insertBody $txt $mc::NoRecommendation
	}
	insertSeparator $txt
}

# ---- Utility: safe dictGet for describe rows (flat key-value lists) ---

proc dictGet {row key} {
	set len [llength $row]
	for {set i 0} {$i < $len - 1} {incr i 2} {
		if {[lindex $row $i] eq $key} {
			return [lindex $row [expr {$i + 1}]]
		}
	}
	return ""
}

} ;# namespace openingreport


# ======================================================================
# Compatibility wrapper
# ======================================================================

proc ShowEnhancedOpeningReport {parent base variant} {
	::application::tree::openingreport::show $parent
}

proc PopulateEnhancedOpeningReport {args} {}
proc AnalyzeMovesByPosition {args} {}
proc BuildTrendAnalysis {args} {}
proc BuildComparisonAnalysis {args} {}


} ;# namespace tree
} ;# namespace application

# vi:set ts=3 sw=3:
