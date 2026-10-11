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
# Copyright: (C) 2012-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source player-card

namespace eval playercard {
namespace eval mc {

set PlayerCard					"Player Card"
set Latest						"Latest"
set Highest						"Highest"
set Minimal						"Minimal"
set Maximal						"Maximal"
set Win							"Win"
set Draw							"Draw"
set Loss							"Loss"
set Total						"Total"
set FirstGamePlayed			"First game played"
set LastGamePlayed			"Last game played"
set WhiteMostPlayed			"Most common openings as White"
set BlackMostPlayed			"Most common openings as Black"

set OpenPlayerCard			"%s player card"
set OpenFileCard				"%s file card"
set OpenFideRatingHistory	"FIDE rating history"
set OpenWikipedia				"Wikipedia biographie"
set OpenViafCatalog			"VIAF catalog"
set OpenPndCatalog			"catalog of Deutsche Nationalbibliothek"
set OpenChessgames			"chessgames.com collection"
set SeachIn365ChessCom		"Search in 365Chess.com"

set Photo						"Photo"
set ChoosePhoto				"Choose..."
set NoPhoto						"(none)"
set ThisIsMe					"This is me"
set PrivateCard				"Private card"
set PrivateCardNote			"Entered by you; kept on this computer, never written into a database."
set NameMissing				"A private card needs the player's name, as written in the games."
set FromRatingList			"From rating list"
set NotInRatingList			"No player '%s' is in the rating lists. Update them under Extras, or check the spelling or the FIDE ID."

}

namespace import ::tcl::mathfunc::abs
namespace import ::tcl::mathfunc::max

array set Options {
	debug:log	0
	debug:html	0

	url:fide			"http://ratings.fide.com/card.phtml?event=%id%"
	url:iccf			"http://www.iccf-webchess.com/PlayerDetails.aspx?id=%id%"
	url:uscf			"http://main.uschess.org/assets/msa_joomla/MbrDtlMain.php?%id%"
	url:dsb			"http://www.schachbund.de/dwz/db/spieler.html?zps=%id%&amp;unloadcache=1"
	url:ecf			"http://grading.bcfservices.org.uk/getref.php?ref=%id%"
	url:viaf			"http://viaf.org/viaf/%id%"
	url:pnd			"http://d-nb.info/gnd/%id%"
	url:wikipedia	"http://%lang%.wikipedia.org/wiki/%name%"
	url:chessgames	"http://chessgames.com/player/%id%.html"
	url:365Chess	"http://www.365chess.com/search_result.php?wlname=%lastname%&wname=%firstname%&open=&blname=&bname=&eco=&nocolor=on&yeari=&yeare=&sply=1&ply=&res=&submit_search=1"
}

set Counter 0
set Photo ""
array set ImageCache {}


proc show {base variant args} {
	variable Vars
	variable Options
	variable Counter

	set info [::scidb::db::playerInfo $base $variant {*}$args]
	set key [MakeKey $base $variant $info]
	if {[string length $key] == 0} { return }
	set name [lindex $info 0]

	if {[info exists Vars($key)]} {
		if {$Vars($key:open)} {
			::widget::dialogRaise $Vars($key)
		} else {
			set Vars($key:open) 1
			set id [::scidb::db::get playerKey $base $variant {*}$args]
			UpdateContent $Vars($key).content $id $key $base $variant $name $args
		}
		return
	}

	::widget::busyCursor on

	::scidb::db::subscribe dbInfo {} [list [namespace current]::Close $key]
	set dlg [tk::toplevel .application.__card__[incr Counter] -class Scidb]
	set Vars($key) $dlg
	set Vars($key:open) 1
	bind $dlg <Destroy> [namespace code [list Destroy $dlg $key %W 1]]
	wm withdraw $dlg

	::font::html::setupFonts playercard
	set css [DefaultCSS]
	set dir [file join $::scidb::dir::share scripts]
	set html $dlg.content
	::html $html \
		-fontsize [::font::html::fontSize playercard] \
		-imagecmd [namespace code [list GetImage $info]] \
		-center no \
		-fittowidth yes \
		-height 600 \
		-width 800 \
		-cursor standard \
		-borderwidth 1 \
		-relief sunken \
		-doublebuffer yes \
		-exportselection yes \
		-importdir $dir \
		-css $css \
		-showhyphens no \
		-usehorzscroll no \
		-usevertscroll yes \
		-keepvertscroll yes \
		;
	bind [winfo parent [$html drawable]] <ButtonPress-3> [namespace code [list PopupMenu $key]]
	::font::html::addChangeFontSizeBindings playercard $dlg [list $html fontsize]
	bind $html <<FontSizeChanged>> [namespace code [list FontSizeChanged %W $html $key]]
	pack $html -fill both -expand yes
	bind $html <Destroy> [list array unset [namespace current]::Vars $key*]
	set id [::scidb::db::get playerKey $base $variant {*}$args]
	set arguments [list $html $id $key $base $variant $name $args]
	set updateCmd [list UpdatePlayer {*}$arguments]
	bind $html <<LanguageChanged>> [namespace code $updateCmd]
	$html onmouseover [namespace code [list MouseEnter $dlg.content $variant]]
	$html onmouseout [namespace code [list MouseLeave $dlg.content]]
	$html onmousedown3 [namespace code [list Mouse3Down $dlg.content $key $info]]
	set Vars($html:tooltip) ""
	set Vars(lock) 0
	set Vars($key:arguments) $arguments

	set geometry [UpdateContent {*}$arguments]
	::widget::busyCursor off

	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm resizable $dlg false true
	wm geometry $dlg $geometry
	wm deiconify $dlg

	return $dlg
}


proc popupInfo {path info} {
	variable Photo

	set info [WithPrivate $info]
	lassign $info name fideID type sex rating _ _ country titles _ _ dateOfBirth dateOfDeath
	if {[string length $name] == 0} { return }
	if {[string index $fideID 0] eq "-"} { set fideID [string range $fideID 1 end] }

	set w $path.showinfo
	catch { destroy $w }
	set top [::util::makePopup $w]
	set bg [$top cget -background]

	set f [tk::frame $top.f -borderwidth 0 -background $bg]
	grid $f -column 3 -row 1

	lassign $rating highestRating mostRecentRating ratingType
	set highestRating [abs $highestRating]
	set mostRecentRating [max 0 $mostRecentRating]
	set dateOfBirth [::locale::formatDate $dateOfBirth]
	set dateOfDeath [::locale::formatDate $dateOfDeath]
	switch $sex {
		m			{ set sex $::genderbox::mc::Gender(m) }
		f			{ set sex $::genderbox::mc::Gender(f) }
		default	{ set sex "" }
	}
	set federation [::country::name $country]
	if {$type eq "program"} {
		set title $::genderbox::mc::Gender(c)
	} else {
		set title ""
	}
	foreach t $titles {
		if {[string length $title]} { append title "\n" }
		append title $::titlebox::mc::Title($t)
	}
	set row 1
	foreach var {	name sex dateOfBirth dateOfDeath highestRating
						mostRecentRating title federation fideID} {
		set value [set $var]
		if {[string length $value] <= 1} {
			set value "\u2013"
		} elseif {$var in {highestRating mostRecentRating} && $ratingType ne "Rating"} {
			append value " ($ratingType)"
		}
		set attr [string toupper $var 0 0]
		if {[info exists ::playertable::mc::T_$attr]} {
			set text [set ::playertable::mc::T_$attr]
		} elseif {[info exists ::playertable::mc::F_$attr]} {
			set text [set ::playertable::mc::F_$attr]
		} else {
			set text [set ::playertable::mc::$attr]
		}
		tk::label $f.lbl$row -background $bg -text "$text:"
		tk::label $f.val$row -background $bg -text $value -justify left
		grid $f.lbl$row -row $row -column 3 -sticky nw
		grid $f.val$row -row $row -column 5 -sticky w
#		grid rowconfigure $f [expr {$row + 1}] -minsize $::theme::padding
		incr row 2
	}
	grid columnconfigure $f 4 -minsize $::theme::padding
	grid columnconfigure $f {2 6} -minsize 2
	grid rowconfigure $f [list 0 [incr row -1]] -minsize 2

	set Photo [::util::photos::get $name $info]
	if {[string length $Photo]} {
		tk::frame $top.lt -background $bg -borderwidth 0
		set lbl [tk::label $top.lt.photo -background $bg -image $Photo -relief solid]
		grid $lbl -column 1 -row 1
	}

	set icon [::country::countryFlag $country]
	if {[llength $icon]} {
		if {![winfo exists $top.lt]} { tk::frame $top.lt -background $bg -borderwidth 0 }
		set lbl [tk::label $top.lt.flag -background $bg -image $icon -borderwidth 0]
		grid $lbl -column 1 -row 3 -sticky n
	}

	if {[winfo exists $top.lt]} {
		grid $top.lt -column 1 -row 1
		grid columnconfigure $top 0 -minsize 2
		grid columnconfigure $top 2 -minsize $::theme::padding
		grid rowconfigure $top {0 2} -minsize 2

		if {[winfo exists $top.lt.photo] && [winfo exists $top.lt.flag]} {
			grid rowconfigure $top.lt 2 -minsize 3
		}
	}

	::tooltip::popup $path $w cursor
}


proc popdownInfo {path} {
	variable Photo

	if {[string length $Photo]} {
		image delete $Photo
		set Photo ""
	}
	::tooltip::popdown $path.showinfo
}


proc setupPrivateCard {parent} {
	variable Var

	# Name
	# Sex
	# Birthday
	# Actual Rating
	# Title
	# Nation
	# Fide-ID (6-8 digits) / DSB-ID "<zps>-<nr>" / ECF-ID (6 digits + 1 alpha) / ICCF-ID (6 digits)
	# Photo

	set dlg $parent.setupPrivateCard
	tk::toplevel $dlg -class Scidb
	wm withdraw $dlg
	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes

	### left frame ########################################################
	set list [::tlistbox $top.select \
		-usescroll yes \
		-padx 5 \
		-pady 7 \
		-selectmode browse \
		-height 16 \
	]
	$list addcol text -id name -width 24
	bind $list <<ListboxSelect>> [namespace code [list SelectPlayer $list %d]]

	### right frame #######################################################
	set f [ttk::frame $top.data -borderwidth 0 -takefocus 0]

	ttk::label		$f.lname -textvar ::engine::mc::Name
	ttk::entry		$f.ename -textvar [namespace current]::Var(Name)
	ttk::label		$f.lsex -textvar ::playertable::mc::T_Sex
	::genderbox		$f.bsex -textvar [namespace current]::Var(Sex)
	ttk::label		$f.lbirthday -textvar ::playertable::mc::DateOfBirth
	::datebox		$f.bbirthday
	ttk::label		$f.lnation -textvar ::playertable::mc::T_Federation
	::countrybox	$f.bnation -textvar [namespace current]::Var(Nation)

	ttk::label		$f.lrating1 -textvar [::mc::var ::engine::mc::Rating " 1"]
	::ratingbox		$f.brating1 -textvar [namespace current]::Var(Rating1) -format all
	ttk::spinbox	$f.escore1 -textvar [namespace current]::Var(Score1) -width 5 -from 0 -to 4000
	ttk::label		$f.lrating2 -textvar [::mc::var ::engine::mc::Rating " 2"]
	::ratingbox		$f.brating2 -textvar [namespace current]::Var(Rating2) -format all
	ttk::spinbox	$f.escore2 -textvar [namespace current]::Var(Score2) -width 5 -from 0 -to 4000
	ttk::label		$f.lrating3 -textvar [::mc::var ::engine::mc::Rating " 3"]
	::ratingbox		$f.brating3 -textvar [namespace current]::Var(Rating3) -format all
	ttk::spinbox	$f.escore3 -textvar [namespace current]::Var(Score3) -width 5 -from 0 -to 4000

	ttk::label		$f.ltitle1 -textvar [::mc::var ::playertable::mc::F_Title " 1"]
	::titlebox		$f.btitle1 -textvar [namespace current]::Var(Title1)
	ttk::label		$f.ltitle2 -textvar [::mc::var ::playertable::mc::F_Title " 2"]
	::titlebox		$f.btitle2 -textvar [namespace current]::Var(Title2)
	ttk::label		$f.ltitle3 -textvar [::mc::var ::playertable::mc::F_Title " 3"]
	::titlebox		$f.btitle3 -textvar [namespace current]::Var(Title3)

	ttk::label		$f.lfide -textvar ::playertable::mc::F_FideID
	ttk::entry		$f.efide -textvar [namespace current]::Var(FideID)
	ttk::button		$f.bfill -textvar [namespace current]::mc::FromRatingList \
		-command [namespace code [list FillFromLists $dlg]]
	bind $f.efide <Return> [namespace code [list FillFromLists $dlg]]
	ttk::label		$f.ldsb -text "DSB-ID"
	ttk::entry		$f.edsb -textvar [namespace current]::Var(DsbID)
	ttk::label		$f.lecf -text "ECF-ID"
	ttk::entry		$f.eecf -textvar [namespace current]::Var(EcfID)
	ttk::label		$f.liccf -text "ICCF-ID"
	ttk::entry		$f.eiccf -textvar [namespace current]::Var(IccfID)
	ttk::label		$f.luscf -text "USCF-ID"
	ttk::entry		$f.euscf -textvar [namespace current]::Var(UscfID)

	ttk::label		$f.lphoto -textvar [namespace current]::mc::Photo
	ttk::label		$f.vphoto -textvar [namespace current]::Var(PhotoLabel)
	ttk::button		$f.bphoto -textvar [namespace current]::mc::ChoosePhoto \
		-command [namespace code [list ChoosePhoto $dlg]]
	ttk::checkbutton $f.me -textvar [namespace current]::mc::ThisIsMe \
		-variable [namespace current]::Var(Me)

	### Geometry ##########################################################
	grid $top.select -row 1 -column 1 -sticky ns
	grid $top.data   -row 1 -column 3 -sticky nsew

	grid columnconfigure $top {0 2 4} -minsize $::theme::padx
	grid rowconfigure $top {0 2} -minsize $::theme::pady

	grid $f.lname		-row  1 -column 1 -sticky w
	grid $f.ename		-row  1 -column 3 -sticky we -columnspan 3
	grid $f.lsex		-row  3 -column 1 -sticky w
	grid $f.bsex		-row  3 -column 3 -sticky w -columnspan 3
	grid $f.lbirthday	-row  5 -column 1 -sticky w
	grid $f.bbirthday	-row  5 -column 3 -sticky w -columnspan 3
	grid $f.lnation	-row  7 -column 1 -sticky w
	grid $f.bnation	-row  7 -column 3 -sticky we -columnspan 3

	grid $f.lrating1	-row  9 -column 1 -sticky w
	grid $f.brating1	-row  9 -column 3 -sticky w
	grid $f.escore1	-row  9 -column 5 -sticky w
	grid $f.lrating2	-row 11 -column 1 -sticky w
	grid $f.brating2	-row 11 -column 3 -sticky w
	grid $f.escore2	-row 11 -column 5 -sticky w
	grid $f.lrating3	-row 13 -column 1 -sticky w
	grid $f.brating3	-row 13 -column 3 -sticky w
	grid $f.escore3	-row 13 -column 5 -sticky w

	grid $f.ltitle1	-row 15 -column 1 -sticky w
	grid $f.btitle1	-row 15 -column 3 -sticky we -columnspan 3
	grid $f.ltitle2	-row 17 -column 1 -sticky w
	grid $f.btitle2	-row 17 -column 3 -sticky we -columnspan 3
	grid $f.ltitle3	-row 19 -column 1 -sticky w
	grid $f.btitle3	-row 19 -column 3 -sticky we -columnspan 3

	grid $f.lfide		-row 21 -column 1 -sticky w
	grid $f.efide		-row 21 -column 3 -sticky w
	grid $f.bfill		-row 21 -column 5 -sticky w
	grid $f.ldsb		-row 23 -column 1 -sticky w
	grid $f.edsb		-row 23 -column 3 -sticky w -columnspan 3
	grid $f.lecf		-row 25 -column 1 -sticky w
	grid $f.eecf		-row 25 -column 3 -sticky w -columnspan 3
	grid $f.liccf		-row 27 -column 1 -sticky w
	grid $f.eiccf		-row 27 -column 3 -sticky w -columnspan 3
	grid $f.luscf		-row 29 -column 1 -sticky w
	grid $f.euscf		-row 29 -column 3 -sticky w -columnspan 3
	grid $f.lphoto		-row 31 -column 1 -sticky w
	grid $f.vphoto		-row 31 -column 3 -sticky w
	grid $f.bphoto		-row 31 -column 5 -sticky w
	grid $f.me			-row 33 -column 1 -sticky w -columnspan 5

	grid columnconfigure $f {2 4} -minsize $::theme::padx
	grid columnconfigure $f {5} -weight 1
	grid rowconfigure $f {2 4 6 10 12 16 18 22 24 26 28 30} -minsize $::theme::pady
	grid rowconfigure $f {8 14 20 32} -minsize $::theme::padY

	### Buttons ###########################################################
	::widget::dialogButtons $dlg {new save delete close help} -default close
	$dlg.delete configure -command [namespace code [list DeletePlayer $list]]
	$dlg.save configure -command [namespace code [list SavePlayer $list]]
	$dlg.new configure -command [namespace code [list NewPlayer $list]]
	$dlg.close configure -command [namespace code [list CloseSetup $list]]

	### Popup #############################################################
	wm protocol $dlg WM_DELETE_WINDOW [$dlg.close cget -command]
	wm minsize $dlg [winfo reqwidth $dlg] [winfo reqheight $dlg]
	wm resizable $dlg true false
	wm title $dlg [::mc::stripAmpersand $::menu::mc::PrivatePlayerCard]
	wm transient $dlg [winfo toplevel $parent]
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $list
	ClearVars $dlg
	FillList $list
	update idletasks
	wm geometry $dlg [winfo width $dlg]x[winfo height $dlg]
}


# --- private player cards ---------------------------------------------
#
# What the user knows about a player that the databases do not: their own
# card above all ("This is me", which the assistant uses for "my games"),
# or a club opponent missing from the rating lists. Kept in the user
# directory, never written into a database; the player card shows it in a
# section of its own, and the info tooltip fills in what the database lacks.
# A photo is copied to where the photo lookup finds it (photos/<letter>/).
# "From rating list" (or Return in the FIDE ID) fills the empty fields from
# the rating lists (::scidb::player::lookup; FIDE's current list once it is
# updated under Extras), by FIDE ID or by name; what the user typed stays.
#
#   ::playercard::privateCard <name>   -> the card's fields, or {}
#   ::playercard::privateCards         -> dict name -> fields
#   ::playercard::myCard               -> the name marked "This is me", or ""

variable PrivateFields {
	Name Sex Birthday Nation Rating1 Score1 Rating2 Score2 Rating3 Score3
	Title1 Title2 Title3 FideID DsbID EcfID IccfID UscfID Me
}
variable Private
# the photo chosen in the dialog, copied when the card is saved
variable PhotoSource ""


proc PrivateFile {} {
	return [file join $::scidb::dir::user private-players.dat]
}


proc privateCards {} {
	variable Private
	if {![info exists Private]} {
		set Private [dict create]
		set file [PrivateFile]
		if {[file readable $file]} {
			catch {
				set chan [open $file r]
				fconfigure $chan -encoding utf-8
				set data [read $chan]
				close $chan
				if {[string is list $data] && [llength $data] % 2 == 0} { set Private $data }
			}
		}
	}
	return $Private
}


proc privateCard {name} {
	set cards [privateCards]
	if {[dict exists $cards $name]} { return [dict get $cards $name] }
	return {}
}


proc myCard {} {
	dict for {name card} [privateCards] {
		if {[dict exists $card Me] && [dict get $card Me]} { return $name }
	}
	return ""
}


proc SavePrivate {cards} {
	variable Private
	set Private $cards
	set file [PrivateFile]
	file mkdir [file dirname $file]
	set chan [open $file.new w]
	fconfigure $chan -encoding utf-8
	puts -nonewline $chan $cards
	close $chan
	file rename -force $file.new $file
}


# Where the photo lookup finds a photo of <name> in the user directory.
proc PhotoPath {name} {
	set key [::util::photos::NormalizeName $name]
	set dir [string index $key 0]
	if {![string match {[a-z]} $dir]} { return "" }
	return [file join $::scidb::dir::user photos $dir $key]
}


# The dialog's selection boxes (sex, federation, ratings, titles, birthday)
# show translated text; their values are codes, read and set through them.
proc FieldWidget {dlg field} {
	set f $dlg.top.data
	switch -glob -- $field {
		Sex		{ return $f.bsex }
		Nation	{ return $f.bnation }
		Birthday	{ return $f.bbirthday }
		Rating[123]	{ return $f.brating[string index $field end] }
		Title[123]	{ return $f.btitle[string index $field end] }
	}
	return ""
}


proc GetField {dlg field} {
	variable Var
	set w [FieldWidget $dlg $field]
	if {$w eq "" || ![winfo exists $w]} { return [string trim $Var($field)] }
	if {$field eq "Birthday"} {
		set date [$w value]
		# a year alone is what the rating lists know ("1992.??.??")
		if {![regexp {^(\d{4})\.(..)\.(..)$} $date -> y m d] || $y eq "0000"} { return "" }
		if {[string match {*\?*} $m$d]} { return $y }
		return $date
	}
	return [$w value]
}


proc SetField {dlg field value} {
	variable Var
	set w [FieldWidget $dlg $field]
	if {$w eq "" || ![winfo exists $w]} { set Var($field) $value; return }
	if {$field eq "Birthday"} {
		if {$value eq ""} { set value 0.0.0 }
		if {[string is integer -strict $value]} { set value $value.0.0 }
	}
	catch { $w set $value }
}


proc ClearVars {{dlg ""}} {
	variable Var
	variable PrivateFields
	variable PhotoSource
	foreach field $PrivateFields {
		if {$dlg ne ""} { SetField $dlg $field "" } else { set Var($field) "" }
	}
	set Var(Me) 0
	set Var(PhotoLabel) $mc::NoPhoto
	set PhotoSource ""
}


# Fill the empty fields from the rating lists: by the FIDE ID when one is
# given, else by the name. Returns the fields it filled.
proc FillFromLists {dlg} {
	variable Var

	set id [string trim $Var(FideID)]
	set name [string trim $Var(Name)]
	set entry {}
	if {[string is integer -strict $id]} {
		set entry [::scidb::player::lookup -fide $id]
	} elseif {$name ne ""} {
		set entry [::scidb::player::lookup -name $name]
		if {![llength $entry]} {
			# "carlsen, magnus" as "Carlsen, Magnus"
			set entry [::scidb::player::lookup -name [join [lmap w [split $name " "] {
				string toupper $w 0 0
			}] " "]]
		}
	}
	if {![llength $entry]} {
		::dialog::info -parent $dlg -message [format $mc::NotInRatingList [expr {$id ne "" ? $id : $name}]]
		return {}
	}
	set filled {}
	set values [list Name [dict get $entry name] FideID [dict get $entry fideID] \
		Nation [dict get $entry federation] Sex [dict get $entry sex] Birthday [dict get $entry born] \
		DsbID [dict get $entry dsb] EcfID [dict get $entry ecf] IccfID [dict get $entry iccf]]
	if {[dict get $entry elo] ne ""} { lappend values Rating1 Elo Score1 [dict get $entry elo] }
	set i 0
	foreach t [dict get $entry titles] { if {[incr i] <= 3} { lappend values Title$i $t } }
	foreach {field value} $values {
		if {$value eq "" || [GetField $dlg $field] ne ""} continue
		SetField $dlg $field $value
		lappend filled $field
	}
	return $filled
}


proc FillList {list {select ""}} {
	$list clear
	set names [lsort -dictionary [dict keys [privateCards]]]
	foreach name $names { $list insert [list $name] }
	$list resize
	if {$select ne "" && [set i [lsearch -exact $names $select]] >= 0} { $list select $i }
}


proc SelectPlayer {list index} {
	variable Var
	variable PrivateFields

	set names [lsort -dictionary [dict keys [privateCards]]]
	if {![string is integer -strict $index] || $index < 0 || $index >= [llength $names]} { return }
	set name [lindex $names $index]
	set card [privateCard $name]
	set dlg [winfo toplevel $list]
	ClearVars $dlg
	foreach field $PrivateFields {
		if {[dict exists $card $field]} { SetField $dlg $field [dict get $card $field] }
	}
	set path [PhotoPath $name]
	if {$path ne "" && [file readable $path]} { set Var(PhotoLabel) [file tail $path] }
}


proc NewPlayer {list} {
	set dlg [winfo toplevel $list]
	ClearVars $dlg
	focus $dlg.top.data.ename
}


proc ChoosePhoto {dlg} {
	variable Var
	variable PhotoSource
	set file [tk_getOpenFile -parent $dlg -title $mc::Photo \
		-filetypes {{Images {.png .gif .jpg .jpeg}} {All *}}]
	if {$file eq ""} { return }
	if {[catch { image delete [image create photo -file $file] }]} {
		::dialog::error -parent $dlg -message "[file tail $file]: not an image this program can read"
		return
	}
	set PhotoSource $file
	set Var(PhotoLabel) [file tail $file]
}


proc SavePlayer {list} {
	variable Var
	variable PrivateFields
	variable PhotoSource

	set dlg [winfo toplevel $list]
	set name [string trim $Var(Name)]
	if {$name eq ""} {
		::dialog::error -parent $dlg -message $mc::NameMissing
		return
	}
	set card [dict create]
	foreach field $PrivateFields { dict set card $field [GetField $dlg $field] }
	dict set card Name $name
	dict set card Me [expr {$Var(Me) ? 1 : 0}]

	set cards [privateCards]
	# only one card is the user's own
	if {[dict get $card Me]} {
		dict for {other c} $cards { dict set cards $other Me 0 }
		set ::application::ai::Settings(me) $name
	}
	dict set cards $name $card
	SavePrivate $cards

	if {$PhotoSource ne ""} {
		set path [PhotoPath $name]
		if {$path ne ""} {
			file mkdir [file dirname $path]
			file copy -force $PhotoSource $path
		}
		set PhotoSource ""
	}
	FillList $list $name
}


proc DeletePlayer {list} {
	variable Var
	set name [string trim $Var(Name)]
	set cards [privateCards]
	if {$name eq "" || ![dict exists $cards $name]} { bell; return }
	if {[dict exists $cards $name Me] && [dict get $cards $name Me]
	 && [info exists ::application::ai::Settings(me)] && $::application::ai::Settings(me) eq $name} {
		set ::application::ai::Settings(me) ""
	}
	SavePrivate [dict remove $cards $name]
	ClearVars [winfo toplevel $list]
	FillList $list
}


proc CloseSetup {list} {
	destroy [winfo toplevel $list]
}


# The private card of <name> as an HTML section for the player card, or "".
proc PrivateSection {name} {
	set card [privateCard $name]
	if {![llength $card]} { return "" }
	set rows {}
	foreach {field label} [list \
		Birthday $::playertable::mc::DateOfBirth Nation $::playertable::mc::T_Federation \
		FideID $::playertable::mc::F_FideID DsbID DSB-ID EcfID ECF-ID IccfID ICCF-ID UscfID USCF-ID] {
		if {[dict exists $card $field] && [dict get $card $field] ne ""} {
			set value [dict get $card $field]
			if {$field eq "Nation"} { catch { set value [::country::name $value] } }
			lappend rows $label $value
		}
	}
	foreach i {1 2 3} {
		if {[dict exists $card Title$i] && [dict get $card Title$i] ne ""} {
			set t [dict get $card Title$i]
			catch { set t $::titlebox::mc::Title($t) }
			lappend rows $::playertable::mc::F_Title $t
		}
		if {[dict exists $card Score$i] && [dict get $card Score$i] ne "" && [dict get $card Score$i] ne "0"} {
			lappend rows [dict get $card Rating$i] [dict get $card Score$i]
		}
	}
	if {![llength $rows]} { return "" }
	set esc {& &amp; < &lt; > &gt; \" &quot;}
	set html "<div style='margin-top:1em'><b>[string map $esc $mc::PrivateCard]</b>"
	append html " <small>([string map $esc $mc::PrivateCardNote])</small><table>"
	foreach {label value} $rows {
		append html "<tr><td>[string map $esc $label]:&nbsp;</td><td>[string map $esc $value]</td></tr>"
	}
	append html "</table></div>"
	return $html
}


# <info> (::scidb::db::playerInfo) with the private card filling in what is
# missing: sex, FIDE ID, federation, titles, date of birth.
proc WithPrivate {info} {
	set card [privateCard [lindex $info 0]]
	if {![llength $card]} { return $info }
	foreach {index field} {1 FideID 3 Sex 7 Nation 11 Birthday} {
		if {[string length [lindex $info $index]] <= 1 && [dict exists $card $field] && [dict get $card $field] ne ""} {
			lset info $index [dict get $card $field]
		}
	}
	if {![llength [lindex $info 8]]} {
		set titles {}
		foreach i {1 2 3} {
			if {[dict exists $card Title$i] && [dict get $card Title$i] ne ""} { lappend titles [dict get $card Title$i] }
		}
		if {[llength $titles]} { lset info 8 $titles }
	}
	return $info
}


proc buildWebMenu {parent m info} {
	variable Options

	set fideID    [lindex $info  1]
	set dsbID     [lindex $info 13]
	set ecfID     [lindex $info 14]
	set iccfID    [lindex $info 15]
	set viafID    [lindex $info 16]
	set pndID     [lindex $info 17]
	set cgdcID    [lindex $info 18]
	set wikiLinks [lindex $info 19]

	if {[string index $fideID 0] eq "-"} { set fideID [string range $fideID 1 end] }

	set name      [::playertable::column $info lastName]
	set lastName  [string trim [lindex [split $name ,] 0]]
	set firstName [string trim [lindex [split $name ,] 1]]

	$m add command \
		-label " [format $mc::OpenPlayerCard Fide]" \
		-state [expr {[string length $fideID] ? "normal" : "disabled"}] \
		-image $icon::16x16::Fide \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $fideID] $Options(url:fide)]] \
		;
	$m add command \
		-label " [format $mc::OpenPlayerCard ICCF]" \
		-state [expr {[string length $iccfID] ? "normal" : "disabled"}] \
		-image $icon::16x16::ICCF \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $iccfID] $Options(url:iccf)]] \
		;
#	$m add command \
#		-label " [format $mc::OpenPlayerCard USCF]" \
#		-state [expr {[string length $uscfID] ? "normal" : "disabled"}] \
#		-image $icon::16x16::USCF \
#		-compound left \
#		-command [list ::web::open $parent [string map [list %id% $uscfID] $Options(url:uscf)]] \
#		;
	$m add command \
		-label " [format $mc::OpenFileCard DWZ]" \
		-state [expr {[string length $dsbID] ? "normal" : "disabled"}] \
		-image $icon::16x16::DSB \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $dsbID] $Options(url:dsb)]] \
		;
	$m add command \
		-label " [format $mc::OpenPlayerCard ECF]" \
		-state [expr {[string length $ecfID] ? "normal" : "disabled"}] \
		-image $icon::16x16::ECF \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $ecfID] $Options(url:ecf)]] \
		;
	set sub [menu $m.wiki -tearoff false]
	$m add cascade \
		-menu $sub \
		-label " $mc::OpenWikipedia" \
		-state [expr {[llength $wikiLinks] ? "normal" : "disabled"}] \
		-image $icon::16x16::Wikipedia \
		-compound left \
		;
	$m add command \
		-label " $mc::OpenViafCatalog" \
		-state [expr {[string length $viafID] ? "normal" : "disabled"}] \
		-image $icon::16x16::VIAF \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $viafID] $Options(url:viaf)]] \
		;
	$m add command \
		-label " $mc::OpenPndCatalog" \
		-state [expr {[string length $pndID] ? "normal" : "disabled"}] \
		-image $icon::16x16::PND \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $pndID] $Options(url:pnd)]] \
		;
	$m add command \
		-label " $mc::OpenChessgames" \
		-state [expr {[string length $cgdcID] ? "normal" : "disabled"}] \
		-image $icon::16x16::ChessgamesDotCom \
		-compound left \
		-command [list ::web::open $parent [string map [list %id% $cgdcID] $Options(url:chessgames)]] \
		;
	set url [string map [list %lastname% $lastName %firstname% $firstName] $Options(url:365Chess)]
	$m add command \
		-label " $mc::SeachIn365ChessCom" \
		-image $icon::16x16::365ChessCom \
		-compound left \
		-command [list ::web::open $parent $url]
		;
	
	foreach {lang name} $wikiLinks {
		set flag ""
		catch { set flag $::country::icon::flag($::mc::langToCountry($lang)) }
		if {[string length $flag] == 0} { set flag $::icon::16x16::none }
		set url [string map [list %lang% $lang %name% $name] $Options(url:wikipedia)]
		$sub add command \
			-label " [::encoding::languageName $lang]" \
			-image $flag \
			-compound left \
			-command [list ::web::open $parent $url] \
			;
	}

#	if {	[string length $fideID] == 0
#		&& [string length $iccfID] == 0
#		&& [string length $dsbID] == 0
#		&& [string length $ecfID] == 0
#		&& [llength $wikiLinks] == 0
#		&& [string length $viafID] == 0
#		&& [string length $pndID] == 0
#		&& [string length $cgdcID] == 0} {
#
#		return 0
#	}

	return 1
}


proc DefaultCSS {} {
	set textFonts [::font::html::defaultTextFonts playercard]
	set fixedFonts [::font::html::defaultFixedFonts playercard]
	return [::html::defaultCSS $fixedFonts $textFonts]
}


proc FontSizeChanged {w dlg key} {
	if {$w eq $dlg} {
		ChangeFontSize $w $key [::font::html::fontSize playercard]
	}
}


proc ChangeFontSize {w key size} {
	variable Vars

	$w css [DefaultCSS]
	$w fontsize [::font::html::fontSize playercard]
	UpdateContent {*}$Vars($key:arguments)
	return $size
}


proc UpdatePlayer {w id key base variant name playerCardArgs} {
	if {[llength $playerCardArgs] == 1} {
		set pos [::scidb::db::find player $base $variant $id]
		if {$pos == -1} {
			destroy [winfo toplevel $w]
			return
		}
		set playerCardArgs $pos
	}

	UpdateContent $w $id $key $base $variant $name $playerCardArgs
}


proc MakeKey {base variant info} {
	lassign $info name fideID type sex _ _ _ country titles _ _ dateOfBirth _
	if {[string length $name] == 0} { return "" }
	return card:$base:$variant:$name:$fideID:$type:$sex:$country:$titles:$dateOfBirth
}


proc UpdateContent {w id key base variant name playerCardArgs} {
	variable Vars
	variable Options

	if {!$Vars($key:open)} { return }

	set preamble "
		\\def\\FormatDate#date{\\%date\\%(#date)}
		\\def\\FormatFederation#code{\\%code\\%(#code)}
		\\def\\DecimalPoint{[::locale::decimalPoint]}
		\\def\\Lang{$::mc::langID}
		\\def\\Title{$mc::PlayerCard: $name}
		\\let\\Tracing\\$Options(debug:log)
		\\def\\Label-White{$::mc::White}
		\\def\\Label-Black{$::mc::Black}
		\\def\\Label-Surname{$::playertable::mc::F_LastName}
		\\def\\Label-Forename{$::playertable::mc::F_FirstName}
		\\def\\Label-Federation{$::playertable::mc::T_Federation}
		\\def\\Label-FIDE-ID{$::playertable::mc::F_FideID}
		\\def\\Label-Title{$::playertable::mc::F_Title}
		\\def\\Label-BirthDay{$::playertable::mc::DateOfBirth}
		\\def\\Label-DeathDay{$::playertable::mc::DateOfDeath}
		\\def\\Label-Latest{$mc::Latest}
		\\def\\Label-Highest{$mc::Highest}
		\\def\\Label-Minimal{$mc::Minimal}
		\\def\\Label-Maximal{$mc::Maximal}
		\\def\\Label-Win{$mc::Win}
		\\def\\Label-Draw{$mc::Draw}
		\\def\\Label-Loss{$mc::Loss}
		\\def\\Label-Total{$mc::Total}
		\\def\\Label-Score{$::crosstable::mc::Score}
		\\def\\Label-First-Game-Played{$mc::FirstGamePlayed}
		\\def\\Label-Last-Game-Played{$mc::LastGamePlayed}
		\\def\\Label-White-Most-Played{$mc::WhiteMostPlayed}
		\\def\\Label-Black-Most-Played{$mc::BlackMostPlayed}
	"
	set searchDir [file join $::scidb::dir::share scripts]
	set script "player-card.eXt"
	set result [::scidb::db::playerCard $searchDir $script $preamble $base $variant {*}$playerCardArgs]
	lassign $result html log

	set i [string first "%date%(" $html]
	while {$i >= 0} {
		set e [string first ) $html [expr {$i + 6}]]
		set date [string range $html [expr {$i + 7}] [expr {$e - 1}]]
		if {[string length $date] == 10} {
			set html [string replace $html $i $e [::locale::formatDate $date]]
		} else {
			set html [string replace $html $i $e ""]
		}
		set i [string first "%date%(" $html]
	}

	set i [string first "%code%(" $html]
	while {$i >= 0} {
		set e [string first ) $html [expr {$i + 6}]]
		set code [string range $html [expr {$i + 7}] [expr {$e - 1}]]
		if {[string length $code] == 3} {
			set html [string replace $html $i $e [::country::name $code]]
		} else {
			set html [string replace $html $i $e ""]
		}
		set i [string first "%code%(" $html]
	}

	# what the user entered about this player, in a section of its own
	set private [PrivateSection $name]
	if {$private ne ""} {
		set i [string last "</body>" $html]
		if {$i >= 0} {
			set html "[string range $html 0 [expr {$i - 1}]]$private[string range $html $i end]"
		} else {
			append html $private
		}
	}

	set dlg [winfo toplevel $w]
	$w parse $html
	lassign [$w minbbox] x y x2 y2
	incr x2 -4
	incr y2 -4
	set height [expr {2*$y + $y2}]
	set width [expr {2*$x + $x2 + 15}]

	wm maxsize $dlg [expr {$width + 100}] [expr {2*$y + $y2}]
	wm minsize $dlg 1 340
	wm title $dlg "[tk appname] - $mc::PlayerCard: $name ([::util::databaseName $base])"

	set show(log) $Options(debug:log)
	set show(html) $Options(debug:html)
	if {[string length $log]} { set show(log) yes }

	foreach attr {log html} {
		set Vars(output:$attr) [set $attr]
		if {$show($attr)} {
			ShowTrace $attr $key
		} elseif {[winfo exists $dlg.$attr]} {
			destroy $dlg.$attr
		}
	}

	return ${width}x${height}
}


proc MouseEnter {w variant nodes} {
	variable Vars

	foreach node $nodes {
		set titles [split [$node attribute -default {} title] ',']
		if {[string length $titles]} {
			set Vars($w:tooltip) $node
			set tip ""
			set delim ""
			foreach title $titles {
				append tip $delim
				append tip $::titlebox::mc::Title([string trim $title])
				set delim \n
			}
			Tooltip $w $tip
		}

		set eco [$node attribute -default {} eco]
		if {[string length $eco]} {
			set Vars($w:tooltip) $node
			set opening [::scidb::misc::lookup opening $eco $variant]
			lassign $opening long short
			set vars [lrange $opening 2 end]
			if {[llength $vars]} {
				set opening [::mc::translateEco $short]
				foreach var $vars {
					if {[string length $var]} {
						append opening ", " [::mc::translateEco $var]
					}
				}
			} else {
				set opening [::mc::translateEco $long]
			}
			Tooltip $w $opening
		}
	}
}


proc MouseLeave {w nodes {stimulate 0}} {
	variable Vars

	set hide 0

	foreach node $nodes {
		if {$Vars($w:tooltip) eq $node} {
			set Vars($w:tooltip) ""
			foreach attr {title eco} {
				if {[llength [$node attribute -default {} $attr]]} { set hide 1 }
			}
		}
	}

	if {$hide} {
		Tooltip $w hide
	}

	if {$stimulate} {
		$w stimulate
		::tooltip::hide
	}
}


proc Mouse3Down {w key info nodes} {
	variable ::table::options
	variable Vars

	if {$Vars(lock)} { return }

	set m $w.popup_web_links
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }
	$m add command                                       \
		-label " $::engine::mc::OpenUrl"                  \
		-image $::icon::16x16::none                       \
		-compound left                                    \
		-background $options(menu:headerbackground)       \
		-foreground $options(menu:headerforeground)       \
		-activebackground $options(menu:headerbackground) \
		-activeforeground $options(menu:headerforeground) \
		-font $options(menu:headerfont)                   \
		;
	$m add separator
	buildWebMenu $w $m $info
	$m add separator

	::font::html::addChangeFontSizeToMenu playercard $m \
		[namespace code [list ChangeFontSize $w $key]] [::html::minFontSize] [::html::maxFontSize] no
	$m add separator

	set sub [menu $m.debugging]
	foreach opt {html log} {
		$sub add checkbutton \
			-label [set ::crosstable::mc::Show[string toupper $opt 0 0]] \
			-command [namespace code [list ToggleTrace $opt $key]] \
			-variable [namespace current]::Options(debug:$opt) \
			;
		::theme::configureCheckEntry $sub
	}
	$m add cascade -label $::crosstable::mc::Debugging -menu $sub

	set Vars(lock) 1
	bind $m <<MenuUnpost>> [list set [namespace current]::Vars(lock) 0]
	tk_popup $m {*}[winfo pointerxy $w]
}


proc Tooltip {w msg} {
	if {$msg eq "hide"} {
		::tooltip::hide yes
	} elseif {[string length $msg]} {
		::tooltip::hide no ;# XXX probably we need a fix in tooltip.tcl
		::tooltip::show $w $msg
	}
}


proc GetImage {info code} {
	lassign $info name _ species sex _ _ _ country
	set img {}

	switch -glob -- $code {
		*.png {
			variable ImageCache
			if {![info exists ImageCache($code)]} {
				set ImageCache($code) [image create photo -file $code]
			}
			set img $ImageCache($code)
		}

		flag {
			if {[llength $country]} {
				set img $::country::icon::flag($country)
			}
		}

		photo {
			set img [::util::photos::get $name $info]
			if {[string length $img] > 0} { return $img }
			if {$species eq "program"} {
				set img $icon::80x80::engine
			} elseif {$sex eq "f"} {
				set img $icon::80x80::female
			} else {
				set img $icon::80x80::male
			}
		}
	}

	if {[string length $img] == 0} { return $img }
	return [list $img [namespace code DoNothing]]
}


proc DoNothing {args} {
	# nothing to do
}


proc PopupPlayerIndex {key} {
	variable Vars

	if {![info exists Vars($key:arguments)]} { return -1 }
	lassign $Vars($key:arguments) _html id _key base variant _name playerCardArgs
	if {![llength [info commands ::application::database::player::addPrepReportMenuEntry]]} {
		return -1
	}

	set playerIndex [::scidb::db::find player $base $variant $id]
	return $playerIndex
}


proc PopupMenu {key} {
	variable Vars

	set m $Vars($key).popup
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }

	set playerIndex [PopupPlayerIndex $key]
	if {$playerIndex >= 0} {
		set base [lindex $Vars($key:arguments) 3]
		set variant [lindex $Vars($key:arguments) 4]
		::application::database::player::addPrepReportMenuEntry $m $Vars($key) $base $variant $playerIndex
		$m add separator
	}

	set sub [menu $m.debugging]
	foreach opt {html log} {
		$sub add checkbutton \
			-label [set ::crosstable::mc::Show[string toupper $opt 0 0]] \
			-command [namespace code [list ToggleTrace $opt $key]] \
			-variable [namespace current]::Options(debug:$opt) \
			;
		::theme::configureCheckEntry $sub
	}
	$m add cascade -label $::crosstable::mc::Debugging -menu $sub

	bind $m <<MenuUnpost>> [list $Vars($key).content stimulate]
	bind $m <<MenuUnpost>> +::tooltip::hide
	tk_popup $m {*}[winfo pointerxy $Vars($key)]
}


proc Destroy {dlg key w unsubscribe} {
	if {$w ne $dlg} { return }

	catch { destroy $dlg.html }
	catch { destroy $dlg.log }

	::scidb::db::unsubscribe dbInfo {} [list [namespace current]::Close $key]
}


proc Close {key args} {
	set [namespace current]::Vars($key:open) 0
}


proc CloseTrace {which key} {
	variable Options
	variable Vars

	set Options(debug:$which) 0

	if {[winfo exists $Vars($key)]} {
		catch { destroy $Vars($key).$which }
	}
}


proc ShowTrace {which key} {
	variable Vars

	if {$which eq "log"} {
		set useHorzScroll 0
	} else {
		set useHorzScroll 1
	}
	set path $Vars($key).$which
	set closeCmd [namespace code [list CloseTrace $which $key]]
	::widget::showTrace $path $Vars(output:$which) $useHorzScroll $closeCmd
}


proc ToggleTrace {which key} {
	variable Options

	if {$Options(debug:$which)} {
		ShowTrace $which $key
	} else {
		CloseTrace $which $key
	}
}


namespace eval icon {
namespace eval 16x16 {

set Fide [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set VIAF [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACN0lEQVR4nJ2T
	v0/UQRDFP7N7PxCFRMXKDi1s5ZSOcGcojY0shlAYKIgUComJLeA/QGFhYqKRAmP80mvFcaFRw501
	iaAJMZIcUogKd9/v7lgcHEdiYXjVJm/ey5vZGTiAc87yn2itlVYilxtPZy8mbWxv/1vZ1UXtW2q/
	XH4WtxoYIOTyQ4/FypQGbQe1DUr1sE4QFFUx5peGMFcuRtOAEYCrhcHRTLrthU/qM/iw5o38QbxK
	MJ0iooGwHzTUUpJW0N5UJjsdx7XRylL00gAY5HZSr62sLr2ZXS0tvrZGvltJbVWWFxfKxehVEPOh
	PXNGUP+jXIxmklptRZRBgBSNoCKw55yzG1WeWJuZAMjl3dPuC9zf2NZHGHmAmM/OuSvrVXZRTNMA
	EAUfRZHvHRieqMf1MYuKsfb55qZ/WH6/OAlMApSBnrxLA3GrQfPtk+RTysisYiT4pNKercbXCm7M
	ptN34jj+UilG90QIqo0fNAdiRVQArCa3FHmn8Bbvb5ZKpUQ1eMJh0OM4SqAN8hQ7W6Wl0jhAf//d
	tt7ekc6PywvzwHyztNG/PzYDIHbO2fUqa9cHhrs1eH6zh55WcjeGMMbiffz1UpdcXq9qDCItBqoC
	HVG06HsGhkYCel7wQdUKCILXgDFqZCeKIp/Luw6En0czMBKlMm19uYKbEc85Ek9DfGhvhcRjgpzN
	FdxsKpvtQ4mOr3LBzYoxUxpCx8HmHoceJBWzqxrmysVoprnKhzjJMTVx0nP+C9EHEClyICnJAAAA
	AElFTkSuQmCC
}]

set PND [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACN0lEQVR4nJ2T
	v0/UQRDFP7N7PxCFRMXKDi1s5ZSOcGcojY0shlAYKIgUComJLeA/QGFhYqKRAmP80mvFcaFRw501
	iaAJMZIcUogKd9/v7lgcHEdiYXjVJm/ey5vZGTiAc87yn2itlVYilxtPZy8mbWxv/1vZ1UXtW2q/
	XH4WtxoYIOTyQ4/FypQGbQe1DUr1sE4QFFUx5peGMFcuRtOAEYCrhcHRTLrthU/qM/iw5o38QbxK
	MJ0iooGwHzTUUpJW0N5UJjsdx7XRylL00gAY5HZSr62sLr2ZXS0tvrZGvltJbVWWFxfKxehVEPOh
	PXNGUP+jXIxmklptRZRBgBSNoCKw55yzG1WeWJuZAMjl3dPuC9zf2NZHGHmAmM/OuSvrVXZRTNMA
	EAUfRZHvHRieqMf1MYuKsfb55qZ/WH6/OAlMApSBnrxLA3GrQfPtk+RTysisYiT4pNKercbXCm7M
	ptN34jj+UilG90QIqo0fNAdiRVQArCa3FHmn8Bbvb5ZKpUQ1eMJh0OM4SqAN8hQ7W6Wl0jhAf//d
	tt7ekc6PywvzwHyztNG/PzYDIHbO2fUqa9cHhrs1eH6zh55WcjeGMMbiffz1UpdcXq9qDCItBqoC
	HVG06HsGhkYCel7wQdUKCILXgDFqZCeKIp/Luw6En0czMBKlMm19uYKbEc85Ek9DfGhvhcRjgpzN
	FdxsKpvtQ4mOr3LBzYoxUxpCx8HmHoceJBWzqxrmysVoprnKhzjJMTVx0nP+C9EHEClyICnJAAAA
	AElFTkSuQmCC
}]

set Wikipedia [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB7UlEQVR4nJWT
	v2tTURiGn++cJBWcHHrt2IIELHZoqqAg3ARHu54O3f0rHGIG8Y9w1uVKoYOrTYqgS1tKiyBEaUcT
	WkEC+XXP+RySm1xbHPpO332438t77nuuMJc450yn0xGAKIo0SZIAEMexzV7KcZ2v1uuGm2q6I9nz
	2tPnd0ql2zGqayCKcGpLxU8+HQlBajOucjJKe/snnz/+nhlUau5FwRZfh+AXNYQugLF20fv0F4C1
	hbvB+y6AGLNojOmmPn15uJe8nURXtkPwF17Hy5vx6tJmvLo0SvsrInIpIpejtL+Sca/j5RDCBco2
	QHaOnobQPtrbOc+OdNzaPUNpo7SPW7tnGT/a2znXENoCPYDCJAAGKELdNJvN6QetA98WpvM/XCd8
	PEswTaHQCFEUaRRFCo2AoMh1LrkKb17fFRWyQScXyWYXyTlnf3aZzXn+ozuvPzMQgWGSJD7vvlFz
	Q4BrvOqGCnZmINBH5MFG1b1DqACo6hGq9wAq1a33Iro+3T8AKYvqaS6BFoulW+XRcPBHYB9VAXlo
	rL0P4H06ANlHVVRkvVRaKI+H/e9zA+Nf+XTw5rCZfMlHrcRbjwEOWx++5vmjZ+4Jxg+n6fOqmzie
	9N1qtTyzuvK8GqARruzVjXPOckXOOfs/nv2NfwHD+uvgJ4DquQAAAABJRU5ErkJggg==
}]

set ICCF [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set DSB [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set USCF [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set ECF [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set ChessgamesDotCom [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

set 365ChessCom [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZklEQVR4nJWT
	z2vcZRDGP8+8725DVootNPYoKBQKuummlRbEtMFW1Ns2Xw8Fe+tNL/4Dazx7bE8Fewxk++OkQhu7
	WxBbDJts/FHEU2/WglrUpcl3933Hwyp0U3vocxpmnoGZeZ6BSYhWy3gaxjVNNkzGDjC38F4D5x3H
	6wCS9cG/7N1cWd/J1eOJg0dP7a3Vnr8oC03Pjmw8jOeMzPA8ujoYPDx398713//rEYxHrs/f212N
	27eRZtIonRF+QWLVQaAFdz4IMS7j+ddy9OjY5q3ZP2HJrSjuCpZy1OAS0vTa6vK+6MMfQ6Xy0pZC
	61GmFWJ8OZn/sLY63CfTdFT1M1jKRVGYAI7MF7O2q7oxLLfvCX3ncMBMB3L2GwBmOunuP+H87Pir
	lequF7eHw9l+Z2XTALK8mVMaCG0AUxIv5JwfSCSJlHN+AOwHpoQ2ckqDgDcBIoCjekqjtfXu5SbA
	3InFm0i/9TrtAqBxYvEyzp5et/0WQGO+6GLUAf5fc3+qE56AAOaOL35iIX6UU7oO1BCvuXspaR3A
	3RsSVVzfAgML4VTO6dNep/2xASTZFQuh5vghYAu4b2Yz7gR3gpnNgO4DW+7esBBqCV0DsKIoQr+z
	sjkqy2sxVqzXbTfLPDppIVJaeD84Zy1ERuLNXpdmrFRtWG5f7XdWNouiCBqv0VJ9vr+7Gqe/QdrP
	cHgmi/OIr/7ddCFn/zBW4rK7/+JKx3qrB/+CJZ+w8iuvv7tnauq5i5Kd3mllJHLOV8ry73Pff/35
	H49ZeeKgDnD4jdOHiPFtJ8+OC9ZXyl+s3Wr3d3KfVOUZ3/kfAIcRLu5fsmcAAAAASUVORK5CYII=
}]

} ;# namespace 16x16
namespace eval 80x80 {

set male [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAANs0lEQVR4nO1c
	e4xc51X/nfN9d2bXjyRt4iUP8mgwgY5C/BgXua6Vu97GrtWmNom5NoRKgYL8R1TRVA0V/YfJCNHA
	H6WNRCG1Am2hVE1vDHZlUedl7yREdZVM0jzYqEUG0dBCN8U2trO7M/f7zuGPe2c9+3JmZmdsr5if
	NNLuvfd7/e75zjnfOWcG6KOPPvroo48++uijjz766GOJgS72BDoAhWFohoaGdLEdFQoFHR0d5Uql
	4gEsur+lgF6+8I76XkoSSAB048Zo0C3jvQq8D+KDznoiVWCAQctAeD7xtYdfqRw81Rij3UktBRCg
	CMPdy88yvhPkBjaL+MX3qgo2Fkm99ipzfeSFZw6caNxptQte/Cx6jzAMDUB6Bvp7QW5gc702VXMu
	cS5JfEefRlvnfL02WQty+dvE208C0HSs1mF7tOauomEwiPB+8d6DYAiwi9o/WVtVgogTJdrUPFar
	WBISOD4+TgCgRP9JzAaKhtV8p0+LIIbi7U7mtiQIHB4eFgDEwD7vkrM2yOXpncBM7ah4Ikx2Mrcl
	QWC5XBYA9OLR+AfeyTYRfxSqP1OVkzM/ekpVTorIafX+J1Ctt0yiakcKYUnowAwCKL38LH0XwEjx
	juhylywnABCfEACweVvJ54KrV5w5/dbkih1k+CuqYpGy2BOPYykRCIAUpRKjXNbq0/H/LvRUMdw1
	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
}]

set female [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAMbElEQVR4nO1c
	b4xcV3X/nXPvnV07ceI4zmIhkJ10AbGBpPE6UdQQvXUgkhOZGEgeIVDLIVJNkfqBT/1QqX2MkCrE
	p36oShKkhA0hfzwOiKQGIxF7HzIoShiHELNticG2aCu80NqO/+3Mu/ecfngzu7Pr2c0mfjM7Tucn
	zZfZ+8459zfnvnvuOecu0EcfffTRRx999HFJgpbbgEUw3zZdFiveAr1CIMVxzFNTUzQ0NKSVSiW0
	GxTHsWkZI+hRUruIhKMosu3+csOdd152Y7Rt9Y3RttU33HnnZe3G5M8m3FkbF8dyeSDFccxNT4ui
	HYPn+PwtQnQ7VDYB2ADFNSBdCQBQOgfCHwE6AqKqAX66pnTq5b1799aA3DOXyyO7TmBjsgEANm2O
	PwTmh6B6LxH/GRsDVYWqQFUBbfBBBCICEYOIICFAVQ6D6HsQeewX+yv/MV92t9BNAme87qPRp983
	4NzfqdCD1toVIXioBFVQgIIISrll1LBPFQooSEFQghpiQ8ZYeO/PE+u3a1n2j6+n3//Pbntjtwhs
	6tGN0f0PssE3jLHXeF+HAp6gDNDbfJepKEgIsNaWEIKfUpG/rU5Uxlv1FTiHtugCgQkDZYmiyJ7l
	df/M1n5Jgodo8AQybWxQQFWV5kyeSKnhkReMV2hgMpaNgXj/8LVr9W/ypZzr7uTsOk0gAcCtt8aD
	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
}]

set engine [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAMfUlEQVR4nO1c
	XYwcR7X+vqrunrWT4Gzg+kYCFAkFI0Wy2HgcERnLu4v5C+En8tIxWXi4Qpc8XvKGxBVpGh6uEC8I
	xEsekJDIbzsIAknET/BuBFaiZONFQZZITKToCgkMwU6crD3dVXV46J7d2dmZne7Z3tk17CeNNJrp
	On3qVJ1Tp845VcAOdrCDHfz7glvNQBiGGgCS5CYBYleuVaTC8AzzdondPO62N4juAYwiNbDV2mfW
	0hkhturFBCAAcHD6+CHl+3uzVusPp+eTs53/9Wt382R4oxcE+8WYvz5/8uFT3TRHia0QIAHg1o+G
	41nG+5XWHycAJ9Jy1vzfC3MnYgAKQLc6KwDuwNSxe5UOvqrIhgBwzv3C99zsM79MzhfPjVSIg1Wm
	ZoRhqABImsq3/cbYx601xhhjxdmGHzS+3pwKbwfg2raxaKMBuOZUeLsf7IrF2YYxxlprjB80Ppam
	8m0AUtAeKUb9QiZJYpvNu3cTuN2kLUuIIqEBZCLiQAkB4Ny5c8vasfydEoqIA5CR0ISonAZubzbv
	3l0sKCPVqpGPGABc8s+PgQgA0QAJACJQABQEuwFg7969y6q4/D3/TxXPIm8rGkRwyT8/NuJu5BzU
	QiWK1OTcnOrsdC+cO3eOe/fulVfOeeNQ2UukGhcRAUARWM/3tc3S5D3/wbsAaABtF0UDsK/8TR7U
	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
	PI8eOz4AAAAASUVORK5CYII=
}]

} ;# namespace 80x80
} ;# namespace icon
} ;# namespace playercard

# vi:set ts=3 sw=3:
