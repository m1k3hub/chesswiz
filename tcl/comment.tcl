# ======================================================================
# Author : $Author$
# Version: $Revision: 1524 $
# Date   : $Date: 2018-09-17 09:27:59 -0400 (Mon, 17 Sep 2018) $
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
# Copyright: (C) 2009-2017 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source comment-dialog

namespace eval comment {
namespace eval mc {

set CommentBeforeMove		"Comment before move"
set CommentAfterMove			"Comment after move"
set ExplainComment			"Explain this comment"
set DetectLanguage			"Detect language"
set DraftComment			"Draft a comment"
set TranslateComment		"Translate comment to"
set ClassifyComment		"Classify comment"
set PrecedingComment			"Preceding comment"
set TrailingComment			"Trailing comment"
set Language					"Language"
set AddLanguage				"Add language..."
set SwitchLanguage			"Switch language"
set FormatText					"Format text"
set CopyText					"Copy text to"
set OverwriteContent			"Overwrite existing content?"
set AppendContent				"If \"no\" the text will be appended."
set DisplayEmoticons			"Display Emoticons"
set ReallySwitch				"Really switch display mode?"
set LosingChanges				"Switching the display mode will loose the history, this means you cannot undo the last edit operations."

set LanguageSelection		"Language selection"
set Formatting					"Formatting"

set Bold							"Bold"
set Italic						"Italic"
set Underline					"Underline"

set InsertSymbol				"&Insert Symbol..."
set InsertEmoticon			"&Insert Emoticon..."
set MiscellaneousSymbols	"Miscellaneous Symbols"
set Figurine					"Figurine"

} ;# namespace mc


array set Vars {
	dialog		{}
	key			{}
	comment		{}
	content		{}
	langSet		{}
	after			{}
	format		{}
	wantedLang	{}
	countryList	{}
	insert		begin
	lang			xx
	count			0
	emotions		0
}

array set Fonts {
	normal		TkTextFont
	bold			{}
	italic		{}
	bold-italic	{}
}

array set Options {
	useComboBox		1
	menuColumns		3
	showEmoticons	1
}

array set NagSet {
	prefix	{	140 141 142 143}
	suffix	{	  3   4   5   6   7   8
					 13  14  15  16  17
					147 148 149 150 153 154
					157 159 160 165 166 167
					173 174 175 176 178 179 180 181 182 183 184}
}

variable DingbatSet {
	"\u00bd" "\u2212" "\u2026" "\u2022" "\u2139" "\u00a3" "\u20ac" "\u270e" "\u2605" "\u25cf"
}
variable Colors {darkgreen darkred darkblue darkgreen darkred darkblue}

set Symbols [join $::figurines::langSet(graphic) ""]


proc open {parent pos lang} {
	variable Annotations
	variable Vars

	set dlg $parent.__comment__
	set Vars(dialog) $dlg
	tk::toplevel $dlg -class Scidb
	wm withdraw $dlg

	set top [tk::frame $dlg.top]
	set bg [$top cget -background]
	destroy $top

	set top [ttk::frame $dlg.top]
	set main [::tk::multiwindow $top.main -borderwidth 0 -background white]
	pack $dlg.top -fill both -expand yes
	bind $dlg <<LanguageChanged>> [namespace code [list LanguageChanged $dlg %W]]
	bind $dlg <Alt-Key> [list tk::AltKeyInDialog $dlg %A]

	set Vars(widget:main) $main
	set Vars(key) [::scidb::game::position key]
	set Vars(pos) $pos
	set Vars(lang) {}
	set Vars(mc) $::mc::langID
	set Vars(init) 0
	set Vars(background) $bg

	MakeEditor xx

	set butts [ttk::frame $top.buttons]
	ttk::button $butts.symbol \
		-style aligned.TButton \
		-compound left \
		-image $::icon::iconBlackPawn \
		-command [namespace code [list PopupSymbolTable $butts.symbol]] \
		;
	ttk::button $butts.clear \
		-style aligned.TButton \
		-compound left \
		-image $icon::iconClear \
		-command [namespace code Clear] \
		;
	ttk::button $butts.revert \
		-style aligned.TButton \
		-compound left \
		-image $icon::iconReset \
		-command [namespace code [list Revert $dlg]] \
		-state disabled \
		;
	set Vars(lang:label) [LanguageName]
	set Vars(widget:lang) $butts.lang
	set Vars(widget:revert) $butts.revert
	ttk::label $Vars(widget:lang) \
		-compound left \
		-textvar [namespace current]::Vars(lang:label) \
		-image $::country::icon::flag([::mc::countryForLang $lang]) \
		-justify left \
		-relief ridge \
		-background $bg \
		-padding {2 2 2 2} \
		;
	::widget::buttonSetText $butts.symbol [namespace current]::mc::InsertSymbol
	::widget::buttonSetText $butts.clear ::widget::mc::Label(clear)
	::widget::buttonSetText $butts.revert ::widget::mc::Label(revert)

	grid $main	-row 1 -column 1 -sticky ewns
	grid $butts	-row 1 -column 3 -sticky ewns

	grid rowconfigure $top {0 2} -minsize $::theme::pady
	grid rowconfigure $top 1 -weight 1

	grid columnconfigure $top 1 -weight 1
	grid columnconfigure $top {0 2 4} -minsize $::theme::padx

	grid $butts.lang		-row 1 -column 1 -sticky ew
	grid $butts.symbol	-row 3 -column 1 -sticky ew
	grid $butts.clear		-row 5 -column 1 -sticky ew
	grid $butts.revert	-row 7 -column 1 -sticky ew

	grid rowconfigure $butts 2 -minsize $::theme::padY
	grid rowconfigure $butts {4 6} -minsize $::theme::pady
	grid rowconfigure $butts 2 -weight 1

	::widget::dialogButtons $dlg {ok apply cancel hlp}
	bind $dlg <Return> {}

	$dlg.apply	configure -command [namespace code Apply]
	$dlg.ok		configure -command [namespace code [list Ok $dlg]]
	$dlg.cancel	configure -command [namespace code [list Close $dlg]]
	$dlg.hlp		configure -command [list ::help::open .application Comment-Editor-Dialog -parent $dlg]

	::toolbar::setup $dlg -id comment
	set tb [::toolbar::toolbar $dlg \
		-id comment-languages \
		-float 0 \
		-side left \
		-allow {left top bottom} \
		-tooltipvar [namespace current]::mc::LanguageSelection \
	]
	set Vars(tb) [::toolbar::toolbar $dlg \
		-id comment-format \
		-float 0 \
		-side top \
		-allow {left top bottom} \
		-tooltipvar [namespace current]::mc::Formatting \
	]

	foreach format {Bold Italic Underline} {
		set fmt [string tolower $format]
		set Vars(format:$fmt) 0
		::toolbar::add $tb checkbutton \
			-image [set icon::toolbar$format] \
			-tooltipvar [namespace current]::mc::$format \
			-variable [namespace current]::Vars(format:$fmt) \
			-command [namespace code [list ChangeFormat $fmt]] \
			;
	}
	set Vars(addLang) [::toolbar::add $Vars(tb) button \
		-image $::icon::toolbarPlus \
		-tooltipvar [namespace current]::mc::AddLanguage \
		-command [namespace code [list PopupChooseLanguage $dlg]] \
	]
	::toolbar::addSeparator $Vars(tb)
	::toolbar::add $Vars(tb) button \
		-image [::country::makeToolbarIcon ZZX] \
		-command [namespace code { SwitchLanguage xx }] \
		-tooltipvar ::languagebox::mc::AllLanguages \
		-variable [namespace current]::Vars(lang) \
		-value xx \
		;
	
	::update idletasks
	bind $dlg <F1> [$dlg.hlp cget -command]
	wm transient $dlg $parent
	catch { wm attributes $dlg -type dialog }
	wm resizable $dlg true true
	wm protocol $dlg WM_DELETE_WINDOW [namespace code [list Close $dlg]]
	# TODO need correction for minimal height, why?
	wm minsize $dlg [winfo reqwidth $dlg] [expr {[winfo reqheight $dlg] + 40}]
	::widget::dialogGeometry $dlg $parent
	Init $parent $lang
	wm deiconify $dlg
	focus [$main raise].text
	ttk::grabWindow $dlg
	tkwait window $dlg
	ttk::releaseGrab $dlg
}


proc MakeEditor {lang} {
	variable Fonts
	variable Vars

	if {	[info exists [namespace current]::Vars(widget:text:$lang)]
		&& [winfo exists $Vars(widget:text:$lang)]} {
		return $Vars(init:$lang)
	}

	if {![info exists Vars(init:$lang)]} { set Vars(init:$lang) 1 }

	set f [tk::frame $Vars(widget:main).f-$lang -takefocus 0]
	$Vars(widget:main) add $f

	set t [tk::text $f.text \
		-height 6 \
		-width 0 \
		-background white \
		-font $Fonts(normal) \
		-wrap word \
		-font $::font::text(text:normal) \
		-yscrollcommand [list ::scrolledframe::sbset $f.sb] \
		-undo no \
	]
	set Vars(widget:text:$lang) $f
	::scidb::tk::misc setClass $t Comment
	set s [ttk::scrollbar $f.sb -command [namespace code [list ::widget::textLineScroll $t]]]
	bind $t <<Altered>> [namespace code [list EditAltered $t]]

	set font $Fonts(normal)
	set fam [font configure $font -family]
	set size [font configure $font -size]
	foreach {attr args} {bold bold italic italic bold-italic {bold italic}} {
		set ft $Fonts($attr)
		if {[llength $ft] == 0} {
			set ft [list $fam $size {*}$args]
		}
		$t tag configure $attr -font $ft
		if {$attr eq "bold"} { $t tag configure codeb -font $ft }
	}
	# XXX possibly we can use only {Scidb Symbol Traveller}
	$t tag configure figurine -font $::font::figurine(text:normal)
	$t tag configure figurineb -font $::font::figurine(text:bold)
	$t tag configure symbol -font $::font::symbol(text:normal)
	$t tag configure symbolb -font $::font::symbol(text:bold)
	$t tag configure code -font [list $fam $size]
	foreach tag {figurine figurineb symbol symbolb code codeb} {
		$t tag configure underline -underline no
	}
	$t tag configure underline -underline yes

	bind $t <ButtonPress-3>	 [namespace code [list PopupMenu $t]]
	bind $t <Any-Button>		 [list $t configure -cursor xterm]
#	bind $t <Any-Button>		+[list ::tooltip::tooltip hide] ;# TODO: needed?

	grid $t -row 1 -column 1 -sticky ewns
	grid $s -row 1 -column 2 -sticky ns

	grid columnconfigure $f 1 -weight 1
	grid rowconfigure $f 1 -weight 1

	return 1
}


proc EditAltered {w} {
	variable Vars

	if {[$w edit altered]} {
		set bg [::colors::lookup comment,label:altered]
		set fg [::colors::lookup comment,label:foreground]
	} else {
		set bg $Vars(background)
		set fg black
	}
	$Vars(widget:lang) configure -background $bg -foreground $fg
}


proc AddLanguageButton {lang} {
	variable Vars

	set countryCode [::mc::countryForLang $lang]

	if {[info exists ::encoding::mc::Lang($lang)]} {
		set languageNameVar ::encoding::mc::Lang($lang)
	} else {
		variable _LanguageName_$lang
		set languageNameVar _LanguageName_$lang
	}

	set w [::toolbar::add $Vars(tb) button \
		-image [::country::makeToolbarIcon $countryCode] \
		-command [namespace code [list SwitchLanguage $lang]] \
		-tooltipvar $languageNameVar \
		-variable [namespace current]::Vars(lang) \
		-value $lang \
	]
	set Vars(tb:$lang) $w
}


proc MakeLanguageButtons {} {
	variable Vars

	set langButtons [array names Vars tb:*]
	
	foreach button $langButtons {
		::toolbar::remove $Vars($button)
		unset Vars($button)
	}

	foreach lang $Vars(langSet) {
		AddLanguageButton $lang
	}
}


proc Accept {} {
	variable Vars

	set lang $Vars(lang)
	SetUndoPoint $Vars(widget:text:$lang).text
	set Vars(comment) [::scidb::misc::xml fromList [ParseContent $lang] -replacewithspace \u2423]
	::scidb::game::update comment $Vars(key) $Vars(pos) $Vars(comment)
	if {![info exists Vars(remember:$lang)]} { set Vars(remember:$lang) "" }
	unset -nocomplain Vars(detectedLang) Vars(detectedText) Vars(detectText)
	SetRevertState $lang
}


proc Close {dlg} {
	variable Vars

	destroy $dlg
	array unset Vars tb:*
	set Vars(langSet) {}
}


proc Clear {} {
	variable Vars

	set w $Vars(widget:text:$Vars(lang)).text

	if {![$w isempty]} {
		SetUndoPoint $w
		$w delete begin end
		focus $w
		set Vars(count) 0
		set Vars(emotions) 0
		set Vars(content:$Vars(lang)) {}
		set Vars(remember:$Vars(lang)) {}
		SetRevertState $Vars(lang)
	}
}


proc SetRevertState {lang} {
	variable Vars

	if {$Vars(remember:$lang) eq $Vars(content:$lang)} { set state disabled } else { set state normal }
	$Vars(widget:revert) configure -state $state
}


proc Revert {dlg} {
	variable Vars

	set w $Vars(widget:text:$Vars(lang)).text
	SetupComment $Vars(lang) $Vars(normalized:$Vars(lang))
	SetUndoPoint $w
	$Vars(widget:revert) configure -state disabled
	focus $w
}


proc GetComment {} {
	variable Vars
	return [::scidb::game::query comment $Vars(pos)]
}


# C1: explain the comment currently being edited.  The stored text is read
# through the same query the editor uses, so the explanation matches what is
# on screen.
proc ExplainComment {parent} {
	variable Vars
	::application::ai::explainSelection $parent comment [list $Vars(pos)]
}


# A2: detect the language of the comment being edited and, when the current
# slot is the neutral one, carry its text into the detected language slot.
proc DetectLanguage {parent} {
	variable Vars

	if {[llength [info commands ::ai::language::detect]] == 0} { return }
	set text [PlainComment [GetComment]]
	if {[string trim $text] eq ""} { return }
	set Vars(detectText) $text
	::ai::language::detect $text [namespace code [list OnDetected $parent]]
}


proc PlainComment {comment} {
	if {[llength [info commands ::ai::factcheck::plain]]} {
		catch { return [::ai::factcheck::plain $comment] }
	}
	regsub -all {<[^>]*>} $comment " " text
	return $text
}


proc OnDetected {parent decision} {
	variable Vars

	if {![dict get $decision ok]} { return }
	set lang [dict get $decision label]
	if {$lang eq "" || $lang eq "xx"} { return }

	set source $Vars(lang)
	if {$source eq $lang} { return }

	set entries [ParseContent $source]
	set carried {}
	foreach e $entries {
		lassign $e code content
		if {$code eq "" || $code eq $source} { set carried $content }
	}
	if {![llength $carried]} { return }

	if {![info exists Vars(tb:$lang)]} {
		if {[lsearch -exact $Vars(langSet) $lang] < 0} { lappend Vars(langSet) $lang }
		AddLanguageButton $lang
	}

	# remember what the classifier proposed, so a later switch to another
	# language is recorded as an override for the calibration autotune
	set Vars(detectedLang) $lang
	set Vars(detectedText) [expr {[info exists Vars(detectText)] ? $Vars(detectText) : $carried}]

	SwitchLanguage $lang
	set Vars(content:$lang) $carried
	set Vars(init:$lang) 0
	SetupComment $lang $carried 1
	set Vars(content:$source) ""
	return
}


# C1: draft a grounded comment for the current position and put it in the
# editor for review.  Nothing is saved; Accept is still the user's decision.
proc DraftComment {parent} {
	variable Vars

	if {[llength [info commands ::application::ai::generate]] == 0} { return }
	set fen [::scidb::pos::fen]
	::application::ai::generate $parent "Draft comment" "Drafting a comment..." $fen \
		-context "Draft one or two sentences of annotation for this position, in the style of a chess author's database note. Ground every statement in the facts given; name only moves that are legal." \
		-observer [namespace code [list OnDraft $parent]]
	return
}


proc OnDraft {parent result} {
	variable Vars

	if {![dict get $result ok]} { return }
	set text [string trim [dict get $result text]]
	if {$text eq ""} { return }

	set lang $Vars(lang)
	set w $Vars(widget:text:$lang).text
	if {![winfo exists $w]} { return }

	if {[string length [string trim [$w get 1.0 end-1c]]]} { $w insert end "\n" }
	$w insert end $text
	focus $w
	return
}


# C2: translate the comment into another language slot, for review.  A
# transformation of existing text: no facts are added or dropped, and the
# ordinary Accept still stores it.
proc TranslateComment {parent lang} {
	variable Vars

	if {[llength [info commands ::application::ai::generate]] == 0} { return }
	set text [PlainComment [GetComment]]
	if {[string trim $text] eq ""} { return }
	set name [expr {[llength [info commands ::ai::language::Name]] ? [::ai::language::Name $lang] : $lang}]
	::application::ai::generate $parent "Translate comment" "Translating the comment..." [::scidb::pos::fen] \
		-context "Translate this chess annotation into $name. Keep every chess move and fact exactly as it is; do not add or drop information, and do not evaluate.\nCOMMENT:\n$text" \
		-observer [namespace code [list OnTranslated $parent $lang]]
	return
}


proc OnTranslated {parent lang result} {
	variable Vars

	if {![dict get $result ok]} { return }
	set text [string trim [dict get $result text]]
	if {$text eq ""} { return }

	if {![info exists Vars(tb:$lang)]} {
		if {[lsearch -exact $Vars(langSet) $lang] < 0} { lappend Vars(langSet) $lang }
		AddLanguageButton $lang
	}
	SwitchLanguage $lang
	set w $Vars(widget:text:$lang).text
	$w delete 1.0 end
	$w insert end $text
	focus $w
	return
}


# A3: classify what the comment is about (opening, tactics, endgame, plan,
# evaluation, warning).  Read-only; the result is reported, never stored.
proc ClassifyComment {parent} {
	variable Vars

	if {[llength [info commands ::ai::comment::kind]] == 0} { return }
	set text [PlainComment [GetComment]]
	if {[string trim $text] eq ""} { return }
	::ai::comment::kind $text [namespace code [list OnKind $parent]]
}


proc OnKind {parent decision} {
	variable Vars

	if {![dict get $decision ok]} { return }
	set kind [dict get $decision label]
	catch {
		::dialog::info -parent $parent -title $mc::ClassifyComment \
			-message "[::ai::comment::Name $kind] ([dict get $decision source])"
	}
}


proc GetNormalizedComment {} {
	variable Vars

	set comment [GetComment]

	set content [::scidb::misc::xml toList $comment \
		-expandemoticons [ExpandEmoticons] \
		-detectemoticons [DetectEmoticons] \
		-replacespaces "\u2423" \
	]
	set content [lindex $content 0]

	foreach entry $content {
		lassign $entry lang comment
		if {[string length $lang] == 0} { set lang xx }
		if {$lang eq $Vars(lang)} { return $comment }
	}

	return ""
}


proc Apply {} {
	variable Vars

	Accept
	focus $Vars(widget:text:$Vars(lang)).text
}


proc Ok {dlg} {
	Apply
	Close $dlg
}


proc Init {parent lang} {
	variable Vars

	foreach l [array names Vars content:*] {
		set Vars(init:$l) 0
	}

	set Vars(comment) [GetComment]
	set Vars(langSet) [::scidb::game::query langSet]
	array unset Vars content:*
	array unset Vars symbol:*

	foreach l $Vars(langSet) {
		if {[info exists Vars(widget:text:$l).text]} {
			set w $Vars(widget:text:$l).text
			$w delete begin end
			$w edit reset ;# XXX
		}
	}

	lremove Vars(langSet) ""

	set content [::scidb::misc::xml toList $Vars(comment) \
		-expandemoticons [ExpandEmoticons] \
		-detectemoticons [DetectEmoticons] \
		-replacespaces "\u2423" \
	]

	foreach comm [lindex $content 0] {
		lassign $comm l value
		if {[string length $l] == 0} { set l xx }
		set Vars(content:$l) $value
		set Vars(remember:$l) $value
		set Vars(init:$l) 1
	}

	SwitchLanguage $lang yes
	LanguageChanged $Vars(dialog) $Vars(dialog)
	UpdateFormatButtons $Vars(widget:text:$lang).text
	MakeLanguageButtons
}


proc SwitchLanguage {lang {setup no}} {
	variable Vars

	if {$lang eq $Vars(lang)} { return }

	NoteLanguageOverride $lang
	foreach fmt {bold italic underline} { set Vars(format:$fmt) 0 }
	set Vars(format) ""
	set Vars(lang) $lang

	if {[MakeEditor $lang]} {
		SetupComment $lang [GetNormalizedComment] $setup
	}

	set w $Vars(widget:text:$lang).text
	set Vars(lang:label) [LanguageName]
	$Vars(widget:lang) configure -image $::country::icon::flag([::mc::countryForLang $lang])
	$Vars(widget:main) raise [winfo parent $w]
	EditAltered $w
	focus $w
}


# If the classifier proposed a language and the user then switched to a
# different one, that is a rejected label: record it for the calibration
# autotune (tcl/ai-journal.tcl). No journal, or a switch to the proposed
# language, records nothing.
proc NoteLanguageOverride {lang} {
	variable Vars

	if {![info exists Vars(detectedLang)] || $lang eq $Vars(detectedLang)} { return }
	if {[llength [info commands ::ai::journal::override]]} {
		catch { ::ai::journal::override language $Vars(detectedText) $Vars(detectedLang) $lang }
	}
	unset -nocomplain Vars(detectedLang) Vars(detectedText) Vars(detectText)
	return
}


proc SetupComment {lang comment {setup 0}} {
	variable Vars

	if {$lang eq ""} { set lang xx }
	set Vars(content:$lang) $comment
	set Vars(init:$lang) 0
	set Vars(normalized:$lang) $comment

	set w $Vars(widget:text:$lang).text
	$w delete begin end
	$w configure -undo no

	if {$lang eq $Vars(lang)} {
		if {[info exists Vars(content:$lang)]} {
			InsertComment $lang $Vars(content:$lang) $setup
		}
	}

	$w configure -undo yes
}


proc InsertComment {lang content {setup 0}} {
	variable Vars

	set w $Vars(widget:text:$lang).text
	set Vars(symbols) {}
	set Vars(count) 0
	set Vars(emotions) 0
	set Vars(init) 1

	set fmt [list 0 [$w index current]]

	foreach entry $content {
		lassign $entry code text

		switch -- $code {
			str { $w insert end [string map {"<brace/>" "\{" "\n" "\u00b6\n"} $text] }
			emo { InsertEmoticon $w $text no }
			nag { InsertNag $w $text [expr {[lindex $fmt 0] & 1}] }
			sym { InsertFigurine $w $text [expr {[lindex $fmt 0] & 1}] }

			+bold - +italic - +underline - -bold - -italic - -underline {
				set fmt [UpdateAttrs $w $fmt $code]
			}
		}
	}

	UpdateAttrs $w $fmt
	$w tag raise figurine
	$w tag raise figurineb
	$w tag raise symbol
	$w tag raise symbolb
	$w tag raise code
	$w tag raise codeb

	set Vars(init) 0

	if {$setup} {
		set Vars(dump:$lang) [ParseDump [$w dump -tag -image -text begin end]]
		$Vars(widget:revert) configure -state disabled
	}
}


proc UpdateAttrs {w fmt {code ""}} {
	lassign $fmt flags pos
	set attrs {}

	if {($flags & 3) == 3} {
		set attrs bold-italic
	} elseif {$flags & 2} {
		set attrs italic
	} elseif {$flags & 1} {
		set attrs bold
	}

	if {$flags & 4} {
		lappend attrs underline
	}

	if {[llength $attrs]} {
		set end [$w index current]
		foreach attr $attrs {
			$w tag add $attr $pos $end
		}
	}

	switch $code {
		+bold			{ set flags [expr {$flags | 1}] }
		+italic		{ set flags [expr {$flags | 2}] }
		+underline	{ set flags [expr {$flags | 4}] }

		-bold			{ set flags [expr {$flags & ~1}] }
		-italic		{ set flags [expr {$flags & ~2}] }
		-underline	{ set flags [expr {$flags & ~4}] }
	}

	return [list $flags [$w index current]]
}


proc InsertFigurine {w fig {boldFlag {}}} {
	variable Vars

	set useFormatting [expr {[llength $boldFlag] == 0}]
	if {$useFormatting} { set useBold $Vars(format:bold) } else { set useBold $boldFlag }
	set Vars(symbol:[incr Vars(count)]) $fig
	set text [string map $::figurines::pieceMap $fig]
	set key key$Vars(count)
	set tag figurine
	if {$useBold} { append tag b }
	$w tag bind $key <Enter> {}
	$w tag bind $key <Leave> {}

	InsertText $w $text [list $tag $key] $useFormatting
}


proc InsertNag {w nag {boldFlag {}}} {
	variable Vars

	set useFormatting [expr {[llength $boldFlag] == 0}]
	if {$useFormatting} { set useBold $Vars(format:bold) } else { set useBold $boldFlag }
	set Vars(symbol:[incr Vars(count)]) $nag
	set key key$Vars(count)
	lassign [::font::splitAnnotation $nag] value sym tag
	if {$tag eq "symbol"} {
		set tag symbol
	} else {
		set tag code
		if {[string is digit -strict $sym]} {
			set sym "{\$$sym}"	;# use something like a question mark instead
		}
	}

	if {$useBold} { append tag b }
	InsertText $w $sym [list $tag $key] $useFormatting

	$w tag bind $key <Enter> [namespace code [list TooltipShowNag $w $key nag $value]]
	$w tag bind $key <Leave> [namespace code [list TooltipHide $w]]
}


proc InsertEmoticon {w text {useFormatting yes}} {
	variable Options

	if {$Options(showEmoticons)} {
		variable Vars

		set selrange [$w tag ranges sel]
		set emotion [::emoticons::lookupEmotion $text]
		set Vars(symbol:[incr Vars(count)]) $emotion
		set key key$Vars(count)
		set mark insert
		if {	[llength $selrange]
			&& [$w compare insert >= [lindex $selrange 0]]
			&& [$w compare insert <= [lindex $selrange 1]]} {
			$w delete {*}$selrange
			set mark [lindex $selrange 0]
		}
		$w image create $mark -image $::emoticons::icon($emotion) -name $key
		if {$useFormatting} {
			DoFormatting $w $mark $mark
		}
	} else {
		InsertText $w [::emoticons::lookupCode $text] {} $useFormatting
	}
}


proc InsertText {w text tags useFormatting} {
	SetUndoPoint $w
	set selrange [$w tag ranges sel]

	if {	[llength $selrange]
		&& [$w compare insert >= [lindex $selrange 0]]
		&& [$w compare insert <= [lindex $selrange 1]]} {
		set pos [lindex $selrange 0]
		$w replace {*}$selrange $text $tags
	} else {
		set pos [$w index insert]
		$w insert insert $text $tags
	}

	if {$useFormatting} {
		DoFormatting $w $pos [$w index current]
	}

	SetUndoPoint $w
}


proc DoFormatting {w start end} {
	variable Vars

	if {$Vars(format:bold) && $Vars(format:italic)} {
		set fmt bold-italic
	} elseif {$Vars(format:bold)} {
		set fmt bold
	} elseif {$Vars(format:italic)} {
		set fmt italic
	} else {
		set fmt {}
	}
	if {$Vars(format:underline)} {
		lappend fmt underline
	}

	if {[llength $fmt]} {
		foreach f $fmt {
			$w tag add $f $start $end
		}

		$w tag raise figurine
		$w tag raise figurineb
		$w tag raise symbol
		$w tag raise symbolb
		$w tag raise code
		$w tag raise codeb
	}
}


proc PasteText {w {str ""}} {
	variable Symbols

	if {[string length $str] == 0} {
		set str [::clipboard::getSelection]
		if {[string length $str] == 0} { return }
	}

	if {[tk windowingsystem] ne "x11"} {
		catch { $w delete sel.first sel.last }
	}

	SetUndoPoint $w

	# TODO detect emoticons

	set n [string length $str]
	set i 0

	while {$i < $n} {
		set m [expr {min($n - $i, 3)}]

		while {$m > 1} {
			set s [string range $str $i [expr {$i + $m - 1}]]
			set nag [::scidb::misc::mapCodeToNag $s]
			if {$nag > 0} {
				InsertNag $w $nag
				incr i $m
				set m 0
			} elseif {[info exists ::font::mapCodeToNag($s)]} {
				InsertNag $w $::font::mapCodeToNag($s)
				incr i $m
				set m 0
			} else {
				decr m
			}
		}
		if {$m == 1} {
			set c [string index $str $i]
			set k [string first $c $Symbols]

			switch $k {
				-1 {
					set nag [::scidb::misc::mapCodeToNag $c]
					if {$nag} {
						InsertNag $w $nag
					} elseif {[info exists ::font::mapCodeToNag($c)]} {
						InsertNag $w $::font::mapCodeToNag($c)
					} else {
						$w insert insert $c
					}
				}

				 0 { InsertFigurine $w K }
				 1 { InsertFigurine $w Q }
				 2 { InsertFigurine $w R }
				 3 { InsertFigurine $w B }
				 4 { InsertFigurine $w N }
				 5 { InsertFigurine $w P }
			}

			incr i
		}
	}

	SetUndoPoint $w
}


proc ParseDump {dump} {
	variable Vars

	set token str
	set content ""
	set num 0

	foreach {key value index} $dump {
		switch $key {
			text {
				switch $token {
					str {
						if {[string length $value]} {
							if {[string index $value end-1] eq "\u00b6"} { set c "\n" } else { set c "" }
							append content [string map {"\u00b6" ""} $value] $c
						}
					}

					sym {
						append content [string map $::figurines::pieceMap $Vars(symbol:$num)]
					}

					nag {
						set nag $Vars(symbol:$num)
						set symbol [::font::mapNagToSymbol $nag]
						if {[string is digit -strict $symbol]} {
							append content "\${"
							append content $symbol
							append content "}"
						} else {
							append content $symbol
						}
					}
				}
			}

			image {
				set num [string range $value 3 end]
				append content [list emo [::emoticons::lookupCode $Vars(symbol:$num)]]
			}

			tagon {
				switch -glob $value {
					symbol*		{ set token nag }
					code*			{ set token nag }
					figurine*	{ set token sym }
					key*			{ set num [string range $value 3 end] }
				}
			}

			tagoff {
				switch -glob $value {
					symbol* - code* - figurine* { set token str }
				}
			}
		}
	}

	return $content
}


proc SetUndoPoint {w args} {
	variable Vars

	if {!$Vars(init)} {
		$w edit separator {*}$args
	}
}


proc EditUndo {} {
	variable Vars

	set w $Vars(widget:text:$Vars(lang)).text

	if {[$w edit info -undodepth]} {
		SetUndoPoint $w
		$w edit undo
	}
}


proc EditRedo {} {
	variable Vars

	set w $Vars(widget:text:$Vars(lang)).text

	if {[$w edit info -redodepth]} {
		$w edit redo
	}
}


proc TooltipShowNag {w key type value} {
	::tooltip::show $w "$::annotation::mc::Nag($value) (\$$value)"
	$w configure -cursor question_arrow
}


proc TooltipShowEmoticon {w emotion} {
	::tooltip::show $w $::emoticons::mc::Tooltip($emotion)
	$w configure -cursor question_arrow
}


proc TooltipHide {w} {
	::tooltip::tooltip hide
	$w configure -cursor xterm
}


proc LanguageChanged {dlg dialog} {
	variable ::figurines::langSet
	variable Vars

	if {$dlg ne $dialog} { return }

	set w $Vars(widget:text:$Vars(lang)).text
	foreach fig $langSet($Vars(mc)) {
		bind $w <Control-Shift-$fig> {#}
	}
	foreach fig $langSet($::mc::langID) eng $langSet(en) {
		bind $w <Control-Shift-$fig> [namespace code [list InsertFigurine $w $eng]]
		bind $w <Control-Shift-$fig> {+ break }
	}
	set Vars(mc) $::mc::langID

	switch $Vars(pos) {
		before		{ set titleVar CommentBeforeMove }
		after			{ set titleVar CommentAfterMove }
		preceding	{ set titleVar PrecedingComment }
		trailing		{ set titleVar TrailingComment }
	}

	wm title $dlg [set mc::$titleVar]

	set Vars(lang:label) [LanguageName]
	set Vars(countryList) {}

	MakeCountryList
}


proc MakeCountryList {} {
	variable Vars

	if {[llength $Vars(countryList)]} { return }
	set Vars(countryList) [::country::makeCountryList]
}


proc DumpToComment {dump} {
	variable Vars

	set count 0
	set fst 0
	set lst 0
	set n 1

	foreach {key value index} $dump {
		switch $key {
			text {
				# TODO count emoticons
				incr count $n
				set lst 1
				if {$fst == 0} { set fst 1 }
			}

			tagon {
				switch -glob $value {
					symbol* - code* - figurine* {
						set n 0
						set lst 2
						if {$fst == 0} { set fst 2 }
					}
				}
			}

			tagoff {
				switch -glob $value {
					symbol* - code* - figurine* { set n 1 }
				}
			}
		}
	}

	set n 0
	set token str
	set content {}
	set num 0
	array set flags { bold 0 italic 0 bold-italic 0 underline 0 }

	foreach {key value index} $dump {
		switch $key {
			text {
				if {$token eq "str"} {
					if {[incr n] == 1} {
						if {$n == $count} {
							if {$lst == 1 && $fst == 1} {
								if {[string index $value end] == "\n"} {
									# skip additional newline
									set value [string range $value 0 end-1]
								}
								set value [string trim $value " "]
							} elseif {$fst == 1} {
								set value [string trimleft $value " "]
							} elseif {$lst == 1} {
								if {[string index $value end] == "\n"} {
									# skip additional newline
									set value [string range $value 0 end-1]
								}
								set value [string trimright $value " "]
							}
						} elseif {$fst == 1} {
							set value [string trimleft $value " "]
						}
					} elseif {$n == $count && $lst == 1} {
						if {[string index $value end] == "\n"} {
							# skip additional newline
							set value [string range $value 0 end-1]
						}
						set value [string trimright $value " "]
					}
				} else {
					set value $Vars(symbol:$num)
				}
				if {[string length $value]} {
					lappend content [list $token $value]
				}
			}

			image {
				set num [string range $value 3 end]
				lappend content [list emo [::emoticons::lookupCode $Vars(symbol:$num)]]
			}

			tagon {
				switch $value {
					bold - italic - underline {
						if {[incr flags($value)] == 1} { lappend content "+$value" }
					}

					bold-italic {
						if {[incr flags($value)] == 1} { lappend content "+bold"; lappend content "+italic" }
					}

					codeb - symbolb {
						if {[incr flags(bold)] == 1} { lappend content "+bold" }
						set token nag
					}

					figurineb {
						if {[incr flags(bold)] == 1} { lappend content "+bold" }
						set token sym
					}

					code - symbol	{ set token nag }
					figurine			{ set token sym }

					default {
						if {[string match key* $value]} {
							 set num [string range $value 3 end]
						}
					}
				}
			}

			tagoff {
				switch $value {
					bold - italic - underline {
						if {[decr flags($value)] == 0} { lappend content "-$value" }
					}

					bold-italic {
						if {[decr flags($value)] == 0} { lappend content "-italic"; lappend content "-bold" }
					}

					symbolb - codeb - figurineb {
						if {[decr flags(bold)] == 0} { lappend content "-bold" }
						set token str
					}

					code - symbol - figurine { set token str }
				}
			}
		}
	}

	set content [string map {\u00b6 ""} $content]

	# normalize content
	set newContent "{xx {"
	append newContent $content
	append newContent "}}"
	set newContent [::scidb::misc::xml fromList $newContent]
	lassign [::scidb::misc::xml toList $newContent \
		-expandemoticons [ExpandEmoticons] -detectemoticons [DetectEmoticons]] newContent Vars(emotions)
	set content [lindex $newContent 0 1]

	return $content
}


proc ExpandEmoticons {} {
	variable Options
	return [expr {!$Options(showEmoticons)}]
}


proc DetectEmoticons {} {
	variable Options
	return [expr {$Options(showEmoticons) && $::pgn::editor::Options(show:emoticon)}]
}


proc ParseContent {lang} {
	variable Vars

	set w $Vars(widget:text:$lang).text
	set Vars(content:$lang) [DumpToComment [$w dump -tag -image -text begin end]]

	set languages ""
	foreach name [array names Vars content:*] {
		lappend languages [string range $name 8 9]
	}
	if {$lang ni $languages} {
		lappend languages $lang
	}

	set result ""
	foreach l $languages {
		if {$l eq "xx"} { set code "" } else { set code $l }
		lappend result [list $code $Vars(content:$l)]
	}

	return $result
}


proc PopupSymbolTable {w} {
	variable NagSet
	variable DingbatSet
	variable Colors
	variable Vars
	variable _Symbol

	set ncols 9
	set nrows 6
	set nsecs 7

	set parent [winfo toplevel $w]
	set m $parent.insert_symbol
	if {[winfo exists $m]} { return }
	menu $m -tearoff no
	bind $m <Escape> [list set [namespace current]::_Symbol {}]
	set top [tk::frame $m.top]
	pack $top -padx $::theme::padding -pady $::theme::padding
	set size [expr {int(abs(double([font configure $::font::symbol(text:normal) -size])*2.0) + 0.5)}]
	set _Symbol {}
	set coords [list [expr {$size/2}] [expr {$size/2}]]
	set bg [$top cget -background]

	for {set x 0} {$x < $ncols} {incr x} {
		for {set y 0} {$y < $nrows} {incr y} {
			set canv $top.c_${x}_${y}
			tk::canvas $canv -width $size -height $size -highlightthickness 1 -highlightbackground $bg
			bind $canv <Enter> [list $canv configure -background #ffdd76]
			bind $canv <Leave> [list $canv configure -background $bg]
			grid $canv -row $y -column $x
		}
	}

	set x 0
	set y 0
	set s 0

	foreach piece {K Q R B N P} {
		set canv $top.c_${x}_${y}
		if {![info exists first($s)]} { set first($s) $canv }
		set last($s) $canv
		set section($canv) $s
		set sym [string map $::figurines::pieceMap $piece]
		$canv create text {*}$coords -font $::font::figurine(text:normal) -text $sym
		foreach seq {space Return ButtonPress-1} {
			bind $canv <$seq> [namespace code [list set _Symbol [list fig $piece]]]
		}
		if {[incr y] == $nrows} {
			set y 0
			incr x
		}
	}

	set color 0
	set s 1

	foreach type {prefix suffix} {
		set ranges $::annotation::sections($type)

		foreach range $::annotation::sections($type) {
			lassign $range descr from to
			if {$from == 7} { set from 3}
			set nagSet $NagSet($type)
			set incr 0

			for {set nag $from} {$nag <= $to} {incr nag} {
				if {$nag in $nagSet} {
					lassign [::font::splitAnnotation $nag] value sym
					set canv $top.c_${x}_${y}
					if {![info exists first($s)]} { set first($s) $canv }
					set last($s) $canv
					set section($canv) $s
					$canv create text {*}$coords \
						-font $::font::symbol(text:normal) \
						-text $sym \
						-fill [lindex $Colors $color] \
						;
					foreach seq {space Return ButtonPress-1} {
						bind $canv <$seq> [namespace code [list set _Symbol [list nag $nag]]]
					}
					set tip "[string toupper $::annotation::mc::Nag($nag) 0 0] (\$$nag)"
					::tooltip::tooltip $canv $tip
					if {[incr y] == $nrows} {
						set y 0
						incr x
					}
					set incr 1
				}
			}

			if {$incr} {
				incr color $incr
				incr s
			}
		}
	}

	foreach c $DingbatSet {
		set canv $top.c_${x}_${y}
		$canv create text {*}$coords -text $c
		if {![info exists first($s)]} { set first($s) $canv }
		set last($s) $canv
		set section($canv) $s
		foreach seq {space Return ButtonPress-1} {
			bind $canv <$seq> [namespace code [list set _Symbol [list sym $c]]]
		}
		if {[incr y] == $nrows} {
			set y 0
			incr x
		}
	}

	for {set x 0} {$x < $ncols} {incr x} {
		for {set y 0} {$y < $nrows} {incr y} {
			set canv $top.c_${x}_${y}

			if {$section($canv) == 0} {
				set prior 0
			} else {
				set prior [expr {$section($canv) - 1}]
			}
			if {$section($canv) == $nsecs - 1} {
				set next [expr {$nsecs - 1}]
			} else {
				set next [expr {$section($canv) + 1}]
			}

			if {$x > 0} {
				set lt [expr {$x - 1}]_${y}
			} elseif {$y > 0} {
				set lt [expr {$ncols - 1}]_[expr {$y - 1}]
			} else {
				set lt [expr {$ncols - 1}]_[expr {$nrows - 1}]
			}
			if {$x < [expr {$ncols - 1}]} {
				set rt [expr {$x + 1}]_${y}
			} elseif {$y < $nrows - 1} {
				set rt 0_[expr {$y + 1}]
			} else {
				set rt 0_0
			}
			if {$y > 0} {
				set up ${x}_[expr {$y - 1}]
			} elseif {$x > 0} {
				set up [expr {$x - 1}]_[expr {$nrows - 1}]
			} else {
				set up [expr {$ncols - 1}]_[expr {$nrows - 1}]
			}
			if {$y < $nrows - 1} {
				set dn ${x}_[expr {$y + 1}]
			} elseif {$x < $ncols - 1} {
				set dn [expr {$x + 1}]_0
			} else {
				set dn 0_0
			}

			bind $canv <Left>  [list focus $top.c_$lt]
			bind $canv <Right> [list focus $top.c_$rt]
			bind $canv <Up>    [list focus $top.c_$up]
			bind $canv <Down>  [list focus $top.c_$dn]
			bind $canv <Prior> [list focus $first($prior)]
			bind $canv <Next>  [list focus $first($next)]
			bind $canv <Home>  [list focus $top.c_0_0]
			bind $canv <End>   [list focus $last([expr {$nsecs - 1}])]
		}
	}

	foreach b {1 2 3} {
		bind $top <ButtonPress-$b> [namespace code [list ExitInsertSymbol $top %X %Y]]
	}

	::tooltip::tooltip on $top*
	wm withdraw $m
	wm transient $m $parent
	catch { wm attributes $m -type popup_menu }
	util::place $m -parent $w -position below -type popup
	wm deiconify $m
	raise $m
	focus $m
	if {[tk windowingsystem] eq "x11"} {
		tkwait visibility $m
		::update idletasks
		if {![winfo exists $m]} { return }
	}
	focus -force $top.c_0_0
	ttk::globalGrab $top
	vwait [namespace current]::_Symbol
	ttk::releaseGrab $top
	destroy $m
	::tooltip::tooltip on
	set text $Vars(widget:text:$Vars(lang)).text

	if {[llength $_Symbol]} {
		switch [lindex $_Symbol 0] {
			fig { InsertFigurine $text [lindex $_Symbol 1] }
			nag { InsertNag $text [lindex $_Symbol 1] }
			sym { InsertText $text [lindex $_Symbol 1] {} yes }
		}
	}

	catch { focus -force $text }
}


proc ExitInsertSymbol {w x y} {
	if {![string match $w* [winfo containing $x $y]]} {
		set [namespace current]::_Symbol {}
	}
}


proc PopupMenu {parent} {
	variable Vars

	set w $parent
	set m $parent.langMenu
	catch { destroy $m }
	menu $m -tearoff no
	catch { wm attributes $m -type popup_menu }
	SetUndoPoint $w

	# C11: the one comment context menu.
	if {[llength [info commands ::context::Build]]} {
		set base ""
		set index ""
		set ply ""
		catch { lassign [::scidb::game::link? [::scidb::game::current]] base variant index }
		catch { set ply [::scidb::game::ply] }
		set object [dict create widget $w base $base index $index ply $ply]
		if {[::context::Build C11 $m $object]} {
			tk_popup $m {*}[winfo pointerxy $w]
			return
		}
		destroy $m
		return
	}

	if {![info exists Vars(content:xx)]} {
		set Vars(content:xx) ""
	}

	if {[llength [$parent tag ranges sel]] == 0} {
		set state disabled
	} else {
		set state normal
	}

	set count 0
	set lang $Vars(lang)
	set accel "$::mc::Key(Ctrl)-"

	if {$state eq "normal"} {
		$m add command \
			-compound left \
			-image $::icon::16x16::clipboardIn \
			-label " $::mc::Copy" \
			-accelerator ${accel}C \
			-command [namespace code [list TextCopy $w]] \
			-state $state \
			;
		$m add command \
			-compound left \
			-image $::icon::16x16::clipboardIn \
			-label " $::mc::Cut" \
			-accelerator ${accel}X \
			-command [namespace code [list TextCut $w]] \
			-state $state \
			;
		incr count
	}
	set sel [::clipboard::getSelection]
	if {[string length $sel]} {
		set sel [string map {"<brace/>" "\{" "\n" "\n\u00b6"} $sel]
		$m add command \
			-compound left \
			-image $::icon::16x16::clipboardOut \
			-label " $::mc::Paste" \
			-accelerator ${accel}V \
			-command [namespace code [list PasteText $w $sel]] \
			;
		incr count
	}
	if {$count > 0} {
		$m add separator
	}

	menu $m.symbol -tearoff no
	$m add cascade \
		-compound left \
		-image $icon::16x16::blackPawn \
		-label " [string map {"..." ""} [::mc::stripAmpersand $mc::InsertSymbol]]" \
		-menu $m.symbol \
		;
	MakeSymbolMenu $parent $m.symbol

	menu $m.emoticons -tearoff no
	$m add cascade \
		-compound left \
		-image $::emoticons::icon(smile) \
		-label " [string map {"..." ""} [::mc::stripAmpersand $mc::InsertEmoticon]]" \
		-menu $m.emoticons \
		;
	MakeEmoticonMenu $parent $m.emoticons

	menu $m.format -tearoff no
	$m add cascade \
		-compound left \
		-image $icon::16x16::format \
		-label " $mc::FormatText" \
		-menu $m.format \
		-state $state \
		;
	foreach format {Bold Italic Underline} {
		set fmt [string tolower $format]
		$m.format add command \
			-compound left \
			-image [set ::icon::12x12::text-$fmt] \
			-label " [set mc::$format]" \
			-command [namespace code [list ChangeFormat $fmt yes]] \
			;
	}
	if {[llength $Vars(langSet)] && [string length $Vars(content:$lang)]} {
		set state normal
	} else {
		set state disabled
	}
	menu $m.copy -tearoff no
	$m add cascade \
		-compound left \
		-image $::icon::16x16::copy \
		-label " $mc::CopyText" \
		-menu $m.copy \
		-state $state \
		;
	foreach code [list xx {*}$Vars(langSet)] {
		if {$code ne $lang} {
			$m.copy add command \
				-compound left \
				-image $::country::icon::flag([::mc::countryForLang $code]) \
				-label " [LanguageName $code]" \
				-command [namespace code [list CopyText $lang $code]] \
				;
		}
	}

	# C1: explain the comment being edited, grounded in the stored text.
	if {[llength [info commands ::application::ai::explainSelection]]} {
		if {[string length $Vars(content:$lang)]} { set state normal } else { set state disabled }
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $mc::ExplainComment" \
			-state $state \
			-command [namespace code [list ExplainComment [winfo toplevel $parent]]] \
			;
	}

	# C1: draft a grounded comment for this position.
	if {[llength [info commands ::application::ai::generate]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $mc::DraftComment" \
			-command [namespace code [list DraftComment [winfo toplevel $parent]]] \
			;
	}

	# C2: translate the comment into another language slot.
	if {[llength [info commands ::application::ai::generate]]
	 && [llength [info commands ::ai::language::Name]]} {
		set sub $menu.translate
		catch { destroy $sub }
		menu $sub -tearoff no
		foreach lang {en de fr es it pt nl ru pl cs uk tr el ar he zh ja ko} {
			$sub add command -label " [::ai::language::Name $lang]" \
				-command [namespace code [list TranslateComment [winfo toplevel $parent] $lang]]
		}
		$m add cascade -label " $mc::TranslateComment" -menu $sub
	}

	# A3: classify what the comment is about.
	if {[llength [info commands ::ai::comment::kind]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $mc::ClassifyComment" \
			-command [namespace code [list ClassifyComment [winfo toplevel $parent]]] \
			;
	}

	# A2: detect the language of this comment.
	if {[llength [info commands ::ai::language::detect]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $mc::DetectLanguage" \
			-command [namespace code [list DetectLanguage [winfo toplevel $parent]]] \
			;
	}
	$m add separator

	set t $Vars(widget:text:$Vars(lang)).text
	if {[$t edit info -undodepth]} { set state normal } else { set state disabled }
	$m add command \
		-compound left \
		-image $::icon::16x16::undo \
		-label " $::mc::Undo" \
		-accelerator ${accel}Z \
		-command [namespace code EditUndo] \
		-state $state \
		;
	if {[$t edit info -redodepth]} { set state normal } else { set state disabled }
	$m add command \
		-compound left \
		-image $::icon::16x16::redo \
		-label " $::mc::Redo" \
		-accelerator ${accel}Y \
		-command [namespace code EditRedo] \
		-state $state \
		;
	set state [expr {[::widget::textIsEmpty? $t] ? "disabled" : "normal"}]
	$m add command \
		-compound left \
		-image $::icon::16x16::selectAll \
		-label " $::mc::SelectAll" \
		-accelerator ${accel}A \
		-command [list $t tag add sel begin end] \
		-state $state \
		;
	$m add command \
		-compound left \
		-image $::icon::16x16::clear \
		-label " [::mc::stripAmpersand $::widget::mc::Label(clear)]" \
		-command [namespace code Clear] \
		-state $state \
		;
	$m add command \
		-compound left \
		-image $::icon::16x16::reset \
		-label " [::mc::stripAmpersand $::widget::mc::Label(revert)]" \
		-command [namespace code [list Revert [winfo toplevel $parent]]] \
		-state [$Vars(widget:revert) cget -state] \
		;
	
	if {[llength $Vars(langSet)]} { set state normal } else { set state disabled }
	$m add separator
	menu $m.switch -tearoff no
	$m add cascade \
		-compound left \
		-image $::icon::16x16::none \
		-label " $mc::SwitchLanguage" \
		-menu $m.switch \
		-state $state \
		;
	if {$Vars(lang) eq "xx"} { set state disabled } else { set state normal }
	$m.switch add command \
		-compound left \
		-image $::country::icon::flag([::mc::countryForLang xx]) \
		-label " $::languagebox::mc::AllLanguages" \
		-command [namespace code [list SwitchLanguage xx]] \
		-state $state \
		;

	foreach lang $Vars(langSet) {
		if {$lang eq $Vars(lang)} { set state disabled } else { set state normal }
		$m.switch add command \
			-compound left \
			-image $::country::icon::flag([::mc::countryForLang $lang]) \
			-label " [::encoding::languageName $lang]" \
			-command [namespace code [list SwitchLanguage $lang]] \
			-state $state \
			;
	}

	MakeLanguageMenu $m.languages
	$m add cascade \
		-compound left \
		-image $::icon::16x16::plus \
		-label " [lindex [split $mc::AddLanguage .] 0]" \
		-menu $m.languages \
		;

	if {$::pgn::editor::Options(show:emoticon)} {
		$m add separator
		$m add checkbutton \
			-label $mc::DisplayEmoticons \
			-variable [namespace current]::Options(showEmoticons) \
			-command [namespace code DisplayEmoticons] \
			;
		::theme::configureCheckEntry $m
	}

	tk_popup $m {*}[winfo pointerxy $parent]
}


proc MakeEmoticonMenu {w menu} {
	set emoticons [::emoticons::emoticons]
	set n [expr {[llength $emoticons]/2 + 1}]
	foreach emotion $emoticons {
		$menu add command \
			-image $::emoticons::icon($emotion) \
			-label " $::emoticons::mc::Tooltip($emotion)" \
			-compound left \
			-command [namespace code [list InsertEmoticon $w $emotion]] \
			-columnbreak [expr {[decr n] == 0}] \
			;
	}
}


proc MakeSymbolMenu {w menu} {
	variable NagSet
	variable DingbatSet
	variable Vars

	set m [menu $menu.figurine -tearoff 0]
	$menu add cascade -menu $m -label $mc::Figurine

	set i 0
	foreach {fig} {K Q R B N P} {
		# TODO: only use accelerator if piece is ASCII symbols
		set piece [lindex $::figurines::langSet($Vars(mc)) $i]
		$m add command \
			-font $::font::figurine(text:normal) \
			-label [string map $::figurines::pieceMap $fig] \
			-accelerator "$::mc::Key(Ctrl)-$::mc::Key(Shift)-$piece" \
			-command [namespace code [list InsertFigurine $w $fig]] \
			;
		incr i
	}

	foreach type {prefix suffix} {
		set ranges $::annotation::sections($type)
		set m [menu $menu.$type]

		if {[llength $ranges] == 1} {
			bind $m <<MenuSelect>> [namespace code { ::widget::menuItemHighlightSecond %W }]
		}

		foreach range $ranges {
			lassign $range descr from to
			if {$from == 7} { set from 3}
			set text [set ::annotation::mc::$descr]
			set nagSet $NagSet($type)

			if {[llength $ranges] == 1} {
				$menu add cascade -menu $m -label $text
				set sub $m
			} else {
				set sub [menu $m.[string tolower $descr 0 0]]
			}

			set nags {}
			for {set nag $from} {$nag <= $to} {incr nag} {
				if {$nag in $nagSet} {
					set symbol [::font::mapNagToUtfSymbol $nag]
					$sub add command -label $symbol -command [namespace code [list InsertNag $w $nag]]
					lappend nags $nag
				}
			}

			if {[llength $nags] == 0} {
				destroy $sub
			} else {
				if {[llength $ranges] > 1} {
					bind $sub <<MenuSelect>> [namespace code { ::widget::menuItemHighlightSecond %W }]
					$menu add cascade -menu $sub -label $text
				}
				set columnbreak 1

				foreach nag $nags {
					$sub add command \
						-label [string toupper $::annotation::mc::Nag($nag) 0 0] \
						-command [namespace code [list InsertNag $w $nag]] \
						-columnbreak $columnbreak \
						;
					set columnbreak 0
				}
			}
		}
	}

	set m [menu $menu.misc -tearoff no]
	$menu add cascade -menu $m -label $mc::MiscellaneousSymbols
	set i -1
	foreach c $DingbatSet {
		$m add command \
			-label $c \
			-command [namespace code [list InsertText $w $c {} yes]] \
			-columnbreak [expr {[incr i] == [llength $DingbatSet]/2}] \
			;
	}
}


proc MakeLanguageMenu {path} {
	variable Vars
	variable Options

	set m $path
	catch { destroy $m }
	menu $m -tearoff no

	set size [expr {([llength $Vars(countryList)] + $Options(menuColumns) - 1)/$Options(menuColumns)}]
	for {set i 1} {$i < $Options(menuColumns)} {incr i} { lappend breaks [expr {$i*$size}] }
	set n 0

	foreach entry $Vars(countryList) {
		lassign $entry flag name lang
		set opts {}
		if {$lang in $Vars(langSet)} { lappend opts -state disabled }
		if {$n in $breaks} { lappend opts -columnbreak 1 }
		$m add command {*}$opts \
			-command [namespace code [list NewLanguage $lang]] \
			-compound left \
			-image $flag \
			-label " $name" \
			;
		incr n
	}

	return $path
}


proc PopupChooseLanguage {dlg} {
	variable Options

	if {$Options(useComboBox)} {
		PopdownLanguages $dlg
	} else {
		PopupLanguageMenu $dlg
	}
}


proc PopupLanguageMenu {dlg} {
	variable Vars

	MakeLanguageMenu $dlg.langMenu
	catch { wm attributes $dlg.langMenu -type popup_menu }

	set x [winfo rootx $Vars(addLang)]
	set y [winfo rooty $Vars(addLang)]
	if {[scan [winfo geometry $Vars(addLang)] "%dx%d+%d+%d" tw th] >= 2} { incr y $th }

	tk_popup $dlg.langMenu $x $y
}


proc PopdownLanguages {dlg} {
	variable Vars

	set popdown $dlg.popdown
	tk::toplevel $popdown -class AddLanguagePopdown
	wm withdraw $popdown

	switch -- [tk windowingsystem] {
		default -
		x11 {
			wm overrideredirect $popdown true
		}
		win32 {
			wm overrideredirect $popdown true
			wm attributes $popdown -topmost 1
		}
		aqua {
			tk::unsupported::MacWindowStyle style $popdown help {noActivates hideOnSuspend}
			wm resizable $popdown 0 0
		}
	}

	if {[info tclversion] >= "8.6"} {
		set borderwidth [::ttk::style lookup ComboboxPopdownFrame -borderwidth]
	} else {
		 switch -- [tk windowingsystem] {
			x11	{ set borderwidth 1 }
			win32	{ set borderwidth 1 }
			aqua	{ set borderwidth 0 }
		 }
	}

	$popdown configure -borderwidth $borderwidth -relief solid

	lappend listopts \
		-height 10 \
		-usescroll yes \
		-relief flat \
		-selectmode browse \
		-borderwidth 1 \
		-showfocus 0 \
		-exportselection no \
		-disabledforeground grey60 \
		-disabledbackground white \
		;
	if {[info tclversion] >= "8.6"} {
		lappend listopts -style ComboboxPopdownFrame
	}

	set lb [::tlistbox $popdown.l {*}$listopts]

	bind $lb <<ItemVisit>> 		[namespace code [list Activate $lb %d]]

	$lb bind <ButtonRelease-1>	[namespace code [list Selected $popdown]]
	bind $popdown <Any-Key>		[namespace code [list Search $popdown %A %K]]
	bind $popdown <Key-space>	[namespace code [list Selected $popdown]]
	bind $popdown <Return>		[namespace code [list Selected $popdown]]

	bind $popdown <Home>			[list tlistbox::Home [$lb child]]
	bind $popdown <End>			[list tlistbox::End [$lb child]]
	bind $popdown <Prior>		[list tlistbox::Prior [$lb child]]
	bind $popdown <Next>			[list tlistbox::Next [$lb child]]
	bind $popdown <Up>			[list tlistbox::Up [$lb child]]
	bind $popdown <Down>			[list tlistbox::Down [$lb child]]

	$lb addcol image	-id flag	-width 18 -justify left
	$lb addcol text	-id name

	pack $lb -fill both

	set first -1
	set index 0
	foreach entry $Vars(countryList) {
		set lang [lindex $entry 2]
		if {$lang in $Vars(langSet)} {
			set enabled no
		} else {
			set enabled yes
			if {$first == -1} { set first $index }
		}
		$popdown.l insert $entry -enabled $enabled
		incr index
	}

	$popdown.l configure -cursor {}
	$popdown.l resize
	$popdown.l see 0

	set index [lsearch -exact -index 2 $Vars(countryList) $Vars(wantedLang)]
	if {$index >= 0 && $Vars(wantedLang) ni $Vars(langSet)} {
		$popdown.l select $index
	} elseif {$first >= 0} {
		$popdown.l select $first
	}

	catch { wm attributes $popdown -type dropdown_menu }
	::update idletasks
	::util::place $popdown -parent $Vars(addLang) -position below -type popup
	switch -- [tk windowingsystem] {
		x11 - win32 { wm transient $popdown $dlg }
	}
	wm attribute $popdown -topmost 1
	set Vars(focus) [focus]
	wm deiconify $popdown
	raise $popdown
	focus $popdown
}


proc UnpostPopdown {popdown} {
	variable Vars

	catch { focus -force $Vars(focus) }
	grab release $popdown	;# in case of stuck or unexpected grab
	update idletasks
	destroy $popdown
}


proc Activate {lb data} {
	if {[lindex $data 0] eq "enter"} {
		$lb select [lindex $data 2]
	}
}


proc Selected {popdown args} {
	variable Vars

	set index [$popdown.l curselection]

	if {$index >= 0} {
		set lang [lindex $Vars(countryList) $index 2]
		UnpostPopdown $popdown
		NewLanguage $lang
	}
}


proc DisplayEmoticons {} {
	variable Options
	variable Vars

	set lang $Vars(lang)
	set w $Vars(widget:text:$lang).text
	set mark [$w index current]

	set comment "{xx {"
	append comment [DumpToComment [$w dump -tag -image -text begin end]]
	append comment "}}"

	if {$Vars(emotions) == 0} { return }

	if {[$w edit info -undodepth]} {
		set reply [::dialog::question \
			-parent [winfo toplevel $w] \
			-title $::scidb::app \
			-message $mc::ReallySwitch \
			-detail $mc::LosingChanges \
			-default no \
		]
		if {$reply eq "no"} {
			set Options(showEmoticons) [expr {!$Options(showEmoticons)}]
			return
		}
	}

	if {$Options(showEmoticons)} { set opt -detectemoticons } else { set opt -expandemoticons }
	set content [::scidb::misc::xml fromList $comment]
	set content [lindex [::scidb::misc::xml toList $content $opt 1] 0]

	SetupComment $lang [lindex $content 0 1]
	$w mark set insert $mark
	$w see insert
}


proc NewLanguage {lang} {
	variable Vars

	if {$lang ni $Vars(langSet)} {
		lappend Vars(langSet) $lang
		set Vars(langSet) [lsort $Vars(langSet)]
		SwitchLanguage $lang yes
		MakeLanguageButtons
		set Vars(content:$lang) ""
		set Vars(remember:$lang) ""
	}
}


proc Search {popdown code sym} {
	if {![string is alpha -strict $code]} { return }
	$popdown.l search name $code [mc::mappingForSort] [mc::mappingToAscii]
}


proc LanguageName {{lang {}}} {
	variable Vars

	if {[llength $lang] == 0} { set lang $Vars(lang) }
	if {$lang eq "xx" } { return $::languagebox::mc::AllLanguages }
	return [::encoding::languageName $lang]
}


proc CopyText {fromLang toLang} {
	variable Vars

	SetUndoPoint $Vars(widget:text:$toLang).text

	if {[info exists Vars(content:$toLang)]} {
		if {[string length $Vars(content:$toLang)]} {
			set reply [::dialog::question \
				-parent [winfo toplevel $Vars(widget:text:$toLang).text] \
				-title $::scidb::app \
				-message $mc::OverwriteContent \
				-detail $mc::AppendContent \
				-default no \
			]
			if {$reply eq "yes"} {
				set Vars(content:$toLang) {}
			}
		}

		if {[string length $Vars(content:$toLang)]} {
			lappend Vars(content:$toLang) {str \n}
		}
	}

	lappend Vars(content:$toLang) {*}$Vars(content:$fromLang)
}


proc ChangeFormat {format {toggle no}} {
	variable Vars

	set w $Vars(widget:text:$Vars(lang)).text
	set content [DumpToComment [$w dump -tag -text begin end]]
	set selrange [$w tag ranges sel]
	ToggleFormat $format $toggle
	if {[llength $selrange] == 0} { return }
	SetUndoPoint $w -immediately

	lassign $selrange prevIndex lastIndex
	array set flags {bold 0 italic 0 underline 0 code 0 codeb 0 symbol 0 symbolb 0 figurine 0 figurineb 0}
	set flags($format) $Vars(format:$format)

	foreach {key value index} [$w dump -tag begin end] {
		if {[$w compare $prevIndex <= $index] && [$w compare $index <= $lastIndex]} {
			if {$prevIndex ne $index} {
				set range [list $prevIndex $index]
				if {$flags(symbol) || $flags(symbolb)} {
					if {$flags(symbol) && $flags(bold)} {
						$w tag remove symbol {*}$range
						$w tag add symbolb {*}$range
					} elseif {$flags(symbolb) && !$flags(bold)} {
						$w tag remove symbolb {*}$range
						$w tag add symbol {*}$range
					}
				} elseif {$flags(code) || $flags(codeb)} {
					if {$flags(code) && $flags(bold)} {
						$w tag remove code {*}$range
						$w tag add codeb {*}$range
					} elseif {$flags(codeb) && !$flags(bold)} {
						$w tag remove codeb {*}$range
						$w tag add code {*}$range
					}
				} elseif {$flags(figurine) || $flags(figurineb)} {
					if {$flags(figurine) && $flags(bold)} {
						$w tag remove figurine {*}$range
						$w tag add figurineb {*}$range
					} elseif {$flags(figurineb) && !$flags(bold)} {
						$w tag remove figurineb {*}$range
						$w tag add figurine {*}$range
					}
				}
				if {$flags(bold) && $flags(italic)} {
					set fmt bold-italic
				} elseif {$flags(bold)} {
					set fmt bold
				} elseif {$flags(italic)} {
					set fmt italic
				} else {
					set fmt {}
				}
				if {$format eq "underline"} {
					if {$flags(underline)} { set cmd add } else { set cmd remove }
					$w tag $cmd underline {*}$range
				} else {
					foreach f {bold italic bold-italic} {
						if {$f eq $fmt} { set cmd add } else { set cmd remove }
						$w tag $cmd $f {*}$range
					}
				}
			}
			set prevIndex $index
		}
		if {$value ne "sel"} {
			foreach fmt [split $value -] {
				if {$fmt ne $format} {
					switch $key {
						tagon  { incr flags($fmt) }
						tagoff { decr flags($fmt) }
					}
				}
			}
		}
	}

	SetUndoPoint $w -immediately
}


proc ToggleFormat {format {toggle yes}} {
	variable Vars

	if {$toggle} {
		set Vars(format:$format) [expr {!$Vars(format:$format)}]
	}

	if {$Vars(format:bold) && $Vars(format:italic)} {
		set Vars(format) bold-italic
	} elseif {$Vars(format:bold)} {
		set Vars(format) bold
	} elseif {$Vars(format:italic)} {
		set Vars(format) italic
	} else {
		set Vars(format) {}
	}

	if {$Vars(format:underline)} {
		lappend Vars(format) underline
	}
}


proc UpdateFormatButtons {w} {
	variable Vars

	lassign {0 0 0} bold italic underline

	foreach fmt {bold italic bold-italic underline} {
		if {[llength [set range [$w tag prevrange $fmt insert]]]} {
			if {[$w compare [lindex $range 0] <= insert] && [$w compare [lindex $range end] >= insert]} {
				foreach f [split $fmt -] { set $f 1 }
			}
		}
	}

	if {[llength [set range [$w tag prevrange symbolb insert]]]} {
		if {[$w compare [lindex $range 0] <= insert] && [$w compare [lindex $range end] >= insert]} {
			set bold 1
		}
	}

	foreach fmt {bold italic underline} {
		if {$Vars(format:$fmt) != [set $fmt]} {
			ToggleFormat $fmt
		}
	}
}


proc InvokeDefaultButton {} {
	variable Vars
	::widget::dialogButtonInvoke $Vars(dialog)
}


proc TextInsert {w s} {
	variable Vars

	if {$s eq "" || [$w cget -state] eq "disabled"} { return }

	set compound 0

	if {[llength [set range [$w tag ranges sel]]]} {
		if {[$w compare insert <= [lindex $range end]] && [$w compare [lindex $range 0] <= insert]} {
			SetUndoPoint $w
			$w delete [lindex $range 0] [lindex $range end]
		}
	}

	set c [$w get insert]

	if {$s eq "\n"} {
		SetUndoPoint $w
		set c [$w get insert]
		if {$c eq " "} {
			$w replace insert insert+1c "\u00b6\n"
		} elseif {$c eq "\n"} {
			$w insert insert+1c "\u00b6\n"
		} else {
			$w insert insert "\u00b6\n"
		}
	} else {
		if {$c eq "\n"} { $w mark set insert insert+1c }
		$w insert insert $s $Vars(format)
	}

	$w see insert
}


proc TextButton1 {w x y} {
	::tk::TextButton1 $w $x $y

	if {[$w compare insert != end-1c]} {
		set c [$w get insert]
		if {[lindex [split [$w index insert] .] 1] > 0} {
			while {$c eq "\n"} {
				$w mark set insert insert-1c
				set c [$w get insert]
			}
			$w see insert
		}
	}

	UpdateFormatButtons $w
	SetUndoPoint $w
}


proc TextSetCursorExt {w pos {dir -1}} {
	::tk::TextSetCursor $w $pos

	if {[$w compare insert != end-1c]} {
		if {$dir > 0} {
			if {[$w get insert] eq "\n"} {
				$w mark set insert insert+1c
				$w see insert
			}
		} elseif {[$w compare insert != begin]} {
			if {[$w get insert] eq "\n"} {
				$w mark set insert insert-1c
				$w see insert
			}
		}
	}

	SetUndoPoint $w
	UpdateFormatButtons $w
}


proc TextSetCursor {w pos} {
	::tk::TextSetCursor $w $pos
	SetUndoPoint $w
	UpdateFormatButtons $w
}


proc TextUpDownLine {w n} {
	variable ::tk::Priv

	set pos [::tk::TextUpDownLine $w $n]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
		set Priv(prevPos) $pos
	}
	return $pos
}


proc TextPrevPara {w pos} {
	set pos [::tk::TextPrevPara $w $pos]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
		set Priv(prevPos) $pos
	}
	return $pos
}


proc TextNextPara {w pos} {
	set pos [::tk::TextNextPara $w $pos]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
		set Priv(prevPos) $pos
	}
	return $pos
}


proc TextNextPos {w start op} {
	set pos [::tk::TextNextPos $w $start $op]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
	}
	return $pos
}


proc TextPrevPos {w start op} {
	set pos [::tk::TextPrevPos $w $start $op]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
	}
	return $pos
}


proc TextScrollPages {w count} {
	set pos [::tk::TextScrollPages $w $count]
	if {[$w compare $pos != begin]} {
		if {[$w get $pos] eq "\n"} { set pos [$w index $pos-1displayindices] }
	}
	return $pos
}


proc TextBackSpace {w} {
	if {[$w tag nextrange sel begin end] ne ""} {
		set c [$w get sel.last]
		if {$c eq "\u00b6"} { set incr +1c } else { set incr "" }
		set c [$w get sel.first]
		if {$c eq "\n" } { set decr -1c } else { set decr "" }
		$w delete sel.first$decr sel.last$incr
	} elseif {[$w compare insert != begin]} {
		set c [$w get insert-1c]
		if {$c eq "\n"} {
			if {	[$w compare insert-1c == [$w index begin+1c]]
				|| [string is space [$w get insert-3c]]
				|| [string is space [$w get insert]]} {
				$w delete insert-2c insert
			} else {
				$w replace insert-2c insert " "
			}
		} elseif {$c eq "\u00b6"} {
			if {	[$w compare insert == [$w index begin+1c]]
				|| [string is space [$w get insert-2c]]
				|| [string is space [$w get insert+1c]]} {
				$w delete insert-1c insert+1c
			} else {
				$w replace insert-1c insert+1c " "
			}
			if {[$w compare insert != end-1c]} {
				$w mark set insert insert-1c
			}
		} else {
			$w delete insert-1c
		}
		$w see insert
	}
}


proc TextDelete {w} {
	SetUndoPoint $w

	if {[$w tag nextrange sel begin end] ne ""} {
		set c [$w get sel.last-1c]
		if {$c eq "\u00b6"} { set incr +1c } else { set incr "" }
		set c [$w get sel.first]
		if {$c eq "\n" } { set decr -1c } else { set decr "" }
		$w delete sel.first$decr sel.last$incr
	} else {
		set c [$w get insert]
		if {$c eq "\n"} {
			if {[$w compare insert == end-1c]} {
				# special case, seems to be a Tk bug
				$w delete insert-2c insert
			} elseif {	[$w compare insert == [$w index begin+1c]]
						|| [string is space [$w get insert-2c]]
						|| [string is space [$w get insert+1c]]} {
				$w delete insert-1c insert+1c
			} else {
				$w replace insert-1c insert+1c " "
			}
		} elseif {$c eq "\u00b6"} {
			if {	[$w compare insert == begin]
				|| [string is space [$w get insert-1c]]
				|| [string is space [$w get insert+2c]]} {
				$w delete insert insert+2c
			} else {
				$w replace insert insert+2c " "
			}
			if {[$w compare insert != end-1c]} {
				$w mark set insert insert-1c
			}
			if {[$w get insert] eq "\n"} {
				$w mark set insert insert-1c
			}
		} else {
			$w delete insert
		}
		$w see insert
	}
}


proc TextClear {w} {
	SetUndoPoint $w
	set c [$w get sel.last]
	if {$c eq "\u00b6"} { set incr +1c } else { set incr "" }
	set c [$w get sel.first]
	if {$c eq "\n" } { set decr -1c } else { set decr "" }
	$w delete sel.first$decr sel.last$incr
}


proc TextControlD {w} {
	set c [$w get insert]
	if {$c eq "\u00b6"} {
		$w delete insert insert+1c
	} elseif {$c eq "\n"} {
		$w delete insert-1c insert
		$w mark set insert insert-1c
	}

	$w delete insert
	$w see insert
}


proc TextPasteSelection {w x y} {
	$w mark set insert [::tk::TextClosestGap $w $x $y]

	PasteText $w [::clipboard::getSelection PRIMARY]

	if {[$w cget -state] eq "normal"} {
		focus $w
	}
}


proc TextPaste {w} {
	variable Vars

	set sel [::clipboard::getSelection]

	if {[string length $sel]} {
		set sel [string map {"\n" "\n\u00b6"} $sel]
		PasteText $w $sel
	}
}


proc TextCopy {w} {
	variable Vars

	if {[llength [$w tag ranges sel]]} {
		set data [ParseDump [$w dump -tag -image -text sel.first sel.last]]
		SetUndoPoint $w
		::clipboard::selectText $data
	}
}


proc TextCut {w} {
	variable Vars

	if {[llength [$w tag ranges sel]]} {
		set data [ParseDump [$w dump -tag -image -text sel.first sel.last]]
		SetUndoPoint $w
		::clipboard::selectText $data
		if {[$w get sel.first] eq "\n"} { set decr -1c } else { set decr "" }
		if {[$w get sel.last] eq "\u00b6"} { set incr +1c } else { set incr "" }
		$w delete sel.first$decr sel.last$incr
		SetUndoPoint $w
	}
}


namespace eval icon {
namespace eval 12x12 {

#set format [image create photo -data {
#iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
#ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
#ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
#MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
#Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
#IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
#YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
#cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
#aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
#b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
#b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
#d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
#b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
#IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
#c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
#REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
#TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
#SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
#SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
#RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
#V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
#SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
#RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB9ElEQVR4nE1R
#PWhTYRQ993svMWrTaAWxpvkRSUjRmhIhaItFQXQQB1EytY5mUwfBDg4PnKwIgg4OUn+gKIaKcbBI
#waiQEklrNEkNpRWDjTZtQ2vMf/LCdehL8SwX7j2Hcw6XoIGZiYiYmdsAuLT1HBEVWjf8D2YmSQgk
#UvPXhvzD6UH/9fTXROqKLEtgZmrxhEYWRMRqs+l8M/nhajQ2a4sl5myPnwcHGw21S3MWm4JAIEAA
#0ASORKJxc0eHsepy2PPRz0n3r+zKyVaITYHP52sys/Ti5YQn/fM3/hbKBlN7W61Sresejb26wMwm
#zYVEywqAdTIUPrVrZ3vDfcC5vpjJGrs6d5c+TkUHAPQDgKIoJBRFgRACS8urFxd+ZLrtVnOhz9ub
#z67ktlotnWpuLW98ODZ+npm3KIqy0Z6Ztz95Fgzfujfq1skyJElCqVSG13Owklv7o99mMCyPP717
#hoi+yFqcE29DYZtjn0W97B96Xa5UFpPfFs4FJ96Z+729+fdT03s/xeJ+Zh4WzNw9cn/0dmQ6vqPe
#UGXnflvk7OnjdwCurebWpchMwlQslnBz5MGl2dT3GzIAlkjUB44erul0+kIyNV+ymPeIar22dKzP
#YxZEcDns0Ot0XK3V1FaHHgCHAGQAzBBRkZkdAHo23gOhzdA/XjnvFL91oxMAAAAASUVORK5CYII=
#}]

set bold [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABw0lEQVR4nHWS
	PWhTcRTFz/nnvZcUE2tBpLS6+YUdSiuFBhutYIuDdIhEdPIDESpiKbgbHQTFQXBxcFCHLiKolCBt
	/CAR4tBB0aoosYMGFbVCtUn6Xvwfhyaxi3c7cA73x7mXWDGRsAdjTFOXK1UAgCSSFACwIRbK5R3T
	D58mF3+XFQqFZCX2dm8tbtuy6S7Jzw2fQ1LhsIfpbD518erNMT8I4LourBUinoPRY6l+SeMk5yXR
	AIAh8WuxIt8P7MjwznunTxw6d+po6oLrOqUbE/cPAojXKenUGeF5Ho0JmaHBeHEgvn0SwObns2/n
	n8287CiVvsQAIJ1OwwGASnUplMnmNwIW6UvXjrStiR0HFJ19UzS7BvoWOjvbf9YD/FdJfVMk4rZA
	csKeZzesb6+9ev0+ms0VEpIMSdusc+JO5krP7gMqzLy4Lqlf0sjXbz/Odyf22zNnLz+R1ApgGYkk
	fN+XrGxmKtf2Ye7T3mp1yb4rznVZiR3r1n4H4DcDVkJsVQs9zzWTU/nkg0eFJEkEQYC+nq6P4ycP
	3yJZkUSncZChPYnbIP80DgcAq1uj5X3Dg48B5JZBKP73NQjUghr8oLbSgr8z0dAB8uUYfAAAAABJ
	RU5ErkJggg==
}]

set italic [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABdElEQVR4nH1S
	vUvDcBB99+svqSbWDzo5qFAcBQcptBHaDoKDbraC/4OLDk6Cs4KTODgJjtoO4iSIotC0Wigo6FSK
	n2AH8SNWoTE5B02JKL7lDu4ed+/eAX8gGFTBzIKZRTCo/qiRlzAzERE/PDwbh2YprSiBCAnBdsOu
	JuLRXDjcYTIzySaTiFVFwcnpWXpxZX3GbjTw4bjQdR261kqqIk0iYvgnfMf45vbuwWBiwpmdX6zm
	j8srt7WaQd89Er9RfH2xroUIiJFUPDs+mpx7fLKaWwi/HiICgP79fCnWprd8JOND5uOThU3mgNfU
	JGwBxMywrLeBq5v7SF9Pd1XTtHMiQgbgX4RJIqerMwSzVI691t9lajhaBFBhZsBHkMxMgohvajXj
	6vJuKrezN+a6jtveHuoFEANQ8AuUX+eUuDivpBeW1qbr9TpkQGB5dSMVCmkZVZEF/znJb9hRoTSh
	qEqEXZds26kmjWjWM+yHBx7+ewkPn8K4qjIa4qfBAAAAAElFTkSuQmCC
}]

set underline [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABoklEQVR4nGWQ
	MWsUURSFz30z782MQxyFQNAulaJlQEgiwiZFTBWSQJqAvyCl/Y62QsAyjdqIYrEJpAqsBERWDViF
	VYJFOovAEHadt7tvZt67FmZioqe6fPdcLucAF6SUxL/6jzEzAUDW78/utT8+y7L+bL3LsjPW/8Nq
	L4JAobXb3px++Ihbu+1NJX0o6V9iQaAAAAIABBG01jDGcJ7nZIqSTFFSnudkjGGtNQTR3wMAEEJA
	CIIKZOV5gj1PsApkJQRBiHMbBACy1iKMI1NZR9lp74a1LrLWRWczXYkjY60FAPKbzSalaYrBwHzZ
	evlu8OL1zqpzcADw6s3O6sT4Nb04f/+zKUpKU9B5cmYOD7tHT5fWN06mGms81VjjpfWNk+73H0+Y
	OaxbIgDo9Xoze/ud5TCKglD6d78dHd8EgDu3Jn+Oyqo7Gg7NQmNmO0mSjq+UxMHXw+XnW28f/9Ia
	YIaSPgCgKKvbIJobi2NcvzoGpWSn/jD9/sPBih6OIIjIWksA4HkeO2aOoxDzD+61kiT5RHVdYaAu
	1XdRzjmMTAEA+A2EQMq52F3OXQAAAABJRU5ErkJggg==
}]

} ;# namespace 12x12

namespace eval 16x16 {

set format [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACqklEQVR4nJ1S
	W0hUURRd+5x7nRlrMqxEeloZJCUVhH30QsggNciSIMH6CMP6iqCgL2f6DL8iIgr6iN4ERU+JtAcR
	YmQhSanZmFpiOdnDprFz71l9OMIg0Ufra3P2Pou11t5AGkiKiIBkJsnNrztjtSQ3kwyRFJKCf6Gu
	rk6liDbt2nv4Q9GGHaM7aw9/MMaUp/f/CZL6/JVbx5etq+SK9dts4ZoKnjhz8RzJ0LjK9HmV9nG8
	znvS0lpsrU/HdXwRsPFRcwmAolT/7wSRSAQA0Ns/sPpNZyxfKxHrW+06Dnp6P+ZcvHq7kqQjIjZd
	xbhniUajlmTgRkPTxuFvPzJc17EARET423hoaHpSBqBwogo14aGgpbV9deJXEhVlJbEZ07MTxnjK
	dR2+6Xo//17T0y1jmwInElApwbMXr9Z3x/rmhTOD5sC+6rOFBYueWhJaKz+RTOL6nfsVABYCwvHM
	VGr39H07pfFh84b48DdZvnTx10AgYMtK1sanhCfR93ztas229q4lz9tel2s15hwAnDT5K569fLXK
	dTTaO7unrdlUHYEIkslRAQCtlf0+8lNduXa30vP9y5FIZJCkKBGh42jeufe4uP/j4IxQMINKlEdQ
	SCvBQIZJXafoMZsrP8XjJdFo1IqIdQDQGG/ukfqTW4e+fGVFafHw0eih27Hevgeu6zJ7alZ57YFI
	aVt7ZygzFLSfh4YD5y7d3E/yO4AGAYCRkcTBqj2HjnZ0vfPD4TAWLZg9eOF0/XYArKo5eLXj7fsc
	zzMCEdCSSim9tCB/6NSxIzUOACil7OxZufjxM6GNMQDU5KTnZaaymRQKBXV4cjYAgYhg9LeBJUVr
	PRYgySxjzO6BwXiW8fzYwrxZAwAepAiKu3v6ZgYDGXNEtAIsAMjM3JzmtJn/xx8i/ViQ7H4FTwAA
	AABJRU5ErkJggg==
}]

set bold [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACf0lEQVR4nJWT
	T0iTcRjHv8/7/t757t0Ex6abhm2V6aEMoiI6RdApiDC6dSi8BBV2WlFge60II+qSRn88FNTJon/H
	goQiQSQJcgeTbbqpGVHp2jv3vnvfp8M0N62Dz+13+fD9fZ/nA6xxiKjyDQDMTETEzOwGsHdsPFkn
	FGEDgG07pGmauS5UGwcwSkRcDhBlIC4Wi/vaOzofJpKZgCxLcJgBBoSQzeZNkVS043gPM98jgskM
	EBFLAKDrOgAgMZGuTSTTgflsDqZpmaVocHJG3jXwYbj5XOzmpaxhHASWU4jyOIqkOLIss0dTrdvX
	O6/W+KqTsiQjkZpaf+1W36mxRDr04PHzNmZ+RUQFZqYKADPYtm0oilDCjQ1xv7+mf7Ej7e27wf2J
	1HRwanq2HoAGoLAqAUukCCGoYJrFVGaqdSIz49Gq1A0fP8XDQyOfW91qFUXCDZMAcpVf0HWgqwtu
	VYmoqoqfc/Py6bNXzguhCJfLhVzOQDb7GwG/j/fs2m4B4KUNSv/cNQhCCEEA2HFQ7fXA7/fh+485
	6urubTMM4xAA1nWdlhMAyC9YqXw+D69Xw50bF+96vZ5BAppVVZXGExOuWHfv0S/JTLDv0bPDzPyS
	iMyKDshhy7ZtliQJwUDgTSDge7JcMLt379y2o//F69qZ2W8hAB4AKwAEkmUZpmlZk5mZLan0tDuf
	LwivVysOvB+KDI+MtgghpPpg3delIisAlmNJtm1TzlhwnYxeviCErJTAxAsFU5rL5rC1ZeOvE8eO
	PCUiMxaLSUsuSETkWJZ1YNUpo9S5IoS5uSmcjJ5p72kKN97/e86LgP/KBJSEqta0QqgkVHylUGue
	cqX/APBwJvzm4ttEAAAAAElFTkSuQmCC
}]

set italic [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACA0lEQVR4nKVT
	S2gTURQ9dzrppGlKUZESarVSoYuIVaL4aYlZVEmooKCCPxDxsxJXoiDCTNClCIp7cRs3Km4UJEiV
	LlQshQqRFkvEUL+LhDRvMp05LpKBpDGCeODxuI9zz73nPi7wn5DGgKSICEkGAcTnFz73h7qCAwBg
	29X84Pr+AoBJEan4XL1RwLIsAUDbtsfPXLz+IP9lcXVPOAzSQ7FUxuBA5Nf9ezdPA3jqc5sEmpuB
	p1TVLRYXJRDQJWgYQpIA2NYPSakfg+TJazfufBqKpbyr6ds5kpccx9lPssvnAkBTB3X/mojYTsX5
	/n7mw6pwd7fs2Bp9YnQG7lad5SYuAGgtUxXxSGqPn79IFr7+7I30rSmlxscmq86yZLPZFstNAiT9
	ODL1Zma3Ujajw0OzoVDoHQAmEgnvrwKWZQEAlpbs2GxuPhoMGrJr+8hrAAW/u7YDbBii9vDRs1sj
	8SNMHr1QKpfVQdM0tUwm0/GnHL0hWav7Xzv1dnqsomxEhzdNh0LGq3Q63bay5leuXex0Xfdsbm5h
	i9GpM74nVi5XKgdIJld+XxNM09QAQCk1ceL8leLm0UPcljjM0dQpZ+e+496xc5d/KKUmGrktFuoQ
	z3OrvT1h6noHPc/TRQRS25nWyv7jiiXa+3Eu36cHxK0RRNu4Yd03AC9FRPncdjP5Z/wGFdwHjNhX
	CMcAAAAASUVORK5CYII=
}]

set underline [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACLUlEQVR4nKWS
	T0hUURTGv3PeHUeRbCZJLbIcaTEw2wKRqDAMLBmICRQ3EVYQtEppkwt3URuX7StoVaBQQQtn+kPb
	oAEJdRqdLCKbAYvQN2/e/VrMm5ghpaCzOZf7nXO53+8c4D9DAICkiAhJtvx03QEAaA2H50Vk828a
	ggc0yEMj4xOlkfGJEskhAEin02YnjaQaAJiengYA5HKFjtXC52jtDACZTOYPbTG30lnrM/V+jFE/
	FHIsCaiqrddU1RrjWBEgHDaV3/f1RdZCSIgIRJWWpCQSCSUpqrQiVd36VXYAGn8gRivqqF8ue2ar
	7O0WEQIoA8DC+1zE83wJh5u8JmO8hlHUQTw6emlyLd6XtBNTd16R7CcZJdl//ebt1/G+pB29PPmR
	5JEGiAAY5GxqeHBuMVe4+jzz5tjYlRsPDvcczC+vFGLZhaVYa0szzg+fngOQrfUZAAjm7IiIS3Lm
	W7G07+HjZ8l3C8uxt9nFmOMo2iNtdix1ZjaVHJwJ6kREKNgmSEaWPqymZp/OHy+VNva0t0eK586e
	etnb0/1IRDYauAUNzQBO5vKFTlW1W65biba1satr7y4ALQA2v6yvfy8Wf5hEvLcEIC0iWyTFAIDr
	ugMXr03dzxc+RY1xKFAlLbyK71taqqiEQo76vpWe7v3Fe3dvXQDwBIAEEB0QEFRXAAQBETSFQg6k
	hphkFbX4vi/bWTiRX13rINiwgY1+RWOHDnwF8KJmYafaf45f9TEsvx26WkkAAAAASUVORK5CYII=
}]

} ;# namespace 16x16

namespace eval 22x22 {

set bold [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADOklEQVR4nJVV
	XWgcZRQ9d76Z7s9kzSY2Nk0wjSBVFBt9iVDsQ60PJcaS5KE1Vh8qiMUnfRJFyOapiA/iH7QgBRW7
	FavEaIp/RR/EKkSpSW1pC93+miYm3Wx2Z/9m5zs+ZBc22Z1dvPAxMPfec88938y9Ah8jKX4+EaGf
	r5n5gpbLSqPCDQFIKh+XrjAmKX7sa4BJGleu39z77Y+/DBRdz7Msg9AAQJCQYDCQ397/yJn7t97z
	jYjc9AM3qwArAZGP41+98PnXpx43ROBpXcPm6LEJb3hw1xDJV0Vkph64WZMFSMbJGdTUfdu2zvRu
	6V4oFlwLAJRSeiWdjv72x2zfR/HJ3RE7nCL5ooikfGWpXAbJ6Gvjb596YPswPzk+eYRkW/m0l59b
	4l+efL9vx4g3OPpSkuSuioTNGK/SFiCZWgkASIlIRQ8BkCR5LH5ianRhMdl+7sLlXgCIxWJr8tdU
	qWJPADCVWbLDoWqRK612pZ1s0DQVI5Fgvh5GXcampSySgIGIk80NzC8mzXAgYJK6p+C6m15+/c0n
	5+aXwo892nfu7q6uMxXG4+PjdYGlzCgaibT0aO0h/sXUnhMT3z1F0FBKKcuyzIyTw+3by4jeYevn
	nxk5DyCxrht/KUACJExlWmIYChAKAK2JFjuEzZ0dyDh549A7H+5MXLvxrGXWNl79plIxtZJ2rkOM
	3gP7h356bu+eD27dWvRsO2x5XqkXgMpkssYbh97bf3p69qF3j3x6sOi6P4hIgqRRuei6GnteyVVK
	IZ3OXgmHghO5fGGN3xDBtX/m/9134JXDZ89fus9xCg8CSCDWTAoRWS2grWwuvz5GNInuzo65UCjo
	FVx3w4qTCQJArAq5LrBASAJtrZECgNaqn6SNZJTkvYePfjY6t7AU6NrUMb/5rjuvAmu/5bpSlEqe
	IYD+/udf+y8mrh4vFlzLMITUFKWUXlpe3vj79My2DZYlw4NPTAE4W05lI2Bth4MUQ4y//r708J+z
	F+p0BGxsby0+PTIwuW9o91sikls/K/7H2FwlRELsFtvZuaN/uqe786SILDSayzVGUvkd2w5XxzXZ
	NrXdNrSxsTGj4V5swLjxTmvS+n8Q9Ld7nq06pgAAAABJRU5ErkJggg==
}]

set italic [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACo0lEQVR4nJ2V
	TUwTYRCG39ntLqX8KL9iwNISK1ALhUC0aExQEyMxwYtHzybGg4kn9UpCYkw08YJ6MZGbepGDcjEk
	Ek0VK/JX0CIURYIIBoUW2O7ueHBrGtJuV97jt5ln35lvZj6CRTEzpTsnIrbKsARMZVs+3C6bTUQi
	odoAMAA7AA2AAoCISPsvMDMTETEzFw8G318cGZ/anyPLdnuOXANCfG09FpVtEk61tz13OiufAODU
	sthMjJLh8OCde73XhscieY5cGaIgYCuRAJEATWMsLf90Xb9yoZ+IfifNZAMn//658/TJ3kZvrTf6
	daE2+G6kLNDSuOqpcY6trce1E8cCfQDiqVDLYmaZmQOXr3Z/8rad5f4XL3uYuYSZizJdrpnjJFQg
	IiUyM7cvNBp2lZfuTvi8ngEiWjGLE7KBiUhnZiE0MnH011pccldXzVZWVIwxMzGzuCMwMye/l4WG
	J1tUVYOv/sAHAFGjnvqOHRuq+zg9W5/vsOPIIf8bURQ2/iaT+bJMwUTEgkB4/Xa4deH7j5K9e8pW
	Aq3+kK5z1onMCDYCWdP03ODQ6OFYfBN1HncYwGSW7LI6Fgy4e3wq4pdsIlqavSEAy0Y2GetrCiYi
	jYj42+Kib3Zu3r2rIC/R2uR7leySHTk2WqmImUvGw9PHl5ZXpabG+mhNddU8M8vZ3ALbBsRIXQwO
	jV7q6x/oLMh3iJGZLw0A67HYRmHXzbs3XM6qMDN3EdGC2RhTKtTYZoXdt+4/ffjoWbsoEph15EgS
	NF1HfENBc4Mn9vjB7Q4iGjSmMq37f44NKAFYP3/uTE95aXFUURMoyM9zsQ7HlqLMbCnKpt9XNw1g
	IuknUynM9rFoBMoARACbAEiSbKqqpt3tlmTa/BaeK/MXJG2AxZ37BxEFQzP6PitiAAAAAElFTkSu
	QmCC
}]

set underline [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACsUlEQVR4nL1V
	TUhUURg9577RiTKnsKwckIqgRZIQFEUSlaYWUURhEbQIF/1sglq0FKJFSJs2lqBQFGFjEIoUmkRE
	JCX0Q5sswxCMoHLSsTEd3z0t5k2NOa/SoG914Xzn3O/vfhfwMUn0w6bj86vxT8Q0bHriksy/+EwB
	JJme3v4D15vbGqPRWCk5OXJJJIFoNFZ6vbmtsae3/4Ak45tdCpCUe6a2rrOoZK+uNLU2pKKSxDQf
	c6WptaGoZK/O1NZ1SspN18gYMQATj49Scm1seMQgcw0ZGx4xkmvj8VFm0slYI9IAoDHGvy9JjCbp
	mwH3Zf6j/V9hOrQQYCUHAH+dCgB0rQ1Ani+gvxH+WrA4/70kvOrtKwJQSFL8aQJQ+OpNX5EkhJcs
	GgAQ9xUmqZqaGkMysatyy/38vFDi0ePnxc2td09KCgeD2TYYzLaSwpGW9lNd3S9W5+eFErsrNt8n
	mfC4PyKf1Pbk8FOSFtY1NNVfvBzZMyuY7VZs3fhg7ZpVXQDQ/fTlhvZ7XZu+jY07xw7vu3W8+uAR
	kh9T3IzCnrhD0pW0+sKlq+ciLR3bo0MjCAazAAFj4wnMD+Wganf5nRNHD50m+TLFmdSnDDVOv2Tx
	oyfPqm53PCzrH3hfCACF4YL+neWbOtevK46Q/ODHnSRMEtbakFd7Akgg2fEFAPI8t88APnl4lodb
	Y8yQ9HM4AqnaOo6jnt6+/WfP11ePfI0bY0iAxlqr8URiQpLrXe5kZ2UFks9S1lopZ85s+/rtu8aV
	K5bdcF2XJBVIaxiv3WyrjLR2bnNdF/yRC0EC9JIThGRg8soFOI6D5UvDA67rRlJagdTBGKPBwcFr
	spj4MhRzAr/ZE+k2YYV5obnujrKSJmOSWiSn7lBvTU73yxFJ64/O4A/z42aKeEbi6Y8DAL4DsUhz
	KuejSigAAAAASUVORK5CYII=
}]

} ;# namespace 22x22

namespace eval 32x32 {

set bold [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAE10lEQVR4nOVX
	W2xURRj+/plzTvfGUi42hpsSRMLFxobQUgWF8IABIyTYpnhJFIg+QcSALw00oCIhgcQHEyXogzFe
	Uo1yCUHCrQI2pDYVaEugKAJihGxZtuz1nDnz+7C7gGX3bAv6on9ycibnzHzz/f/8880/wP/dqFQH
	Zi7Z5xYYEd8fnfuYPM+BmcWgBgyAhAVgKIBS3qUMKROu1nncAUWjIAFmJiJiZh65c++hxh9+/KmG
	pNAernF5ONxbW/1429zZ1TuJqBPZaJRcFsODGAOo/OTzb1ecPX8xZJkGlHILukUADENi9/6WRTOq
	ptVnMplNlmU1YwBRKEYAAJBOp02lXNdnmTo8JBgvD4dtJjbvAmZQ9EYs3BdP0sGjJyqXrVy/9bOP
	NieIaE8+mvdEwDAMloLYVkrMqHrs5NZ31r6XSCTcsrKy/l3Fqe6eyR/s+GJ5x6nuqSc7z43euOXD
	1czcRkRXvUh4EkDOVWZAShIAjoVCoZuFycp9jqM6G5av2XH6zPmxrW0dNTeTyVoA38EjKQe1ZQD4
	mVkws8y9849UyiUAB+c9VXPAMg260RcPHm9tnyIEeSbiYAloItL5d/4BoJmZLNPQw8rDVw3TgOtq
	3Iwng1JKT8ABE8iJEgEgIrrVRvYDE5G2HRX65cKlaZmMDcsyePSoimtKKU/cUjnA4OzaGYZUAGzT
	NFhkNQIMQBAhnbENAOWd3T3L9h9pnaOUi1EVD0SemFHVznxbV+6FgGmY0iIA1yLR8sNHT6z59Mtd
	0pACDDABFAr6xx440jq859fLD36ze/+USO8N39BwSC9aMKcZQHs2WMX1oCCB5uZmAgDbVmMNaQSl
	ID7Vda7yra5tlTlAMAACgYjgui4yGRumKTWD9aMTHkq9WP/cGcOQKa21pw4UyYG6u75kEQopd/ZP
	MBiAEFIQCXGy62xg6Yq1azMZu15KwV6HWsEI1NVlUS3LuOwqN2k7KjDv6Zrf6xY/8/Wli1cSpmWK
	/BIMCYXGMOsRUorkn5Go3r330MyeC5fGnT5zftzqxi3rXFd3ElE3M4vcjilN4A5zHKUyQspAwO//
	7cnqqo1zZ1VHBRH6JaEI+H06mUrLl+uenfvqynXvt//cNbmto3Nay/G2xYaU3cWWodQ2JFA27hnb
	JgCG4yjK2I6wHUW5NohIp9IZEJEriA688doLH4dDQZ1IpnD8REe1o1QAQMGlGLAOkBBAXpmZOd8G
	bhcuzCzXNzWJSRPHdw4bFo47ysX1WN9IAIFiuINVQpGreO6UYYFcJVTf3IwNGzboSDRWkUymfFII
	9ltWEoBdDLDkYdTPUoUS6U5j5jGbtm5v6I32lfl8FqZMmtANIH7PBLLaC2iXNYBZ8Xi80HEMpRSi
	sXjFpm3bG3Z9f2S+UgqPPDwmsvT5hXuISDc1NRXcBcVKMkFEOpVKzV/yyptfXfnj6hDPgiQHlEim
	/L3RWJlyXAwfPlS927hq8+za6W8DcIDCVbNnBHw+n2MaUqRtR+i+eDhyPeZZY0kh4PNZmDh+3LVV
	r7+0fXbt9G1EZHudBaWK0hG79h1ubDnWNrNEUQoNwF9Wlpg6aUJ3w5IFewG0lJq8KIF+ZAZalhMA
	Oxjwx5Kp9N8cKTWH1+SDvZjkx4mBjv1Hr2bAv3A9+8/bX1qVcMMIaZogAAAAAElFTkSuQmCC
}]

set italic [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADsUlEQVR4nOVX
	z29UVRg9332dX7QzTAelWDNEoLakIDWWUi0NTiwaLFXDwhgTNCaGjf+Bq5lZGN24cMGCGBJjjIkr
	ozEsTJBaDdpiA0WZlKYj1YmNI7Yd5gfzq+8eF30vmWJx5g2oMZ7Ve8l3v+/cc++5373A/x3S7ECS
	tWNrv7mugMi6/38ctxD9E5pSQCkF0zRDAAwAGoAbwGYARQB5K68AyIhI9a9ytTgpbM1GksmfX469
	dfKVXKHYooT0+ryhTR7PllWtC9lc/lcQGoCKDB/4huSbIrJEUjZajoYJ2AlItp/+8OMTH33y+ZDX
	7YImoUSgtQZJQGSnoRRK5QoSV5OPHH3q0BkAX1iKNE+ghn1hoH/v5NX5hZ5KpaIMJcZvv6+0lisV
	FQz4GQwG8tVqddXUVEMDfTMAUo3WqAt7Q5EMkRwhOXJxZvb0waeP6z1Dz/GdUx9MkBzL5HKHSR4h
	2VUvp6M9YKsgIssAzpKUM2cnTmRzN2VzoI37ers/FZHPnORUToJtkDRIKgB75pML+6vVKjruDS1F
	hgemo9GoOneOLSSVFXP3CcRiMYqITi2m96UW0/crpbDzgfAcgEQ8HteRCLSIaBHRfwuBeDyuScr4
	xNSjK5mc1+f1oK939zSA6wDQSOGmCdTIunUmMdtfLJXRHvSXIocOfCsiOhqNOsrZlAIWen9cSHVr
	rRHu3JYKd3ZcAoBYLOYoiWMCIkKlFL78anIgfX15i8vlwu7uHd8DuGaFOGo+jghY5wBN0/RNXrwy
	mMsXxd/m42B/36RhqOIaP2fdz6kCdvPaMTuXfMi23+MH91/QmnU73x0TsNc3tZh+OLWYDq/Zb/sc
	gITTwk0R2NB+e3uasp9jAre133Bz9rNRtxfYhcfHoaLRKLDOfvf9Eu7suGzFSDwev/sEamTVABA5
	fLTftl/Xru3fAbhyJ/e+urKR7CJ5xGqxY5cTc8/eyOYl4N/E0SeHCwCesFpzyIp35IQNg0kqEdEk
	H3zj7VPvnr8w02co0S6XqyWTybZlsjnxuN166z3tBdOk6fa49fEXxt4/NjryuoiUnRCotwTh81OX
	Bmfnf/J6PW6YWgMkRASlctVYyeYDSgSlShU90z8MHhsdaQVQvt39zwkBe/DMa6++eHL866nHAGgI
	VMDftq1Fqdab5fJSqVha1hTxt/pWX3r+mfcAZJwUBxq4lpN0AQhapAigDYAPwA0AFaztI9MwjGWt
	HR8DdYs3/XJqFI0ocGvMhs+wf/0J9p/FH7vP2BfZ5nlOAAAAAElFTkSuQmCC
}]

set underline [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADzUlEQVR4nO1X
	XWgcVRg938zszOAS0E0MTUraNCWtpRhrkxB/WpQGRFeE5KEIGhUs2PpQ64tCbcrGUhdEoZq8FAKV
	Fh8s+9AH0QfRh0ADsU3j2h8shpCm2yRNJe02ocns7sw9PnS37MbdzZpUm4eelxnm3nu+851773fv
	AA+xCEgKSfm/xv2DZFkE94ODpEmyQtO0ksdomgaSFSTNxfoaBYKKiJBk+akffu4cjP7RdPnPK8fq
	19ccB0ARYaFxAGR4JPbOgc963m3asmmQ5GERmc5wlpQBSS393NHWsTde1xjkwXB3H8lAVqB8wUEy
	cDDc3VfXGGRbx944yR3ZnAtR1FfHcXyu6ynL9Km5uXl9sf4Zzrm5ed0yfcp1PeU4jq9o52KNhmEQ
	AiGpLWENaBCIYRhFbS+d9T/CQwErW4DrApn9ltnjJXCKSm9JAYDlLELbNmZsy3JI4tbt2QCAx9K8
	+YRkvgfi8dlykrBte94AZpYsAECsuqoypmsaR8fGa2MT17cDYCQSyTloSEokEhEAHItNbB+5GqvV
	NY3Vqx6PAYgVC5C3FIuISr9OvrCtua//TLT5r+lb9pc93+wheVZEzi/oTwAeyYZ9+8N7pqdvW/5H
	bLy4rbkPwPUFnKU5EAqFNBFR7cHW7xo2bRhRSuH0wFDTgcNfd5N8mWSZbVuwbQsky0i+8smhIz2n
	B35rVEqhYfOGkbZg60kRUaFQqGCcoosqY/O1yan3dn/Y9cXYtckywzBQt7Z6qmVrw8CamuphALgS
	m6g/M3T+2dGxiUrXdVFbUz3Te+TQR1VVFb1ZDi1NgIiApDk8cvX9znD3x5eHR6tSKRe6rsOy7pb5
	RCIFz/Pg8xl4on7dZLjzg8/Xr1tzVESSJJcuIEsESeoAXvrq6Ild/b9Gn5u6MV2ZSCZ1ALBM01tV
	WX7j+Wee7t+3+61jAH4SEa+UIzivgDx7XkS6CHyqSD4K4KnBoUtPjo2PVwHA2tWrJ5u2br4A4HcR
	iSMU0tjVJQCygxe8RzxQ5DiQZXcAwBbHcXx5jlNxXYjnJeC6dzM0DIiuWzAMELlZw3VdsW07BSAq
	IjcXTktOHUgHt079+Evntye/fzuZdDVI/kul5OgnCnpLoWkaquP1106Q3C8iiezmewKylPnPnrvY
	Er00XG6bPigub9o0ETjJFDaeu9DSHmz1A0hku3BPQDp7ARDf9UZ7r+kzUrN37hj6v7gJ5YOnFMr8
	fvfNna8eBxBfOAV57dU0DZ7nBQDoQGF3S4QA8HRdv6lU3mr8YFGwEN2Pv6KcQCuxBqwI/A3NQuSg
	K4rQHgAAAABJRU5ErkJggg==
}]

} ;# namespace 32x32

set toolbarBold [list $22x22::bold $16x16::bold $32x32::bold]
set toolbarItalic [list $22x22::italic $16x16::italic $32x32::italic]
set toolbarUnderline [list $22x22::underline $16x16::underline $32x32::underline]

} ;# namespace icon
} ;# namespace comment


bind AddLanguagePopdown <Map> {
	ttk::grabWindow %W
	focus -force %W 
}

bind AddLanguagePopdown <Destroy>		{ ttk::releaseGrab %W }
bind AddLanguagePopdown <ButtonPress>	{ comment::UnpostPopdown %W }
bind AddLanguagePopdown <Escape>			{ comment::UnpostPopdown %W }

switch -- [tk windowingsystem] {
	win32 {
		bind AddLanguagePopdown <FocusOut> { comment::UnpostPopdown %W }
	}
}

::shadow::addBindings AddLanguagePopdown


ttk::copyBindings Text Comment

bind Comment <Return>			{ comment::TextInsert %W \n }
bind Comment <KeyPress>			{ comment::TextInsert %W %A }
bind Comment <Shift-Tab>		{ focus [tk_focusPrev %W] }
bind Comment <Tab>				{ focus [tk_focusNext %W] }
bind Comment <BackSpace>		{ comment::TextBackSpace %W }
bind Comment <Delete>			{ comment::TextDelete %W }
bind Comment <Control-d>		{ comment::TextControlD %W }
bind Comment <Control-D>		{ comment::TextControlD %W }
bind Comment <Left>				{ comment::TextSetCursorExt %W insert-1displayindices }
bind Comment <Right>				{ comment::TextSetCursorExt %W insert+1displayindices +1 }
bind Comment <Up>					{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W -1] }
bind Comment <Down>				{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W 1] }
bind Comment <Prior>				{ comment::TextSetCursorExt %W [comment::TextScrollPages %W -1] }
bind Comment <Next>				{ comment::TextSetCursorExt %W [comment::TextScrollPages %W 1] }
bind Comment <End>				{ comment::TextSetCursorExt %W {insert display lineend} }
bind Comment <Control-Up>		{ comment::TextSetCursorExt %W [comment::TextPrevPara %W insert] }
bind Comment <Control-Down>	{ comment::TextSetCursorExt %W [comment::TextNextPara %W insert] }
bind Comment <Control-End>		{ comment::TextSetCursorExt %W {end - 1 indices} }
bind Comment <Control-m>		{ comment::TextInsert %W \n }
bind Comment <Control-M>		{ comment::TextInsert %W \n }
bind Comment <Control-s>		{ comment::TextInsert %W \u2423 }
bind Comment <Control-S>		{ comment::TextInsert %W \u2423 }
bind Comment <Control-b>		{ comment::TextSetCursorExt %W insert-1displayindices }
bind Comment <Control-B>		{ comment::TextSetCursorExt %W insert-1displayindices }
bind Comment <Control-f>		{ comment::TextSetCursorExt %W insert+1displayindices +1 }
bind Comment <Control-F>		{ comment::TextSetCursorExt %W insert+1displayindices +1 }
bind Comment <Control-n>		{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W 1] }
bind Comment <Control-N>		{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W 1] }
bind Comment <Control-p>		{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W -1] }
bind Comment <Control-P>		{ comment::TextSetCursorExt %W [comment::TextUpDownLine %W -1] }
bind Comment <Control-a>		{ %W tag add sel begin end }
bind Comment <Control-A>		{ %W tag add sel begin end }
bind Comment <Control-w>		{ %W delete insert [tk::TextNextWord %W insert] }
bind Comment <Control-W>		{ %W delete insert [tk::TextNextWord %W insert] }
bind Comment <Control-T>		{ tk::TextTranspose %W }
bind Comment <<Clear>>			{ catch {%W delete sel.first sel.last} }

theme::bindUndo	Comment { comment::EditUndo }
theme::bindRedo	Comment { comment::EditRedo }
theme::bindCopy	Comment { comment::TextCopy %W }
theme::bindCut		Comment { comment::TextCut %W }
theme::bindPaste	Comment { comment::TextPaste %W }

theme::bindPasteSelection Comment {
	if {![info exists tk::Priv(mouseMoved)] || !$tk::Priv(mouseMoved)} {
		comment::TextPasteSelection %W %x %y
	}
}

bind Comment <Control-Left> {
	comment::TextSetCursorExt %W [comment::TextPrevPos %W insert tcl_startOfPreviousWord]
}

bind Comment <Control-Right> {
	comment::TextSetCursorExt %W [tk::TextNextWord %W insert]
}

bind Comment <Control-q> {
	%W delete [comment::TextPrevPos %W insert tcl_startOfPreviousWord] insert
}

bind Comment <Control-Q> {
	%W delete [comment::TextPrevPos %W insert tcl_startOfPreviousWord] insert
}

if {[tk windowingsystem] eq "x11"} {
	bind Comment <Control-Z> { ;# the <<Redo>> binding is not working!
		comment::EditRedo
	}
}

bind Comment <1> {
	comment::TextButton1 %W %x %y
	%W tag remove sel 0.0 end
}

if {[tk windowingsystem] eq "aqua"} {

bind Comment <Clear> { catch { comment::TextClear %W } }

bind Comment <Option-Left> {
	comment::TextSetCursorExt %W [comment::TextPrevPos %W insert tcl_startOfPreviousWord]
}

bind Comment <Option-Right>	{ comment::TextSetCursorExt %W [tk::TextNextWord %W insert] +1 }
bind Comment <Option-Up>		{ comment::TextSetCursorExt %W [comment::TextPrevPara %W insert] }
bind Comment <Option-Down>		{ comment::TextSetCursorExt %W [comment::TextNextPara %W insert] +1 }

} ;# End of Mac only bindings

# Don't use:
bind Comment <Control-h> {#}
bind Comment <Control-o> {#}
bind Comment <Meta-greater> {#}
bind Comment <Meta-BackSpace> {#}
bind Comment <Meta-Delete> {#}
bind Comment <Meta-b> {#}
bind Comment <Meta-f> {#}
bind Comment <Meta-d> {#}

# vi:set ts=3 sw=3:
