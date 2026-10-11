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
#RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABUUlEQVR4nK2R
#sU5UURRF1z7vQUVDSYnldMwQpQDuQDKFJhYk3IlCQUX8AYZIBcRYW/gHdOZS2suLNGiYxMIJvY3x
#AzTy5t1jMxBMbExYzTnJ2ien2HAftNfioL0WB/9ydrPEGAtAndXYk7MnOFhY7z8FNHF/H0xwL3jh
#YiTYs+wvAW+1Wn4T0J3py8tbs7/K68+gOVnezNneILaHH9IwxmgppcYAQggFoJ9lvQV8ceXDxq0v
#8U6ufeD2gwF0u90MuGBbZh8dT+b0HCrwpc7KxlxKKQMmODSAhTB6YMYV8M2d3+XU9Py4vt4Xvgh8
#vzw7HYQQSgvhzOA4S3kH58SsXsxjVnxc9yR/TqO37jwGqKpqLEDt0H9UTJXnTV2fDqv0DKCzHh8W
#Vl40Tf1esiee/WTGf+wa4FLjZWGvJT61YpwGJLcS05HjI0mv3PPX/6t/wh9ibYL3ZlmflAAAAABJ
#RU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABN0lEQVR4nH2R
	MUsDYQyG3+S7o72zIPgjHIo4VIcOxarg6CD4FUEX8Qc4+xsc3NycC9ZZ136OSl2c3OrooTgotfYu
	X1x6R6XWFzIk8CRvEuB/0Th+FQotbx3MhSOJ8rzn2q+zOmi1aSsR6x0xx15UmMmoos9e9+5d5wVQ
	AKSck8EoixWY11S3SbIGS9qAaiKMMwBqbYsBIMgBNoECGPRuO495rba20yYTnExaL4Dhd+rjMKys
	bLYuSHXgoQGTOVSvxwA0SRICgMJSIZ8vxyMiugHpfr1uI+ecAKBiQrkUMoDPXvfyaJKvre8+pZHf
	AHBtrTUF4CUjDk282mwtqU/fAIBK5UWVdEHI9AGgU63q9FmJY68qBAIxs5fs9KF7dT6272c+TqKM
	3r+Sj2fnhnnTqX3/krXWTOY/ZDR/pj+053IAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA/ElEQVR4nJ1R
	MU7DQBCcXc62XFgCKh5AT5vu6DjRRAL5GS54AcoLKPIMhCN3ERXXuaFIFQk+gCgAKcUJ+7iliBLZ
	UYJEptyZ0czuAv8EbRue6eFhmsQMAO67CTNbfa043hQbUySK4tJ7nntPc0VxaUyR7DRMp+Mm9dF1
	COFTRG68NFdZ9uZXvOrLbxkYBRf9HEMQRQ6T57pys071XoLWTwyAIGFIJK91fe+01gqA7Ky0JOUC
	Qo/bjtI1kLXWDwZ5KqBTEFcAxNrz0DWsd8jznF/em6xlXELQpu3BxzJh1DOsExaLE6UoLonojpmP
	nGofjCnizUq9jn89bG/8AiXJXn04QvBxAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABKklEQVR4nKWQ
	vUoDURCFv7n7kx9FEiwEC8EiBALBIikDEiwsra5FHsDSVxCfwXcQdCsrFUUIWNqIsIWNYCEISlLE
	VZJ791qsGyIIgp5q+M4c5jDwH7VaO8FvTAEC0Oz0qm5hcNHs9Kq5+QMTlZti3wNwNTdJw5xls6tl
	Xib/ewFJCkWxsKcACsV765BkdmMaMKGf+I4SxpRh/yWDukxAyYT+NKQAp7X24n40QjiTghy3u7re
	7uq6hCoS4TTuRyOttQc4ybsADqDd3T5A2PjClzdXR7uzO3mAZqdXDT3nzfM0fPMXVwDmzOvjiOXK
	2Iq9uz4c5CkaDR0WlzhXSq06m4Iwyd5EIJ4iTdOHj2c24zgaTy+srW9VfMo+gLVGADzPdwCGxNz2
	T4b8RZ8ej2cT72+H2AAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACT0lEQVR4nKWS
	z0tUURTHv+e+Nz91hogaqP4AYTbhTJhM1PNHlFAMRVyLCFoEgcsWZWAgLlrUohZuAqN2ETx0UUEt
	LOcVWBuftTDShbs0Jph+mE5v3r33tHA0lbSg7+pwz7mHz/fLATYXbVL/u5oKxVRToZjaakZsfJBS
	WgAo3376SDqR/JROJOebO2UXAKr3tl6QzWYZADPrPmb22RhfGFwHwPXeOm30JgCY5sNndtugj1qp
	Qc24F4/FJsMw2OePub6UUriuq/9I4DiOAAAyWlqWDSJciFs/50MVTBHzNQB/JSAAnGuTHwg8A6L9
	MLjNFqYtYY8o8J7J0Ydz6O8XGBgw6wjqAXG+ozsXicaatKCrDAyRRb0pnXzKxnwVSl0CAKdUWv23
	WpTL5WUa5h4VBjNvX7jv7cXoTRKiYYGqjtLmBgnR09oqE57n6RX6FQsEgAuFYiqIxWYB2ADeANAk
	rGPGaC8ZLp0M4umK1uqiP+YOOY5je56n7Hp4ViaT4dkyjgrL3mFU+BhEUQAWG/PMtuyuKhq3m7D2
	QJDoA3A3k8nwb4J6KPk2+RwAJkpu59pk8+3dUwx+HYaRy4k4V4Kw1v7OGy45jmPTypJchzxhkTVi
	WN+Hrl6pZhLfASD9DY2qhjsQJI0x5wC6RULMGRGcLR7YO00AyHHOx36IJZ+E2AWGMEod918OvwKA
	3KFTB0XEfsLGaADbmFGxI9GkUrVBf8ztXb2DrJTRnbVkMvz8RY+PP1pYa6GlpSsdJGKiIWS9GCHL
	jkR5YjS7ACzfwn/pFxFh+Y/AtFX7AAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB6ElEQVR4nJVT
	v2sUQRT+3pvZVRPyQ9RrLETsRBFZWLGQPUVRBAl6LgoBK6Nd/gM5rknrX2ApBFbtRIsQvTKHy1Wm
	0sJUclwgeC4Xd3fmWeRu2SxniA+GgW/efO9735shVCIMQ9Xr9aiM1Wo1iaLIVHP/N+gwIHlBI2Ct
	TlsrAgCsGDan7/Hn1Y2DCAiA+P7ibD6d/lSsjhlrcogwERmlXcfYfBU7357EcWwAyGiB9/Ntg0Qc
	a9KnOnFPuC6dUsngpDW7dxXrxzJzdgmADYJAjW/sI9DaFQAMUsNO5/Wv21ejnc7Gx8GX9bcfsnR3
	HYT7wJ6pEwnG7YjJhwDQasGCIJeChXlW+jxZ+goA5Snp8s3EIaUJv1k5Le96+AwCFsIRABeIaM6w
	eQkA7YMVyIRxSRcif5SoFQBAFEk1gwDA9+/MevWH1qs3FqoJl288uOffWhSv3rgCAGg2+V8eCIin
	9nKaxXn32sX3Js8MiM8BQLi5SUXl0S6ed3MOM/N9InnOydE3ritqoBLRmNJg84KZli3ZM/FatDUq
	bisKjkOIMmLnVT6dbg912lfk9sGmx8zLNjdL8Vq0NZJvywoKL7zgUcBaiqcsIqQdlWZ51ul+evdj
	rHZC64eIkidFxSow6TsDQLtdt0DLVvG/oozCK26QQLAAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABiUlEQVR4nJ2S
	P0scURTFf/e9ic6SLGLQ6SwthAjBFFERZ1OIgRXEyKvzLdIOfoB8hYCF1VQJqIiNCxIUQQuLNCmC
	5Sps2GHxT9x3U+xukNk/Jjnl5dxzz+UcoT8kjmP7cBBFkaZp2hyw8++QPjOdXiiPDg89XVZVAyCC
	8V4uTw+m9mHDd8gmv50kiQA8MeELEbMpIlvWBluI2RT0Yxz/GGofkX4O/jh5tbJS0EZhR8APF4ur
	vprdHx2l1w9JwYDX9CrL/JgpvAb98PXLp0xB8he7XgBwzhmA50QlY23ovewCIu35owLVarX1n+iq
	v29enFXS7wD0iLCnQKVS6RDLwDZAvhP9BZyzAC8X303aIJhQ5DO0SvRXApqmHlBrzVvfbN7Uw/pB
	y33q81zokcLcrAvno2Jwm2VrCscjQWBppzLIgQASx+/DXyEnd43GT2uDN0YkNtfPajOL6wsASZJ0
	Oc7FmpiZ0rclY3RcFQ8gIv72rrF3frhdG+Tkv9FVZeec7fSgg3asPS//Bh+Sgu1DeyYbAAAAAElF
	TkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABoklEQVR4nLVT
	wWoTURQ99728aSG0mK8QhbhIyMKSJgxmaLuxitxiQ/4lZK9/UUQcBHUnFmG01E3pQumiX6FNHdok
	773rJoMz00G68SzvOfe8yz33ASUwswZA5ToAWnL/GZ1wr9fsDhvZq9k0ze6w0Qn3emW9ygkRRaO6
	AElgFjsAwMyKmRUABGaxLUASRaN6vkfl3dJ0qkTEiciNHYiIEhGXptNCjyoLl+Iqg6rFVhkIaZDF
	ePyXG4+VBlngpknBwJiLKyFKHeQeJhN/BugzQGMy8U5wX4h+G3NxVTVJlj9aIb/sDPZte/NpK+Na
	Ibc7g+euHfKLvBYoHgwxszr/tbIauPl7XTOP7GL+DQBqJnjorT2cafPk7p3ZdRzHHoCUDQpoh7wP
	ot2l6N3J5zevq3QFgwfRqL6qRdeml3J8/OEyz21sPF6z62t07ch9/3SQ5sfWcRy7Vu/ZpjLm0Hun
	CKIAKiUkXkBekfbeLganX95+ZWadnao0u8PGSmC3vPeaiKSce1ZTSrnZvPbxx9Grn/9awa1RSKHf
	79/quyZJ4rBM4Q9YLKWGiun0CAAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACsklEQVR4nLWV
	v2sUURDHv/Pe7t1e7k5NCNiEELQTFM1pLPeClhaSZAOi2AQiAUutVJZtbEUQi2CjCBYvia2QqLlg
	pxciyKH/gIViNGRzv3b3jUUu8e6yd4ZAppxhPsz7zo8HHJJRJ7/jOKJTklJKA+BDqchxHNkt3l4x
	AeCRketHdDq8zFoLloiYNREJZk2CDPi6yqtrH9RPwBWAp+PALc+1bVsCgE7Xb5mWNW9YlrKS6YWU
	lZ23kukFK9UzlzRTb4yE+HrWHpsBPO26bqxkRpyTgTRrjoJ65VUIfGMmQbSjKR8HiSnLSj89n5/8
	4XnevOM4UikV/RcMQiCEkJroxdo7tdgeztnjc1pGiwz9AHBfK7VXjngwMwGABB/L5abNTKYmfT8Z
	AUCl8puKBbU8nB//QiTOXLj0uffjW/xCoz/dwbuSULhanA0YCKl5vFxX0Eqpn4HyVmjW4nK7gsHa
	zOWmzXymJnN+Mgr6yolkvZaNVkr3zGRqIKiVn5cKc/6+NSYSMopCEMQTZNcf+USEbJnNAIYmHDUM
	MxnWaxWK+HGnmmJHhRsat3kBYgFgIwqCdSGNFKR4lrOv9W9vYmtOh7XVkZQGGPo2NvuGMrrnBDb7
	hswKDWYYJ7UhT0dB7WWiJzMMEd4HwI4z2cLqrjGJoNjavKAR8U/ZzgwqW1fAuGrb9h2lVIimyegK
	JrDR3Dxge9xSqV4uFmb94fyED1CmwQn3UTExAESgP2vF2aCp0l07Nzo+ZiasgaBeXSosF6qu6wrP
	+7concCm1joSzDdzoxMXt1eaNUA7DRokElOsNYjEQwAolUotzYsfN8AnQdJMpG5Isfc6MjOCevV7
	vVa9u7ay8B5whVJe1MZoZ8afTQAgEixYE0ljQ0N/Ki6pDbiugBd/Og9s3Y79gb4m4JC/p272F1RY
	PDEHzAz8AAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACNklEQVR4nL1V
	PW8TQRB9s7tZnxPHggJLNJCGJhIIdIkEDRfER2EkCsQBQrTkF9BQWQYhKv6AkWgpDhokQCIS5JoI
	KbkKyQ1NOiRTBBHjj/PtDoXjxI5in5Ehr5x98zQ7M/sW+E+g8Wgl4ftVAoBarUaFQoF7J0EQWAA8
	NPVfI61iAsBnL948pbRz2pg2iGUWZDoMJBIi0bOzn9fevtzucXuJarRuiYAySylfOdkZt9MWsNZA
	ygxICCil0fi19RDAc8/zZBiGyZjCZd6p+1G7UT9vTbIgtS7G7dYKEa11qGWhKACAMAzN37RiAO7S
	7cqU4zwwzd+L6+GbjVHccYQJvi/cLeRgeJMZpsU0dwzzrXr9O0VRJcEBWyHSVH3fFwgCw7E9M6Wn
	j4BopRoG9UKhylFU6RwkOpZwrVYjACAhrwopQeAP/fFhSBXeG4q9HrcbbKHDbnzJpuWOQEkAwLlL
	904uXL5j3aVb0c5B6mxGVux5q6JLij2dmQaAd924JycS3vMEKlpjCIo+DsaHY9iVyHWXVS53nH+g
	6jjEm0SQkDQXHUUdYxhPaq8WvbsLMqvXO63Gi2j19XIaf5gwAWD3in+CrLjPzIKZLyitr5k4fi+k
	2rCcfIk+BSvYZzr7MdDj3aEk7Gdn8k+1k32iM06RrVVKZ25kpnOPwXjWZZdG3nbAhHo7m8nnK83t
	n98MrCJAgeVUQnHTWAtjzNcuu3x45t6PoVvh+/5um/q/oyCYZ6A8yaubDH8A7p/fKJqfbw4AAAAA
	SUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACOklEQVR4nL1U
	MU8UURD+Zt7eHevdBRrpbSwoJHKFNnh4MaE0Sl5HYiIJf8DSglDYGX+AJjbGaiWG7kiMelJZcAkW
	l2BjRbM2R0CP27s3Y3G3uGceiET4mtnN982382ZnHnDBIGut+ZtoqKELqOc3/vwaAdDp6t0JQ4Ub
	tD/xfmvrec+XWKks57Tcrjntft5urLfT3JTnrLharRoACCi3FBZLdS23a8DRkZF91nK7FhZL9YBy
	S9lcr3EKZSqqiAhr+bijCmtZRUSZij7ea0yAA8A8iF4MOaZjNF5jqNIgyLF//Igbak9n/B/gb4Wq
	AFAmMsAKx3F8VFUcx4SVFSYgAKD6T62A2VGA4HQOWJXdMDSw1sBasxuGBqurQg5zCpBCd7zF+d6n
	qw/GA+58ZWNKLknmm5/WNrOimdrCrOHChrjeQV+Sq9uN9b0hpSNGWVhrTRRF7np1YbEwdulVL+l2
	AX1CTHVVJSjmCfQ4yBcKSbez2Pz45nWac1LFI+Yzt+4vc5B/mh8Ly64/WEAT5JAcdvbF9R41G2sv
	fKbeVqQb9H1ykltRlFybtVdyeb4HJxUQFMzNXiJvv2xG36aszV+OYwGARqPhsq04N1AmauWOHYfD
	Q4CKEAEYUCUmGp0eVQiRCgSD/YT+gMHLrXfRXuoVAIC1lqMoctqnm2Gx9ExETn3JKgAmRufnQQvA
	Ruo1kj81ZfNjk+42IygJq5y00gBAxMpCLOgfHMbmQ6sVJaes5+zwzvFZjHwjdy74BVS4+BDOg50D
	AAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADvElEQVR4nO1X
	QWhcVRQ95773ZzKZNrWtzMK6EgxBqUECpdbAxEgxuLR9ikVxYVZdCC5cj3HlzrVLsQvhV9JFwdRq
	wlAsUp0qLoq0CzepymzaGjJJ5r/3roskTSQzfyZNoS564G3+u/++8+4797z/gcd4xGCvAOec6SdR
	s9lkpVLRNE3D3mntDUQfG9se3A0CII5NvuVE5FTwXsnO8apQChcB/bYxn15ef1oTYCY+KAEC0Oeq
	bl+JWEyKxQMxRpDSJVyhCqgGaNRLEtrT1+qzi/2QyCdw3B0qlXAL5BBU24C2Oi6vJInDIgKKRQzZ
	72Rx/Kfvv7wD1JBHotuWAADGJgpotLZgobjUzgrDIn6knRWGtw+qHUGMr0TVqzFkMDYZiWH1UwDR
	uRu5esitwNHxMwcLSfumTQae9NnaV42F9O28ZC+cfKecZO2GWHk2hNCi98ONK7N/5R1FbgU6kGK1
	WrXYUvr9MTU1Vfzt8rnlqPo5KSIi+2LBjgJAXhV2QwAAtFKpKIAdY2VlJTjnDAW3VRWkqKju75XQ
	9r+0csOUjHPuP1PNZpOlUsmkabr24sSpl0giBk+q3n54BIj2hst1czo/NvHmyxC8r6qIGhdZXvsV
	ANM07doFPQmokqoRUD4zNulOE2qjMm7NgyQOEPo8iWkAg4B6gJ80Ll5sOedMnj33JECqxOBB4QmK
	OQEAnS4HkvBZFkTExxj/ZlyZBYA0TTUv/25F2BWqETZJDAhL8CmawSujk+4IAF1vw87IrYCYRFWz
	aKxFyLKrCv9ZpyMAdRDKlsA/DXKaIiNGkhH1a18AerJW+xgzM53XyDWi0ep7T1hZvrVuRKvnGgvn
	3+1ViWPHpoZCeWiOwuMkGUJ49fpCOt9NC7toQxQ22xDbOqHZbBIAKpWK/rK0ZK/Nzf0zNvHGR9Ck
	ThEhwusA5jfjHpwAqWmaBuccclQdAbBUHrjRWm7fNTY5rIojmwQ7vbBbEXJjJx1HtVo1qNW40gqH
	SJYBVUKXgK1K7YWAAtB6ve7RwYrvz83MRCB8KMYMqEYC/CEv6W40UDw6fubgQLElq2uDO5yt7DNm
	xVChMWcBnoUCwWd/wvICANbr9Y7HlksghowQivdtD+K1QtK+GaNFIWnviM0SAGr2U0xR109bKTr9
	83fn78E5gy66ySUQTJZBYZJCwcYYLSmDefEKBaJCEf4I3n9wvf71N72suI+P0tNOJMn9KN1Kxjsq
	+iPu4kKjkd5DrSbrmngU6PN/4qH9mABbrbYhuNxL6DH+N/gXmd7O4AmTmIoAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC9UlEQVR4nO2W
	TWtdVRSGn7X2PjfXpJFgNZNMdCBCERQbI4J4jAHtTEk8OPUvCIIzL9eZI0f+AMGBcJJCZlbR5igI
	pk3RDqRSHHYSPwjmo/djn70c3JsmhtaccxOsgz7Dc9hrvbxrv4sND7jPyGjHWpplP1c6m+d5OVqP
	/4i6Dghgz768+KRPGu9bGScRi5gpyLgJHYwA4Jw3i73lq5dXLgIKxBMLSNPUF0URzs9nnzfHJ9/u
	9zqIKGYHtUUUMFQ9vc5et5+Mnb3+1We7++KP1vR1BExPTw8KiK30urdfjGVogqnBlJgIEBDbBomq
	QU1YeWqq27l+Wg4cZm7uwsONxx5xndvhJZBVdU5Cv/dxaRMfev7wARd+Kla3jqtTy4EDWvrDentb
	wJ57NZvzLpEYA4qsXis+Pdz0rrYfRkcT0I5CS6ClErkAYGW8NWFsDJq2tErzEwhoKbTj7MLNx03s
	6eHH74si38myTKEdqzQfWUCarimAlf1575ImFkG5BLC5uVnrXo0k4E4a4HVECWW/g+kaQFG8ctfb
	fi9GSYEAlqbZmR3hhksaM6HfvXJtbfmF4f9K1u9T24HBjGHHlc+L0xkwROXrgajU1a1XW8CdGUf3
	mqojliUgX8I/RlOZ2nugKIoSEMMWQLAYb50xrgDkeV5r/lDbgZYCNruw+AQiR+PnqDn/2gIO4ufm
	vfMPnSR+Iwk4zfjtU1W1QEugbWmaTWwLN3zSmClD7+rG5XPD+LVHElDFgeFOH6zXXeG8Op1h8PES
	tKPRtuH9qE0lB55J35jylD5wNjjZ/cAnjXdjWRoW32yOJ9/1fvuzXF//4q/TFqBZlsmvv/OJU12K
	MUYwxWQS8CZmAlsgUZ3vxNh/b+Ob5TzLMlfnIXqvPSBA/GVrbCKx7js+aY7FGAA5+vx61CySNJp0
	9sISkNdNw786AMTZ+aVF0cZbZRlkeMILNDHbQyRiouJ0O/R7H/347cWbVHwH/G841q7hhjuWPD9n
	o0bxAfeVvwH2tEjtrBs5wAAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADQElEQVR4nO2X
	wWtcVRTGf+e+l5mJkxZaMCAYF2JRgkrNWBJEMkaIm9aFibeIBgr9B7rQZctjloJ24aZQ6M6K8OpC
	cFEsCA8XBmkoisxGceNCGCFq2kxm5r17j4vJ6GQyM5km1rrIt3q8c853vnPOfffeB4d4yJC9HKy1
	AUAcTytU/Gi0kbG2Ku242B1E4EOFAZhZsGdnF1euzc4vnQAgiszAiG3b7PzSidnFlWszC/ZsN9fA
	JH0ggJ8u2wmUK2E+fz41wUUAW60OHFvHlprgYpjPn0e5Ml22E4BnwLgHVwPQJCeCS1uNTNDCUN8d
	6rWQthqZCI4muWG+QwUE4ZiCiiAhIiMuQEDECxKCSptjnwJ6aR+E7/0IeCA4FDCCAOleRKPMVlCV
	TqwJDrAItybW66hugKLKFKDtLbk/tm0KMgUK8Gc6Wa/vR4Baa4Ofbt5sAlVVVTHMvLhgn4aKL5fL
	YW9A+13Fl8pLz2B4QVVVlWo1jlvb50lf4buIeuGR6wG8biQoONxl4HSSJFm5XA4nJycVoFarSZIk
	Wbuk4LKRoKCqIFzfi3/4TKPIlL74NeDo79+YICyhivf+47ExvbD6Zbze7Tr3mj2eZuYjI/IOIniX
	3mbj+EtrZx5zVAafokM7EAGVtavpqYXlc+r91yJyzBizkqbuldKCvQF6Z7uOmTRl2Rh5HEC9Xw9S
	Offt2tU0OhOZyr47AERRZCqVij85/8apMMx9YoLgKVVFRFBtj7XzLGLwLvvRueztO8lntzuxw/hH
	2jKttUEcx+65l08fy+eL76K8papPmiAQAO+cFzE/A5+mrvHhd8nnf3Ri9uIeJmCHzVprOoRzc3Y8
	K8qzeJkCwOgv4ab+sLoab3UJ7q186H7QgyGXjn2jP+fADjy/uFg8mns0d/fepnpX3OVXyNeNz8YF
	wIRb2mg+smvWJtjUIxNF2Wj91vr+1q3NPQV05lZ69U1rzNgH3mUF0AN2Q7wJwob36XtrX92Ie9fG
	js+wVqu1Baks5/LjT6StBiIHy6/qGcsVaNSzZSD+O0c/AUmSOADn3KVmo35PnT+C6MD73Cj5UTHe
	1+86597vzvG/wYDK/vmx+Ldwfz82h/gP8Rd5+2ZLZwFRuAAAAABJRU5ErkJggg==
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
