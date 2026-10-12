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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACnklEQVR4nHWS
	T0hUURjFz/d8b57jNP5hUidx1KKFm3YtrEnIYCQRq9XQhDtdVGQtmtrVILprI7UqCBKDCjdpC6N/
	JFhuQshwkYkxUKGgZtnoe/f9OS1yYjT7NndzznfvOfcn2DYkBYAACNq23QoApmk+A7ABgCLC7Z4d
	h2RLqju9kOpOL5Bs+Z9OL7xZREgyCODIzMe50/PZr9UAMPNxrpOkDmBCRDby2i2bMpmMBgCWZXWc
	6U6vNCVSPHgs6R08lvSaEime6U6vWJbVUagFAK1wCUnJ5SzHVk7O96kACkDxfSpbOblcznI2O9ox
	s2yeMZL90zOzE/G2Tj/e1ulPz8xOkOwnGSvUAn/aLsx/YOD2UN+TsdeHfN8P59Y3TAAIlQRtTdPW
	ThxveXvpbOd1EfmQ9+gF5pLBhyOXBx+MniQJMxCA47oAgHXLDtq2Ct57OHKqvDz8g+S5fJla/hUA
	Yi/GJw8rx2V7onl0ZGigpzZala3dU5UduX+rpz3RPKocl6/GJw8BqMsn+PuNAIojFWVB13GlrDQc
	iUarYncGeqcAIFoViZWW7oq4jisVFWUlAIr/4UAp1bi0vFpp6BoePX4aH3s5EXcdhwCgG4b8XPsF
	Q9ewtLxaqZRqBPB+eHhY9DwQ45NTDbPzWbO42GQ4FPI9z6OIaADgeZ5XGgrJGqB9ms+a42/eNQBA
	Mpn09UwmI729vayvjS4GTZO2rZwbfelnuyMVVMoVAAgEdC4tfZcLV/tbTTNg1NfVLG4CtaUDeL4v
	G5YdOH+l76gQW4ChgLalArqxxQIhqYmI7zhOW9fFa3fnPn+JFBVpGrYtgICe5/v799Yu373Z12UY
	xhhJTQo5cF03MZ/9Vq3r4u1Eq+uyaF99zaKu689FZJ2k/AYymWgYyFTScwAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADG0lEQVR4nKWT
	W2hcZRSF1/4v58zMyaS06TiJ8QJtMR17CTGlsRhBLYpYEAOiD0rrk0UUShXB0nhJfGiN9EFRKr4J
	RXxRkdqoDVFpg62KTWNbZxBDTQmYMTNJM5nLmfnP/28fJoU86JMb9uNe7LU+FvA/h1aWmfmOufmF
	7mq14gEALJGFhZSCrXV04yCZTNbbU+umiOh3AKSkFFyp1AcOHh4Zmrqc64qs9ZxzYGYQEQQJAAwp
	BUfWkZaq0dO9OReG4RtBkPhcRZHNvDj41uBX4z9sCxI+tFL1RDzGWikYY1CrN0gIkkvLZdXakjCl
	clmfGpvYzozDUWSzIl9Y7J38NZdpSfjuwP6n3zl/+uMjz+57PNu3o3tu/zNPTI199uFoOtUW1hsR
	Ojvaa8OHXvg+5unGxUu5LflCYYdaLpVikbVaSun2PvnotaGR4/2fnhzraZgIgnD734WFbNu6tUtB
	/C+KrJ27Z2fPpVjc22VMpJdLlZgSUjCads3Vmdlt42fOP+Rp5e7d1fvjuZ8md34x+u2mLz85fuqP
	P6+FWzdv+m1+vlgCkyaCE1KwWo2kKcbNxNkRkUBkI7XvuVcemJ6Z9W+7pb3v3aODpwE2zNAAIFZg
	MjPUzelU7v7+vm8aJhLjZ3++uxaG4rFHdl9MBPHr1jooqZ2WwjBzEz6AlQ+YlZKqWFycHzr0/NiW
	zMYNV3LTrXd2bSgO7Nl9ZqlU9oqL19s6bkrliaCVVorBDMgbAiSiyNQd0Dew98DDC4uljkTMcxPn
	LnQee/+j7UTEUgoYY9HZnoqcZaGVsM4aUs46AgNEhGQQ1KUgU61VXRiGDIJTSq7KiOB52hAoxsxw
	DqSSrUGolTLlWk19/d3Z+IkPRk5enZlNkyQnQHDgpknrqCVImCu56VtfPfLefb4ft2uSQY2YOfPS
	4NsnRscn7or5Gr6nQyICgXg1IQaTIOJyperXjRN7Huy/cOzNl59SSspspVodBvDa5OVclzHGB4Pw
	b0Pg9W1rw56tmezR1w8OKylzq9uYyecLvZWw5v9XdZ0FJYN4mE6v/4WIsgDoHxQLdrV8dDCvAAAA
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACzElEQVR4nJ1T
	S0hUYRT+zv//d8aZuXecfGNRBBVFUQQFFiX2WGSFURLWImoVPRYJ0caNuOm56YFFRRC16AFNQoqE
	va00ahFUBtKiRZmm2eB4Z+6de+9/WqT23NTZnSfnfN/5gDFjZsI/2Hg9jTtExMxclkqllw4MDccM
	Q2gACAIiCQCSOQg0FRcUZBIJ6ykR9TMzqZ+aiy5cTp642tK+wXHcEAASRAi0BjODiCCFQCgccrdu
	XNvCzPVE1C/GNgh5XrDnWkv75o99A2Ew+wB8x8nlQobhmNGoEzYMJ5t1Mn2fPoevJNtq0+n0EgBQ
	RMSe563esbfhwODQVwoZikuKCoNTRxvOJBLxkVvtD2revH03af68WZ8rFi3oqd1eX+fmvEjfwJAJ
	AAoAfN/Xvq8dEEwpFEHgS3lZyavGw801N9vuLcx5HpKtHdO21dUkzFhEuDkPQggGAAEAeXl5j8+f
	bHpoxqKIxSK41HzwPgBxr/PZ+pChglXLF3dHopEg2doxcyRtG1KICTYEANiuu3xnfWPVqJ3BqJ3B
	9r0NVcOpkYVg9n7l9k+mxe8BAiHwtShIxLtXVlbcdj1P3u18XpHNOrKmekWvZUa9QGsAEhMYxMLh
	znPHmx6sq9u9ibXG5bNHXgCw9+3a1jN39oypr9/2Fs6dM3Ngw5qVH9o7Hk0nIQAEPwY4jrNs577G
	StvOEDOwa39TJYDK3nfvI4m4qZWh8KT7Zcm1ZNvsQLM0xI9TFAAopYSUIsIMMDNnM07k+2A3POT7
	0JqhmaGUAMAMMLTWBACCmUkpdedi86FjxUWT2M3laDiVkoNfvioxhrYQ37/QzmSVbWdVOGT45aVF
	oxMgElHOMOTpLRurr0+ZXOb6fiAZLBP5FuKWibhlIj9ushBClZYUultr19+wLKvrr2JKpzNL+gcH
	Y1IKDgL9B29lxcW2ZUW7xsU0kfhfOX8DiB1ZDEZtjcUAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADIklEQVR4nK1T
	X0xTZxw9v+/e9N6WYVsoUFztBosl/MlKAgWUm7mqgS3Lkm1MH0icmTHxwSdf3cO1D0u2x2XZg8li
	YsaTS5b5MDdAmhmhDiSbW0JBs9LVglTogIFAb+/9vs8H1Pmu5/mcX37n5BzgBUFSSh1A/P5C4WA4
	FFwFkM8vLrUqisL2BmsnAdwCcOBBYbmbcy72vVo/A2DfwoOCL7Q3OKVajvPOqbPnv80vLlc3RxrA
	OReZfxaYpmnwVnoKl7/5/PLJs5+d/G9zO2hZFt54PSQURWH3Mjn4KivWVc45CCQ3NjZxMzUtfN5K
	2A6XhYcrsqWp0eVyuSocx3Hl7i+IVyo8lL6bwdr6hvS43eTdUyGZR9N+Gbr45ZnjH/TPWGWH3ja6
	iqdPDGTLtsPqagJrjLGZuprqtbLtsNMnBrJxo3ulbDv4+P2jf/343ddnGBGViOiHviO9l2prqpAc
	n9rTHGnI1Qb89vSdmdBIcmJg+k46VBfw282Rhlzy5m/eupoq9B01LhHR9+zKFamYpsk6o63XW5oa
	MyvFdT09l/EeiLXnt7ZL2lcXh4yt7ZLWE2vPp+ey3uXiut68vyHb8WbLmGmajB07BpFIJASA2UMH
	Y2Met47RX2+F40bnEhHwcOVfnQiIG11Lozcmwh63jkNG7DqAuUQiIRgRSdOUjIjswQ/7r4VDwc30
	vWxAYQpF2yKrj7Z2EG1rWlWYQum72UA4FNwcHHjvJyJyTFMyBgAXLkACgKppqVh725QjBIaTE/WB
	Kv+ObTsI+H07w8nxekcIdEZbb6uqmnqigwoARCQBSaqqFMcnf/959Ebq8PjkH68xpki/rxKp238G
	heBUW+2T7/YZ11RFKe7KSLCnlZQSxLlAT0d0ZH9jeN52OAGCOBcABNkOp0hjeL6nIzrChYCUkgDg
	2QFg1waA2bjRNUZExIWk/sO9i1xIIiJ6q7czCWD2eb76bBRE0jRNRkSOlPLqcDJ1vFwu73xhnhv6
	ez73icvlcn86+NHV3fBMRkQCAOj5ZT19C4BmWdYRKSXXdX2yVCp1E5GiadoYAOv/3F4CHgPueV2J
	kAJ3VwAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADIklEQVR4nF2T
	T2hcVRTGv3PffXf+kZl0TGqiJZNMbNSKuslCJNQqWbtxZ8BNm4rQWoKVUrROUtMUsRBFEVGkO+nK
	TTeCUF246EKFBiJNnZl0MtOZ1k7jNDMvM9533j0uamjJtz78zvcdvkPYJREhIhIRSTLzdLlSHyKi
	SES8ifGR2wB+JCK7M6d3A+bn5wmAMPPBw++e+bq4Xnss5msXcqSGhwY2lz6cOyci3wKwIkJqN2BH
	5UptqLReHe50AtPaaseDbtesXi8PvV/4dJHB00QkAB4CRIRERAFQhUJBQcT5WkdKKRApEAAiglKK
	NB4a14/mBiAAHAAcnp21AiEAkoibjhNRuX1PbJ774MQigJ/+Xyb6kaMZANM3Sjf3GmNsu919xTlR
	8USMPzt/+pdMuq81OLCn1Z/uuwaAicgR0QNnImKCIJg5OrewVK3/PeApgohT7c42OeeQSibCyLlQ
	EXF+dKQ5+9Yblw6+PLlMRE0SEVUsVt45OX/h7FqxkiUCtOfB8xSSqSQn43FtrYWIIOQIra0OBrP9
	7uzp44uHpiYXNYDnP/nyu2PXi5XsM/tzWy8cmPhnZfVG9q/yRt9Lz040Pz9/6lKlWl8xxth2Jxi8
	8MXFI1f/WH3u4vc/vHloavKyrjUaL5bK1dFkIiZBp+tf/W1lr3MOxvhYK65ng6B3ZeKpscsAYHyN
	36/9iSMnPlreqDaerDUaB9R2YGMhsxc3MdefSUvrfiexJ5ORRDwWMbO509wcKBR+1oVCIW5D9mLa
	NI0x4Ih1r2uN1r5yAKC1om+WC18B6lfATb0+c3xOBJJOpXoLC68yAAaAVDzuRAQAoDwlWimIUoR/
	LUelSrX19HherZUqLY7YEZG7e6+5f+PW7Zlud1snEkm+e29znJlD39dQSom2ln2OIq/b66ljp5bm
	je/r0IZRz1oPAN5+7+Mzvq81BAABHHIY9Hp+n0o4a62v87mx+vjoyK3yzdrjnkfknAu1rykTMxYA
	IucURMIHfQd8o5H2UjY/uu9OPjdWJxFJMeO1cmVjWGuKdjruIkc7OXc/GrN4+dxIQ2tc+Q9AZJ1I
	S3aeJwAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACxElEQVR4nKWT
	T4jVVRzFz7m/+5v35v2ccZ7v0TBq6pgtHKlF1MJtISiBQbhyCCVjIBKL0nChvpkyAmsRQbQZSRci
	SCAEKfQHahNhUUox0IwzbxzCP9hz3tD83vz+3uNi3hsSa9WFy72Lc+Cezz1f4H8uSiJJSeqO4/hZ
	SXmxWPwpjKKng2KxCMC1tSaO46RQKHxHcqnjoyRD0knauXfk7fNJnLQ+P/vR+J59b7wcBEFFchkA
	kDRJkkbnxz94ieTljs+Ojo4CAKbrc/2zczf70jQt/XJtYuedu41196bqtNZCcsgyh0q5N5icrj8C
	AB2f7WTJnaMhkKZZ15vHTj0TxQms5+WE4Ps+rSdK+lcGhqRL03TXK6+fOPPH9dlqFMX0fctqpQIA
	aDTuIYoTPPXk1uZnn7w3TPJSxwdJbO9uSbsuXLz87dbtuzU8cqS5uBieW1wMz+0dOdIc2v6CLn31
	/UVJJQCQRAAwJNWGtATgm6n63IJErCmX60FQOhgEpYOVcrkuAVd+/V3LUq5EMJ0o7bN66/bdTQAw
	0F+dBbAAYGGgvzorAH81mpsArGqzIADY9lMkqQvAi435hUFDYMvgxlVhGA4Dy3dDoDHfHASwR9I4
	gEQSVyCGYbj71cMnz/w2MVWWHEqlbniet/xDeY5WawmkwRNDj89/+uGx/UEQfCHJGJIigR+uXNs2
	MTlTJqG+1b0OUJQmSStNkhagqG91ryOhicmZ8o8/Xx0iAZKytVqNY2Nj2vDowK3uQiFP80yn3nnr
	y55SMB3HSQ4AhUKX93crfOzQ0fef9z3L9evW3paAWq3GlSIBgJPzWuESXjt88jljuAMd3JKck4vj
	xPb0BP9dpAOHjp++Xv+z4nnGyIkPCA2V585tGVzfOP3xuwd831+eh39MYynLsh0zN272W8v8oc4C
	yDJ5mzeuvWOt/ZpkSxLvAztZfXp76cwzAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC50lEQVR4nG1S
	TWhUVxg95777ZsZM58ckorSxUg0afwihG1HciTaidKlQlCqCCmn9aaNuKjOvkQqCCC5cCBbtxkKL
	KFiUunChLUHFuDMSTbSmIRGTzORl3uT93a+LzLQj9Kzu4d7zfd+53wEAiMj2nuN9Axu7d08e/KbY
	LyI/HDxW7N/YvWfq0Ht892TP8b4nIrKjpiNFJH3u4pUff/r51k7LIghi9arl7rPnwxkRAdnAIYhi
	wZe7dlz/tmfvHpKeBqBnZipNJMRSykBEjY29TZIQRQIExsbfJua5MsbEambWawJgAYACAEEdQgGY
	WpAQABSAAGhrDdTOIsKkrVM1DgUgymU+8IMwYhwbAMD4xLvkvyUFWJBKKZKoW2pemCOACAA0yYqI
	XJqeLq2998ejVdXqnFiWxXnpfOOp6bICgDk/UGs7VphD+3b9StITEaVERJH8/fR3R77qWtfxdxBG
	JBmHkWEQxgzCiKUZ1yIZk8TCXHYEwJ36hBr/4XE2k34hwrZPO1c/nJwqtYGYtyLwW5rzo/f7n27I
	57KjAEp1h7rhD6utzfk3VIQxJvHLlfO9ACZqd4sPHC2coCIWteT/AlCud1UNE6iuzjVJAiiV3fay
	664cHBpuHRwabi277spS2W0ngK7ONcn6CgFAF4tFAhDP87uvXruxVSng5as3uc+/+LqvoThmZytQ
	Crh67cbWTeu7PgNws1gsUjmOIwDw5+OBjsGhkbyttWQzaROFUTXwAy/wAy8Ko2o2kza2tmRwaCT/
	oH+gAwAcxxFdKBToOI58/NGS8VQqYcIwNme/7/0tk06/9OeCGACSqYTlViorDp88s922LbW0bckE
	ABQKBTZuAcaI8ryq6uk9vVkpbgHJWprEGDG+H+hMJt0oAWs5MGEYbtt/+NTlFyOjLZallBjhew8V
	JY6Naf+kbfLyhb79tm3fFhFFESFJEZGmKIq2DL8eW6w1Y/wPokis5cs+nNBa360lkf8AmLVo/tAl
	FiYAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC30lEQVR4nH2T
	X2gUVxTGv3Pnzs7szmZjmoghxq6RIAZ8CZRCBVspaCkqSCkLIupDUDRCBME/FNLdRH1SX6QtVBT/
	tFAa9EERfQh9aC00VEgEW41ojPFfDO5qspvZ2dm5c48vq06j9Lzch8P9znd+97tApJiZauf67r2H
	hj/5YlNh196Dw8y8LtqPloheJiJmZufo96e3Xhsa6fSrfsMfQzc6j313ZiszJ2t9eq9AdELZrdQR
	wNIwFAFcDYImANW50+cKEBExgHQymVisdQgiIcJQUTLptAJYy8z23FVExL5m5safBy71nr80uDRU
	irxKxbBiJv9y4Ur7lh0HTriu/zkRcS6Xo3ccSMPArdGxTT+evfB1qeRixcedpcWLWnwiwkyxhGqg
	6izLsAAgl8u9XYGZBRFxoFTzuV8vZvIvZuTyjvZbJ4/3/2TbVuB5PhERWprnF6SU4//HoGP07oNl
	VszE2jWfXgZwmTX7bemFKm5b+p/bd1PForuQmf8DXr62M/boaXP+5cv6OieOVSs+uikNcVWF+qt8
	/sWGDZt391T8aqLs+4l6SmoAbxm8FljQkAobUikUS7P48++RjfnC9OGZUmnV4O9DS2bdsojbVui6
	5c+YeU30NWhgYMDIZDKh53ldW3Z+c+Lf0XvCcRzUp5IgITA9XYTv+7CsGGKm1G3p1sIPR77dlko5
	F5lZiEwmowHg2l/DTQ+fPBPxuM1O3FIV31ee5yknYYeNH9QraRjlWdcTd8Ym5l8fudFRCw7LbDZL
	fX19nP6wZSoWk0xgdfTwvt+aGuZVA6WE1hwyeGpy8nllf9+x7bYdi6UXtU4CQDabJRklqjVT2fPN
	7j39K0HEYCYmMIFAREalUrVNUyLU+g1EquVAB0HwZVdP76l7448bDUMIMAuAGKjFlqDDkHV7W2vh
	1PGDXaZpXmVmQZFfmFBKrb4/8XSBlBTODQwAKMXGknTLlJRykIjKzEyvAGEadeodGZF4AAAAAElF
	TkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC/UlEQVR4nF1T
	TWhUZxQ993vvffPy3puIJPNMRintIjrpaJoQXQih4qIguBCtDZQq1YViutCalaKQGRV/d7oqlW5U
	rAgiWkTQSpXaVipVUtAoGOIPJJqfZsZ5r28m7/uuCzPDmAt3d+7h3HPuJdQVMxMRgQDWzO2jbyaW
	A0Cr33yfiB4DIGYGEXF1xsScMoTgIAzX9+8/vu/B4FAGALo6MkNRNHPIcRKXAVA9vkbAzIKINDNn
	+vcfy127ebcj6TUAAK7d/L0bQF4p9YiInlaxACCqBLlcDgDw+vVk+8PBoU89x9b7dm0/svf7bUc9
	x9YPBh+1j42Nd9ZjawqYmQhgzuXkxNT0CqW1kZAWL+9eNh/QSEgLAJkVFTfMXdmcZSTk87ocRV/s
	2nO4b7rwlizLxOa+PTuIgLelUC9KN5JtWa0AkM1maz6IerY4jklrjh3H1gCjWCyhWCyBmcXChX7o
	NzU/Z+YPTBSzCpiZyXXdW+dPn9i6/duv/iyFZepalhnuXJoZjjVjzeqe2zBwsT7CGgER8WyHAG4M
	j7xUsVJY0vZJYXHbx8VKZQb//Pv4IwAbmHleb2+vqnkwezzMzA1xHH8+MTXdM/JytMuWFq5e/62D
	WdO8Rodv3bmXXT+084eeld2/MvNZANcBlKmaaTEI1n3Xf+DH4eevUkEQQggBzQDAMIQBpRRmYgUi
	wmfZtsmfTh3cYtv2L6K60737g+1Pno2kwvB/9lNNcWPSK3uuHSQ9LzBNI+xcmnmxu2/THSmN6NnI
	q6a7fz/MEAHmwMAA5fN5Tvv+G1tKFkTl47n+G8mkV65ElYhMAa1YtCxontI6/u/0mUsrpGVyq++P
	M79/DkFEOgiCDes27bwwOjZhOq5dEkSCiAThvUKlFbGGCKNItvjN6sq5kxtd170sADAAOI7zx9df
	rr2QbkmVElLalmUlTMO0DMOQhmHIhJSWbUtKL0iVvtm49mfHcf7C3M9i5nShUFg1PjntCkN8kDcA
	aAVq8eeXPM+7TUSjzEzvAAQ2XACGc81/AAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADG0lEQVR4nE1T
	TWhcVRT+zr33zXN+3rTDMJkxuhIVRRCKq4pQs+kiK9MoptGNMtmJUEktCO1kcCERxVLwB0EXImoi
	JqsarDsXZu2iXbSkxHEmmUkzTfLeZN68uT/HxUyg3+bAd375zjkEAMxMAAhAup8k5yUA3/dvLS0h
	BoClJaSTJDmPMQ8gBsBExACA1dVVOS40NVe93LlYXWwz8xTGYOapi9XF9lz1cueEP8lRzExEZJm5
	3GjuXthutCYYjDt3t+a3G61JALhzd+vV+41WmUBoNHcvMPNtItpjZqJxh8p3P65dX1nfeO3gMPQI
	IN9PEY3cYGYkyZAZ4MLpvJ6bmV5/9+2ZDwC0BQAcRtHZn3+7Odvc2fONsWSdI+ecNsb0jTF955y2
	zpExlpo7Hf+XtZuvh2H4EhGxAoBu9+CUNlYVC6dsEGRsLpO2y/XFzSRJmmPhnrxS++xs7zhWUa8v
	BolWcTJ8mZn/JADYae9de+e9q/W9B/su/ViKmMkpTxqtDQgEqQQb4zwChHWWk6ERLzz71P73X3+8
	IADAOUcgwDpHSikSgmgwSBgMq40xxtiUp6SQSsJaNxIGI6MAYDgw23E8QD6Xpa8+v/ZNZaK4yRav
	HITRM/lcNrbO/j7U5uGgPzhXvVRbEELgi0+ufOsrf0MBAJPTzjkIIZAPgj+KhUJnfuHD5a3tZunM
	i8/bLz+9uqEU/dRqtUHAAjMjjHr/lEvFRI2nGa0TQNTv+wACIUQQRpG8t/Wv/K/VeqJWq6kwjv2T
	4xJCpIgIAo+CGUE6RUrJWzeWP7peLJzGUA+hhLhdr9dNNp0ePhrMzCMNrHVEALQxw+5B9Ny9+403
	tdZeuVTsMzNSKf9Mo7mr97sPn7bWaaVk6kRMAoDw+Hhm5q33f2139mU+yGgplUcE1sYwAHhKgZmF
	tVaH0bH3eLlk13648UY+n10XABBkMpvzs9Mrk5VSTykJgDUzG09J6ylpmdkC0EpJTFYmenOz0ytB
	kPkbAGj8TMzMk0dHR+cedA+zQgoGJJzVBABCegxYOOuoMlHs5XK5v4hoh5npfx6Qto1F/+n2AAAA
	AElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAARDElEQVR4nO1c
	e3gUVZb/nXurujsv8iSEhDdMBOKDVUTj6ogj6qLgrDDBRYcZZ0Yc9UP0W3cE9dtJ2g9nVx1lfIvO
	KK6KEmR8Mevg4CegIoioMCIgCAgJhJAnId1dXVX37B9VlXRaggmBbtzJ7+NRX1VX3XN/fe69v3vO
	qQZOYjAzMTMl247vDVzCRHl5uYi/Vl5eLphZ9BLaCZi5A2kBvw8uYcLv9x31s8lE0r9NIoAZBICZ
	WQcwauv2nWM3/n3byLrGpjwAyMvOqjvjtFO2jvzBsPUAthCR1X5rcqEls3FmJiJyD3nM0jeX/+Kt
	d1Zfvuub6iGhcESzbQUAkFIgPTVgDRlUtHvSpeP/l5mfI6LPGSBmBhEljcdkeyAxs7Btu+zWO//7
	7o8+2XRq1DShSQEpiAGPGCZbMVm2gk/XUTr29C8e/q+590opK13y/vEIZGby6TrXNTX97PpZ/3n/
	5m07+6UEfIqI4C4U8bYxETEzIxyJipJThh947rF5v8nK6vOCaZqULC9MymRcXl4uiIijpnnh7Dn3
	3rN5285+aakBG4BwFwgCwERQRFBwPIzcayItNWBv3vZ1v1lz5t1jmuYPiYiPtHInAgmfA915TzFz
	5h+efOHWTzduG5ya4reVUtL7DBGxZdtk24oAZw7UpGRPwiilZGqK396wceuQh5968VZm3khEze6z
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAATXklEQVR4nO1c
	e3wV1bX+1t4zZ05CEgiPhAg3poBEHsEo4eWjkipSeVwRidZn7W1ttT9v4bZFrf7uPcGrtw97q9za
	qj9r9YpoISj1Qa1oG6UI4SkgEFIgvIRAICQBcnLOmdl73T9mJhxCgAA5J+0t348Dw5nZe/b+Zu29
	v7XWngP8DYOZiZmps9vxdwOPMBEKhUTrc6FQSDCzuEDoKcDMJ5AWtALwCBOWFTjttZ2JTn+aRAAz
	CAAzswlg0Jat1UXrP6+69FB9Q08A6JnZ7dBlBflbLr2k3yoAlUTkHC/auTA68+bMTETkHXLhm+98
	8I13Fy+ZsGPX3rxwc8RQSgMApBRISw06ebl9dk66YewfmPllIlrHADEziKjTeOxsCyRmFkqpkuk/
	+sljy1dvGBqzbRhSQApiwCeGSWkmR2kETBNjioZtnP3jR56UUs73yPvHI5CZKWCafKih4Z5vPfjv
	P9tUVZ2dEgxoIoK3ULRuGxMRMzOaIzExJL//gZeffWJmt24Zc2zbps6ywk6ZjEOhkCAijtn2td97
	+MnHN1VVZ3dJDSoAwlsgCAATQRNBw7Uw8s6JLqlBtalqe/aDDz/xuG3bXyYibmvlTgaSPgd6855m
	5q7PPDdn+tr1VRenplhKay39a4iIHaVIKU2AOwcaUrIvYbTWMjXFUmvWb8mb/fxr05l5PRE1enUn
	1RKT/tRKS92h6TjOtYs//nScIDBwXJYQgWO2Q13Tu9iFQwfuKBwycEfX9C52zHaIKH6uYyGI+YPy
	T8c5Dr4MAKWdMCUl3QJnzSLNzDRn/rvXHzhYn2YYkj0ZAyKwbSu6fNillU88+r2n+16UvQwAvth3
	4MrHnvif76/buOXSgOlezwwyDINrDx5O/93C965n5veISCe7P0klMG6Iddu8ZVuB4zgImAa737vk
	5fbpfeiVZ598VErxe61dg5NCbHKUOjTp9u+++MXeAz1Mj0R3HnVo05ZtBQC6AahP9jBO9hD2h1jm
	ocMNWXyiDGYGMGrEsAoAH2rNxMySmaXSmgB8OLpoWIWva44XYtTV1WfBJTD+HklBZwlpw7GVd2+X
	C2ZASomM9LQ6ABGPXO2eYwCIZKSn1Ukh49wP98C2lQnATF7zj6OzfMrmlBQr7B66BkMEOI7Cri9q
	BgLoRURcVlYmysrKhDcke+7es/8SRzmgFhtzD7y6mpPcBwDJt0Dfdg5f1LvXF0RUGGeBZBiCK1Zt
	GF6xZv19zPwLImpyz3GX5avWf7tizYbh8YsOwCAiXJTTaw+Aulb3SAqSSqBnSWSaRtP7f1q64r3F
	SyZ5XgQAkBTETU3hwKOPz35o2uRx+Rsqq5YAwK9eev3aBe98dFNTUzhgGKKFQK2ZUoIWxhQVrjAN
	I+zeIrk6MOm6iZmFJ6RH3vHth978fPPWvkHL1MzudEIEdpQmgJDeJQUAcLSpGQDDkCJe8uho1BYF
	QwbumfvCT28holV+3cnsT2fMgexZ3Nq7b5v8RjBowZMr7l8MMoRgKUgfawrjWFMYUpA2hIgbumCt
	GcGghXtKJr8B4DM/qpPsziSdQCJirTURkXPjddf8eurE6/4Us5UAmP3hx+7IEEIICCEAQHjfgYiY
	AR1zlJg66bqPxl9/9a+JyPHqTDqBnSJjvKgKEdFOZn44Gos9/fb7H1+jtY2AaWiAAOYWNjzmGGDE
	bFtIIWXJ5OuXPDLjvoeJaFdn+MA+Oi2g6kdQiGgNM3+nX17fh3735vtT9x04lKG1hiCCNyzBzNDM
	JIRA35zsxttvufGtu27956eIqNKrI+kuXEs/OuvGPkKhkJg1a5Zm5vRwODz+t6+/PWXt+k0jDtTW
	9Q43R7oAQGpKsCk7q0fNFZcNWX3f3VMXWpa1mIiO+mU7s/2dTiBwfGX2jlMA5EWj0by9+2u7A0Cf
	3lmHLcvaCWAnETW3LtOZSHowwTskACgrKyMAKC0FM7MsLS0lj6BK73MSQqGQMXbsWJSWQs+fP18C
	QElJiT//MYBOzZF0OE6X600UkplDTtgN/MbHW4MXks8EkA2gZ339kdxILNoPQKpt6yO2E6th1o5W
	1Ga7hGQmEoZpBHJMU2QACAcDVnVmZsZuAIcAHABQHz+0Q6GQKC0t5URZZYcTGJ+q9P6fCmBgZdW2
	omUr1xX9tXr3oJoDB/scOXIsUynVXWmGUhpEhFgsBqWUditonfJ1tY+UUgQCATAzpBSQQkBKcTgj
	I60+J7vX3oH9ciuvHFm4elD+gNUAqvw5EwlKgXYYgcxMvl4jArTmvjU1tcVl73x448p1n4/es2d/
	7rFwWNq2ghsEcOUJtfwHEK52ObU/4abfoXVLKh7s+r8e3QTTlEhLTVW5uTm7RhQOXVEyedz7OTlZ
	5ULQF+41TMwdN092CIGtVtHczzf/dcrcskUlqz/bOPxQfWOK1tq3Fh03OMlPvh2vp32uGFF8u12B
	Dc+BYWYorYVSGkII9MzsGim6fOjqO0smlhUMHvh7Itrdus3ng/MisNXOgm61tXVTnn7+1W8uXfHZ
	6MbGY4aUBMOQHrFoK9fbZrUd0GYmAoMBRymhNKNrepq6alRhxYwH7nqpd1bWW0TUiA4Y1udMoP8E
	DUPCtp0xL7wy718XvPPhTftrD6eahoCUUreRIGdBBH2a1VFpfdohLMWpF3NBxNofy3H3JCJWSgnb
	0cjOygxPmzzunfu/8bXZpmlUOI46L2s8JwJ935OZ03bt2fv1x3/23PQ1G7ZcAjBMwziJOC98BaW0
	sB0HAdOEECffmoh0akoKE7HAyTQSM+lwc7OfYD8BWjNitg3TMCCl8Hc4xF/HRMS24wiAMHzY4K2l
	jzzwzD/1yXmViI6dqz991gTGkfelBW9/8PBzv513T21dfUowYGqQm25sqZxIa63JdhQZhoHMjLTm
	Qfn96yr/uj37cP0R0zAkvCGkbVuJ8deN+einoR+8vKlyu2mZJkN6K7Eiito2DRnU335k1i/u/eOf
	lo0zTak9y4HjKHTPzLAHDex/oLJqe4/6I8dSHMeBaUgWQnA8kd7Q5kjMFlm9uocfuPfWOdNuGv9T
	ItpxLiSelSfiO+7MnDf7+Tm/fHXeuxOVUghaAc3MwrcZ9+ED0ZgtglYAgwb223nN6KKP75g2cVEk
	Eh1+y70zZvqrMABorcmyTFx71YhlUtDr+hRdEAS8u/iT/PKlq8Y5juOtvu4ibttKhGZ+97Vg0Frz
	+oJFE5dWrB5btX1XXiQao4BpsL+Nzp+Lg1ZA19U1pP549kvf2VtT25eZHySinWfrX5+tBZKUgj9d
	sfaH//bYU081NzezYRjxLppnTY6QUqJgyCXbbp3y1QUTrr9mIYD1XTPSo48+/sycNxa+f5cphWY3
	HsmOo+iinF7HFs599mtB03y/vLxcfPzxxyd0YuzYsaK4uFgfi0QmlNwz/Y19NQfTDEOy+7ygbaXF
	7Tff+Np//ceMuxuPHLUAXPaHxZ/cPP/3H5R8Xrmtv1IKpmnoE62R2HEcpKSk0NNPzpx51agrfu5t
	J2m3FbbbAn3zdhwlfvni3KGRSFQbhsnM7p4W3+oiUVvk9sluuHPapPl3lEz8DYA1cRIn/77poRFa
	a8AQrvAgsGamvNy+2y3D2AhAjx07FsXFxScQWFpaCgC6i2V9npfbd/sX+2ov8w0QBGitsW3H7hGN
	R47mE1EVgJXMvGrCDde+9fqCRd+aW/berbv3HuhmBeKtkckwTBWJRGnl2o1DHUf5I6zdQ7nd/qlf
	YTBo6T45WbUkSDBrEEELIu04ijSDxhePWfnO68/ef0fJxBlEtIqIdHl5uQGAauvqCnbt2XexEOTL
	GjADhjRQMHjAWgB7/efV1jP0/t07bPCAtYY0WnwVZpAQhF179l1cV9dQAIDKy8sNImIiWnXHtIkz
	Fs6Zff8NY0ev0gxyHEWCSLuCQIMEiT45WbXBoKXj+9qhBLoNZRGNxjB10ri3iwqHVEeitozFHNEc
	jYmM9PTYjPvvfOXn/znzXsMw5hFRs+/QFxcXO0HL4vKlq0bVNx4NGtIdegCgtRZpaUF99cgrKojI
	OdXTj4tiO1eNvKIiLS2otdZ++8mQkusbjwb/vLRiVNCyuLi42PEDGUTUbFnWvP9+4qGvT//2na9k
	pKfHmqMxEYs5IhK1ZVHhkOqpk8a9HY3Gznr/9VktIr55A1j2wi9C0382+zf3V27d2b97Zrf6u26b
	9NblQy99iYjq4xx47UVhuDkS6fnIrKdHRGMxWAHDW3yhHaVFn97ZNQVDBq71b4MzOHMFQwau6dM7
	u2ZT1fY+lhSaGYIIHI3FaPW6zSObI5GeRHSotLSUvGAteaGySmb+/rCC/E2vzXtv6uH6hszBA7+0
	beb3vvkCgGX+1ruz4uRsLm4NZu4KIAvAMdMwahx1siiNS2NedcvXZyzcVr27VyBg+J3WMVuJKROK
	F8965MFb6Qx7/OIkVNfSn/xq3sI//Hl8wJTH64o5YkC/3INv/u8zNxPRp6dqiyElbMfJAZAGoNbz
	Ss4J5xyj8zrTSERbicgn76QnSOSmMSvWbCg6UFvXU0oJPwesNVPQCqDo8oIVgYDZiDMkxr1zFAiY
	jcMvH7wyaAWgNftzqZBS4kBtXc+KNRuKyI1LcKvympnJUQpEVOO1vfF84obnTKA/J8UHLlt33v2e
	WGttLV+xbnRTuJmkaCGYldLUo3vXYzded9UK23YQCoXO2JFQKES27eCG665Z0aN712PxskMK0k3h
	Zlq+at1orbXluronkuO3Mb7t5+MLn1eU2Fvl9Gka4Df+4k1V2wqV1i3fePIFebl9txuufPGlymnh
	X2MZxsa83L7btSuk2b+b0hqbKrcVAri4VRvOtu3tQkLD7H5na+sahu3eU5N3jvKlNc4oZ3bvqcmr
	q2sYFt+GRCGhBPor4CdLK85ZvrRGe+XMh0uWj2ZmSnTaM2EExiWReqxZVzkiGou1DDVPvqAN+dJe
	EAD4csZRrqD36uZoLIbPNlSOANCjVVs6HAmrOG7o5G+t3jW4NTsEQv6AvM0AtjOzhPeOSHs+3rUS
	QHX+gLzN1Ip7ArCtevcgAPmt2tLhSBiBZ5QvKRaGDBrwKRHVE5EiIseb1Nvzcbwy9UMGDfg0mGKd
	lZzpSCQkse7PZ1qz9fSvXx3dFG4mw4u+uPv/mLK7ZdSV3DS+mpmvBpAKoAFAI9oX0u8Kd1N5GED1
	y3MX1u07cKiHabgRek/OCE/OPE9E0URtQErUzgRfm7XIF8OLvjADUhCONoXlAz94PGSYRm/HUSJg
	ylhTc/SwYzs2CETcSlMSExhsmIbZJcXqHrNVwDCkdmxn/9GmsJSCWlbjVnImF8DWuDZ1KBJCoD/n
	1LUhX+ClIcPhSLelKz7rppTyi6VIKbtS2zn1FripgZYykFL2D5imv5PLH8bxcuYyAFsTNQ8mhMBZ
	s2Zpywrgo78sH9lw5GhQxskXH0TgoBVgIrTMUOz/OS3Iz4d62wjhexvx9ZOUkhuOHA1+9JflIy0r
	sCBRcqbDFxHfdYpEoqL24OEs21Es2o5wEDMLrZk0ux93lcUZPiz8672Xcfy3O0/sGJG2HcW1Bw9n
	RSJREd+2jkSHE+g7/IYh9cgrLtuYErQoZtuCiBTcF2c0EfSpekJETN518R8CTul2EeDrQK9+UjHb
	FilBi0YWFmzyctMJWUQSImNCoRAppTFq+NAFt00Zv6hLago5SkvNEJohbEcLpdseUbbtkKNZaIbQ
	2vswhKNZ2LbTJu9Ka9iOFn79jtKyS2oK3TZl/KJRI4aVKaXbFag4FyR0d5af/lyxZsO01es2DVJK
	Sdt2VO+sXpnvflD+lc1V2zOsQMB3zdi2HZo4/svbB3wpd1lDfSNL052ile2gW2ZX2rZj95WLPljS
	32x5QZE4GovR4Pz+RyaPL/7z/tqD9aZpSCmlKiocUjlq+LAF55qubC8StsEyzmfdQcBT2p2rJAAH
	QP6SZavfZkaGtwvLvVgIGtAvd9k3br/5WwAUjj9gBiBffmPhb0iI/uzmQ93EKIO6pqfvv7Nk4o8A
	VHl9UoJIM054QzQhSOgO1TgS4QVavT6xikZjaC1ZiAgNDY0MwGkdmGVmbmho5LbKRKMxAFAeUQ6O
	/0RAwnerJnyLb3wAE+6cqwGIU+k9KQ3A9XXjpQ8DEN65tu7hl2m5hxfv67iOnAJJ23brEenvFD2T
	VcRfd9ZlEm118fib+Qmlv1dcIPA8cYHA88QFAs8TFwg8T1wg8DxxgcDzxAUCzxOdReCplO5JWzFa
	nTzTzq2ko7MIjFqWGXMdZdHyhiUzU1pqahjeD+60gk5LTQ3HBweIBDMzBywzBiCaxPa3INkE+taz
	7ytXj1waCAQoEo1JrTWawhGZk92j+eaJxZ/Q8bfZOf745onFn+Rk92huCkek1hqRaEwGAgH6ytUj
	lwLY1+oeSUHSzT4uTnjpc7+d9+R7fyy//lhzJLVP7161D95354tXjiz8ObV6byOuTNqylet++OyL
	c+/bu/9gVlpKMDzpq8UfPfAvtz1GRFsSHbr6m4E/zzFzT9u2J2yt3nk3M49h91d8TwpzxX/HzCYz
	j9lavfNu27YnMHPP+Dr/YXCqDrdjETmrMv+v4W9yPJs3zM+lzAVcwAVcwAUkBv8HD2dUjUTIktkA
	AAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAQ7klEQVR4nO1c
	fZBU1ZX/nXvve93T084MyMgIgiL4AVtuiVVrIsEY2BhFBCUKxhVr142RSkVNajV/aEyaSSVSlXV3
	zZpdI2TjbokfASl0FJSF4DdGkw26roICMmAYZxgGZoaZnu73cc/+8d6bedPTH6+bmfEj86vqmp7u
	e+695/S995z7u+c+YAxjGMMYxvCJgJmJmUUqlRLMLJiZRkLmc4lCihczSCUyn0sECjPzBNu2r9jz
	YfONzHwRMxsAQDTUHsFnzGww80V7Pmy+0bbtK5h5QrjO0YYa7QaZmYiImfncB3/9m58++/wLX+3p
	yyQmN9QfvvVbN6xh5vuIqCcolyOT3PHmW3f+Ys2j3zrU2n5KsiqevvLyeduY+QdEtDss87lEaOSZ
	T2zY/OAF85bxeXOX8OxLruGZX1zMC5atSHd0dF4PAKlUSgRywfvDHR3XL1i2Ij3zi4t59iXX8Hlz
	l/AF85bxExs2P8jMZriN0cJoj0ACwAAmbX/1jYsty+KqeExrrWV1Iu5+3NZRtXHTtkuY+Qki0oEx
	gvf/8ciGSz5u66iqTsRdZpZxpdy+TFZsf+XNudd9fcEkAM2hNkYFw2rACL8++WViVtYxvHmpg1FJ
	RMQ96XQCgGRmF54xwMwAIHvS6YQ/lf3PNRERWZZtAoj5n1OpfgznND9hAwadJiKO0DHtibD2jZIL
	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
	HKcAAAAASUVORK5CYII=
}]

} ;# namespace 80x80
} ;# namespace icon
} ;# namespace playercard

# vi:set ts=3 sw=3:
