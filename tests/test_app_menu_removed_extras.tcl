# ======================================================================
# Scidb App Test - every user-facing menu path resolves at HEAD
# (GAP-003; VAL-BAR-007)
# ======================================================================
# The old guard only looked for the word "Extras".  The menu reseal moved
# many rows, so a help page or an assistant reply can name a path that no
# longer exists without ever mentioning Extras.  This test extracts every
# "A > B > C" chain from the help pages, the tips, the player card and the
# user strings, then resolves it against the live drop-down, the live
# context menus and the action registry in the same language.  Every
# registered language is checked: the list comes from the product's own
# tcl/lang/localization.tcl, so a new language cannot be skipped.  Dynamic
# cascades (icon sizes, themes, a database's repertoire types) are opened
# through their own postcommand: a path must reach a child the product
# actually posts, and an empty cascade has no children to name.
#
# It also keeps the Extras check: no user string or shipped help page may
# send anyone to the removed catch-all.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::mpaths {
	variable Root [file normalize [file join [file dirname [info script]] ..]]
	# These hold the English user strings the assistant, the player card
	# and the setup scan show.  Language catalogs override them.
	variable EnglishFiles {
		app-assistant.tcl player-card.tcl app-ask.tcl
		app-setup-scan.tcl ai-provider.tcl app-assistant-panel.tcl
	}
	# Surfaces that are not the menu bar.  Each maps to the live context
	# menus it can open.  A pane name without a context menu is a terminal
	# location, not a stale path.
	variable SurfaceCids [dict create \
		"Board tab" {C1} "Players tab" {C5} "Events tab" {C5} \
		"Sites tab" {C5} "Annotators tab" {C5} "Positions tab" {C5} \
		"Database tab" {C4} "Game list" {C3} \
		"Analysis pane" {C6} "Notation pane" {C2} \
		"ECO pane" {} "Tree pane" {} "Report pane" {} "Media pane" {} \
		"Assistant pane" {} "Explorer pane" {}]
	variable OsRoots {
		"System Settings" "Systemeinstellungen" "Ajustes del Sistema"
		"Impostazioni di Sistema" "Rendszerbeállítások" "Systeminställningar"
	}
	variable SavedLang en
}

# The registered languages and their catalogs come from the product's own
# table, so a newly added language cannot be skipped by this guard.
proc ::mpaths::Languages {} {
	variable Root
	set text [ReadText [file join $Root tcl lang localization.tcl]]
	set result [dict create]
	foreach line [split $text \n] {
		if {![regexp {^[ \t]*\x7b[ \t]*([^\x7d]*?)[ \t]*\x7d[ \t]*$} $line -> fields]} continue
		set fields [regexp -all -inline {\S+} $fields]
		if {[llength $fields] < 4} continue
		dict set result [lindex $fields 1] [lindex $fields 3]
	}
	if {![dict size $result]} {
		error "no language rows in tcl/lang/localization.tcl"
	}
	return $result
}

proc ::mpaths::Ellipsis {} { return [format %c 0x2026] }
proc ::mpaths::Mark {} { return [format %c 0x25b8] }
proc ::mpaths::Sep {} { return [format %c 2] }

# The dump and the help pages differ in punctuation, ampersands used for
# keyboard mnemonics, "..." versus the ellipsis character, and trailing
# accelerators.  Reduce both sides to the same label.
proc ::mpaths::Norm {s} {
	set s [string trim $s]
	# Tcl sources spell the ellipsis as \u2026.
	while {[regexp {\\u([0-9a-fA-F]{4})} $s -> hex]} {
		scan $hex %x code
		set s [string map [list "\\u$hex" [format %c $code]] $s]
	}
	set s [string map [list [Ellipsis] "..." [Mark] "" & {}] $s]
	set s [string trim $s " \t\r\n\"'`\u00ab\u00bb\u201c\u201d"]
	set s [regsub {\.\.\.+$} $s ""]
	set s [regsub {[.,;:!?]+$} $s ""]
	return [regsub -all {\s+} $s { }]
}

# A path component may carry a trailing parenthetical or prose after a
# dash.  Strip those; the menu label is the part before them.
proc ::mpaths::Comp {c} {
	set c [string trim $c " \t\r\n\"'`\u00ab\u00bb\u201c\u201d.,;:!?[]{}"]
	# A trailing parenthetical is prose unless it is a real menu label,
	# such as "Motoren (Schachprogramme)": those are one word, title case.
	while {[regexp {\s*\(([^()]*)\)\s*$} $c -> inner]
	       && [expr {[llength [split [string trim $inner]]] > 1
	                 || [string length $inner] > 20}]} {
		regsub {\s*\([^()]*\)\s*$} $c {} c
		set c [string trim $c " \t"]
	}
	set c [regsub {\s+-\s+.*$} $c ""]
	return [string trim $c " \t\r\n"]
}

proc ::mpaths::ReadText {path} {
	set ch [open $path rb]
	set data [read $ch]
	close $ch
	set text [encoding convertfrom utf-8 $data]
	# The German help pages and catalog are ISO-8859-1; the rest UTF-8.
	if {[encoding convertto utf-8 $text] ne $data} {
		set text [encoding convertfrom iso8859-1 $data]
	}
	return $text
}

proc ::mpaths::Unescape {s} {
	set pairs {
		&lt; < &gt; > &quot; \" &apos; ' &nbsp; { } &hellip; ... &mdash; -
		&ndash; - &rarr; \u2192 &larr; \u2190 &laquo; \u00ab &raquo; \u00bb
		&auml; \u00e4 &ouml; \u00f6 &uuml; \u00fc &szlig; \u00df
		&Auml; \u00c4 &Ouml; \u00d6 &Uuml; \u00dc
		&aacute; \u00e1 &eacute; \u00e9 &iacute; \u00ed &oacute; \u00f3
		&uacute; \u00fa &ntilde; \u00f1 &Aacute; \u00c1 &Eacute; \u00c9
		&Iacute; \u00cd &Oacute; \u00d3 &Uacute; \u00da &Ntilde; \u00d1
		&agrave; \u00e0 &egrave; \u00e8 &igrave; \u00ec &ograve; \u00f2
		&ugrave; \u00f9 &aring; \u00e5 &Aring; \u00c5 &aelig; \u00e6
		&oslash; \u00f8 &Oslash; \u00d8 &rsquo; ' &lsquo; ' &ldquo; \"
		&rdquo; \"
	}
	foreach {entity char} $pairs {
		# The help pages use both "&hellip;" and a bare "&hellip".
		set bare [string trimright $entity ";"]
		regsub -all "${bare};?" $s $char s
	}
	regsub -all {&amp;?} $s & s
	while {[regexp {&#(x?[0-9a-fA-F]+);} $s -> num]} {
		if {[string index $num 0] eq "x"} {
			set hex [string range $num 1 end]
			scan $hex %x code
		} else {
			set code $num
		}
		set start [string first {&#} $s]
		set stop [string first {;} $s $start]
		set ent [string range $s $start $stop]
		set s [string map [list $ent [format %c $code]] $s]
	}
	return $s
}

# Closing block tags end a sentence (and a path); opening tags and inline
# tags do not add characters.  CQL help pages are full of "Condition 1 >"
# arithmetic, which the component filters below drop.
proc ::mpaths::Markup {text} {
	regsub -all -nocase {</[^>]*>|<br[^>]*>} $text "\n" text
	regsub -all {<[^>]*>} $text { } text
	return $text
}

# Return {line {component ...}} for every maximal chain in a line.  A
# maximal chain is a run of short " > "-separated parts: this keeps the
# leftmost component as the root instead of inventing "Einstellungen >
# Motoren" out of the tail of "Main Menu > Einstellungen > Motoren".
proc ::mpaths::KnownRoot {word} {
	variable Top
	variable AllLabels
	variable SurfaceCids

	return [expr {$word eq "Main Menu"
		|| [lsearch -exact $Top $word] >= 0
		|| [dict exists $AllLabels $word]
		|| [dict exists $SurfaceCids $word]}]
}

# A path can follow a long sentence with no punctuation: the Swedish
# speech hint ends "... Ställ in dem i Inställningar > Assistent".  When a
# part is too long to be a menu label, keep its trailing words up to the
# last known menu label, so the path after the prose is still checked.  An
# unknown tail is left alone: prose is not a menu path.
proc ::mpaths::TailStart {s} {
	set words [split [string trim $s]]
	set last [llength $words]
	for {set i [expr {max(0, $last - 10)}]} {$i < $last} {incr i} {
		set cand [join [lrange $words $i end]]
		if {[string length $cand] > 90} continue
		if {[KnownRoot [lindex $words $i]]} { return $cand }
	}
	return ""
}

proc ::mpaths::Chains {text isTcl} {
	set sep [Sep]
	set out {}
	set lineNo 0
	variable OsRoots
	foreach line [split $text \n] {
		incr lineNo
		if {$isTcl && [string index [string trimleft $line] 0] eq "#"} continue
		# A macOS Settings path is not an application menu; skip the whole
		# line so its "Keyboard > Dictation" tail is not read as a menu.
		set osLine 0
		foreach root $OsRoots {
			if {[string first $root $line] >= 0} { set osLine 1; break }
		}
		if {$osLine} continue
		if {![regexp {\s>\s} $line]} continue
		set parts [split [regsub -all {\s+>\s+} $line $sep] $sep]
		set run {}
		set runs {}
		foreach part $parts {
			set trimmed [string trim $part]
			if {[string length $part] <= 90 && [llength [split $trimmed]] <= 10} {
				lappend run $part
			} else {
				if {[llength $run] >= 2} { lappend runs $run }
				set tail [TailStart $part]
				set run [expr {$tail eq "" ? {} : [list $tail]}]
			}
		}
		if {[llength $run] >= 2} { lappend runs $run }
		foreach comps $runs {
			set clean {}
			foreach c $comps {
				set c [Comp $c]
				if {$c ne ""} { lappend clean $c }
			}
			if {[llength $clean] >= 2} { lappend out [list $lineNo $clean] }
		}
	}
	return $out
}

proc ::mpaths::Key {path} { return [join $path [Sep]] }
proc ::mpaths::CtxKey {cid path} { return [join [concat [list $cid] $path] [Sep]] }

# ----------------------------------------------------------------------
# Live drop-down tree
# ----------------------------------------------------------------------
proc ::mpaths::ParseDump {text} {
	variable Top
	variable Kids
	variable Dyn
	variable AllPaths

	set Top {}
	set Kids [dict create]
	set Dyn [dict create]
	set AllPaths {}
	set levels [dict create]
	set top ""
	foreach line [split $text \n] {
		if {[string match "MENU *" $line]} {
			set top [Norm [string range $line 5 end]]
			if {$top eq ""} continue
			lappend Top $top
			set path [list $top]
			lappend AllPaths $path
			dict set levels 0 $path
			if {![dict exists $Kids [Key $path]]} { dict set Kids [Key $path] {} }
			continue
		}
		if {![regexp {^(\s*)(ENTRY|SUBMENU) (.*)$} $line -> indent kind rest]} continue
		set depth [expr {[string length $indent] / 2}]
		set parentDepth [expr {$depth - 1}]
		if {![dict exists $levels $parentDepth]} continue
		set parent [dict get $levels $parentDepth]
		if {$kind eq "SUBMENU"} {
			# Marker for the cascade whose ENTRY is the parent path; the
			# children that follow are at the next depth.  It makes the
			# cascade static.
			dict set levels $depth $parent
			dict unset Dyn [Key $parent]
			if {![dict exists $Kids [Key $parent]]} { dict set Kids [Key $parent] {} }
			continue
		}
		set label $rest
		# [Mark] inside braces is a glob character class, not a command:
		# compare the real cascade marker instead.
		set mk [Mark]
		set moff [expr {[string length $mk] - 1}]
		set cascade [expr {[string range $label end-$moff end] eq $mk}]
		if {$cascade} { set label [string trimright $label " \t$mk"] }
		if {[regexp {^(.*?)\s+(Ctrl|Cmd|Alt|Shift|F[0-9])} $label -> base]} { set label $base }
		set label [Norm $label]
		if {$label eq ""} continue
		set path [concat $parent [list $label]]
		lappend AllPaths $path
		dict lappend Kids [Key $parent] $label
		if {![dict exists $Kids [Key $path]]} { dict set Kids [Key $path] {} }
		dict set levels $depth $path
		if {$cascade} { dict set Dyn [Key $path] 1 }
	}
}

# ----------------------------------------------------------------------
# Live context menus (C1 board, C2 notation, C3 game list, C4 database,
# C5 player, C6 analysis line)
# ----------------------------------------------------------------------
proc ::mpaths::AddRows {cid prefix rows} {
	variable CtxKids

	set k [CtxKey $cid $prefix]
	if {![dict exists $CtxKids $k]} { dict set CtxKids $k {} }
	foreach row $rows {
		if {$row eq "-"} continue
		set head [lindex $row 0]
		if {$head in {ask header}} continue
		if {$head eq "cascade"} {
			set id [lindex $row 1]
			set kids [lindex $row 2]
			set label [Norm [::context::L $id]]
			if {$label eq ""} continue
			dict lappend CtxKids $k $label
			set path [concat $prefix [list $label]]
			set pk [CtxKey $cid $path]
			if {![dict exists $CtxKids $pk]} { dict set CtxKids $pk {} }
			# A cascade with no declared children has none to resolve: a
			# path must stop at the cascade itself.
			if {[llength $kids]} { AddRows $cid $path $kids }
			continue
		}
		set label [Norm [::context::L $row]]
		if {$label eq ""} continue
		dict lappend CtxKids $k $label
		set pk [CtxKey $cid [concat $prefix [list $label]]]
		if {![dict exists $CtxKids $pk]} { dict set CtxKids $pk {} }
	}
}

proc ::mpaths::BuildContexts {} {
	variable CtxKids

	set CtxKids [dict create]
	foreach {cid object} {
		C1 {}
		C2 {}
		C3 {}
		C4 {base /tmp/mpaths-probe.si4}
		C5 {name Probe}
		C6 {}
	} {
		if {[catch {
			set rows [::context::Rows $cid [dict create {*}$object]]
			AddRows $cid {} $rows
		} err]} {
			# A context that cannot be built would make every path under
			# it look stale; say so rather than pass silently.
			error "context $cid: $err"
		}
	}
}

proc ::mpaths::BuildLabels {} {
	variable AllLabels
	variable Kids
	variable CtxKids
	variable Top

	set AllLabels [dict create]
	foreach label $Top { dict set AllLabels $label 1 }
	foreach {k list} $Kids {
		foreach label $list { dict set AllLabels $label 1 }
	}
	foreach {k list} $CtxKids {
		foreach label $list { dict set AllLabels $label 1 }
	}
}

proc ::mpaths::BuildLang {lang} {
	variable SavedLang
	variable Dropdown

	if {![info exists SavedLang]} { set SavedLang en }
	catch { set SavedLang $::mc::langID }
	# SwitchLanguage is the runtime language path: it reloads the catalog,
	# refreshes the registry labels and rebuilds the live menu.  Calling
	# only ::mc::setLang leaves the registry labels in the previous
	# language, which would compare English rows against German help.
	::menu::SwitchLanguage $lang
	if {![winfo exists .mpathsMenu]} { menu .mpathsMenu -tearoff 0 }
	catch { destroy .mpathsMenu }
	menu .mpathsMenu -tearoff 0
	set Dropdown [::menu::Dump .mpathsMenu]
	ParseDump $Dropdown
	FillDynamicCascades .mpathsMenu
	BuildContexts
	BuildLabels
	return
}

proc ::mpaths::FindEntry {menu label} {
	if {[catch {$menu index end} last]} { return -1 }
	if {$last eq "" || $last eq "none"} { return -1 }
	for {set i 0} {$i <= $last} {incr i} {
		if {[$menu type $i] eq "separator"} continue
		set text ""
		catch { set text [$menu entrycget $i -label] }
		if {[Norm $text] eq $label} { return $i }
	}
	return -1
}

# Dump prints a dynamic cascade as a leaf marker: its rows exist only after
# the product's postcommand runs. Open each one here and record the real
# children, so a path through an empty cascade cannot match its tail by
# accident. Runtime values remain children: the cascade itself and every
# label the product posts are checked.
proc ::mpaths::FillDynamicCascades {root} {
	variable Dyn
	variable Kids

	set queue [dict keys $Dyn]
	set seen [dict create]
	while {[llength $queue]} {
		set key [lindex $queue 0]
		set queue [lrange $queue 1 end]
		if {[dict exists $seen $key]} continue
		dict set seen $key 1
		set path [split $key [Sep]]
		set cur $root
		set found 1
		foreach label $path {
			set i [FindEntry $cur $label]
			if {$i < 0 || [$cur type $i] ne "cascade"} { set found 0; break }
			set sub ""
			catch { set sub [$cur entrycget $i -menu] }
			if {$sub eq "" || ![winfo exists $sub]} { set found 0; break }
			set cur $sub
		}
		if {!$found} continue
		set command ""
		catch { set command [$cur cget -postcommand] }
		if {$command ne ""} { catch { uplevel #0 $command } }
		set kids {}
		if {[catch {$cur index end} last] == 0 && $last ne "" && $last ne "none"} {
			for {set i 0} {$i <= $last} {incr i} {
				if {[$cur type $i] eq "separator"} continue
				set text ""
				catch { set text [$cur entrycget $i -label] }
				set text [Norm $text]
				if {$text eq ""} continue
				lappend kids $text
				set child [concat $path [list $text]]
				set childKey [Key $child]
				if {![dict exists $Kids $childKey]} { dict set Kids $childKey {} }
				if {[$cur type $i] eq "cascade"} {
					dict set Dyn $childKey 1
					lappend queue $childKey
				}
			}
		}
		dict set Kids $key $kids
	}
}

proc ::mpaths::RestoreLang {} {
	variable SavedLang
	catch { destroy .mpathsMenu }
	if {[info exists SavedLang] && $SavedLang ne ""} {
		catch { ::menu::SwitchLanguage $SavedLang }
	}
	return
}

# ----------------------------------------------------------------------
# Resolution
# ----------------------------------------------------------------------
proc ::mpaths::IsProse {c} {
	if {$c eq ""} { return 1 }
	set first [string index $c 0]
	if {[string is alpha $first] && [string is lower $first]} { return 1 }
	if {[regexp {[,;]} $c]} { return 1 }
	if {[regexp -nocase {right-click|double-click|\bclick\b} $c]} { return 1 }
	if {[llength [split $c]] > 4} { return 1 }
	return 0
}

proc ::mpaths::Walk {start rest} {
	variable Kids

	set cur $start
	foreach c $rest {
		set k [Key $cur]
		set kids {}
		if {[dict exists $Kids $k]} { set kids [dict get $Kids $k] }
		if {[lsearch -exact $kids $c] >= 0} {
			lappend cur $c
			continue
		}
		if {[IsProse $c]} { continue }
		return 0
	}
	return 1
}

proc ::mpaths::WalkCid {cid cur rest} {
	variable CtxKids
	variable SurfaceCids

	set i 0
	while {$i < [llength $rest]} {
		set c [lindex $rest $i]
		set k [CtxKey $cid $cur]
		set kids {}
		if {[dict exists $CtxKids $k]} { set kids [dict get $CtxKids $k] }
		if {[lsearch -exact $kids $c] >= 0} {
			lappend cur $c
			incr i
			continue
		}
		if {[dict exists $SurfaceCids $c]} {
			return [WalkSurface $c [lrange $rest [expr {$i + 1}] end]]
		}
		if {[IsProse $c]} { incr i; continue }
		return 0
	}
	return 1
}

proc ::mpaths::WalkSurface {surface rest} {
	variable SurfaceCids

	set cids [dict get $SurfaceCids $surface]
	foreach cid $cids {
		if {[WalkCid $cid {} $rest]} { return 1 }
	}
	# A pane with no context menu is a terminal location.
	return [expr {[llength $rest] == 0 ? 1 : 0}]
}

# 1 = resolves, 0 = a known menu row with a stale tail, -1 = the first
# component is not a menu label anywhere at HEAD.
proc ::mpaths::Resolve {comps} {
	variable Top
	variable AllPaths
	variable SurfaceCids

	set c0 [lindex $comps 0]
	set rest [lrange $comps 1 end]
	if {$c0 eq "Main Menu"} {
		if {![llength $rest]} { return 1 }
		set t [lindex $rest 0]
		if {[lsearch -exact $Top $t] < 0} { return 0 }
		return [Walk [list $t] [lrange $rest 1 end]]
	}
	if {[lsearch -exact $Top $c0] >= 0} { return [Walk [list $c0] $rest] }
	if {[dict exists $SurfaceCids $c0]} { return [WalkSurface $c0 $rest] }
	set found 0
	foreach path $AllPaths {
		if {[llength $path] && [lindex $path end] eq $c0} {
			incr found
			if {[Walk $path $rest]} { return 1 }
		}
	}
	if {$found} { return 0 }
	return -1
}

# A leading prose phrase ("Searching: Main Menu", "search_games \"Database
# tab") hides the real root.  Use the longest known suffix.
proc ::mpaths::TrimRoot {comps} {
	variable Top
	variable AllLabels
	variable SurfaceCids

	set c0 [string map [list "\u0022" "" "'" ""] [lindex $comps 0]]
	set words [split $c0]
	for {set i 0} {$i < [llength $words]} {incr i} {
		set cand [join [lrange $words $i end]]
		if {$cand eq "Main Menu" || [lsearch -exact $Top $cand] >= 0
		 || [dict exists $SurfaceCids $cand] || [dict exists $AllLabels $cand]} {
			return [concat [list $cand] [lrange $comps 1 end]]
		}
	}
	return $comps
}

proc ::mpaths::Titleish {c} {
	set c [regsub {(\.\.\.)+$} $c ""]
	if {$c eq "" || [llength [split $c]] > 4} { return 0 }
	if {[regexp {[0-9]} $c]} { return 0 }
	set first [string index $c 0]
	return [expr {[string is alpha $first] && [string toupper $first] eq $first}]
}

proc ::mpaths::AllTitleish {comps} {
	foreach c $comps {
		if {![Titleish $c]} { return 0 }
	}
	return 1
}

proc ::mpaths::IsOsRoot {c} {
	variable OsRoots
	foreach root $OsRoots {
		if {[string match "$root*" $c]} { return 1 }
	}
	return 0
}

# ----------------------------------------------------------------------
# Sources
# ----------------------------------------------------------------------
proc ::mpaths::FilesFor {lang} {
	variable Root
	variable EnglishFiles

	set dir [file join $Root tcl help $lang]
	set files [lsort [concat \
		[glob -nocomplain -directory $dir *.txt] \
		[glob -nocomplain -directory $dir *.html]]]
	lappend files [file join $Root tcl lang [dict get [Languages] $lang]]
	if {$lang eq "en"} {
		foreach name $EnglishFiles {
			lappend files [file join $Root tcl $name]
		}
	}
	return $files
}

proc ::mpaths::Analyze {lang} {
	set bad {}
	foreach file [FilesFor $lang] {
		set markup [expr {[file extension $file] in {.txt .html}}]
		set text [ReadText $file]
		if {$markup} { set text [Markup $text] }
		set text [Unescape $text]
		foreach item [Chains $text [expr {!$markup}]] {
			lassign $item line comps
			set norm {}
			foreach c $comps { lappend norm [Norm $c] }
			set comps [TrimRoot $norm]
			if {[llength $comps] < 2} continue
			if {[IsOsRoot [lindex $comps 0]]} continue
			set r [Resolve $comps]
			set where "[file tail $file]:$line"
			if {$r == 1} continue
			if {$r == 0} {
				lappend bad "$where: [join $comps { > }]"
			} elseif {[AllTitleish $comps]} {
				lappend bad "$where: unknown menu root: [join $comps { > }]"
			}
		}
	}
	return $bad
}

proc ::mpaths::Check {lang} {
	set rc [catch {
		BuildLang $lang
		Analyze $lang
	} result]
	RestoreLang
	if {$rc} { return -code error $result }
	return $result
}

proc ::mpaths::Resolves {lang chain} {
	set comps {}
	foreach c [split $chain >] { lappend comps [Norm [string trim $c]] }
	set rc [catch {
		BuildLang $lang
		set r [Resolve $comps]
	} result]
	RestoreLang
	if {$rc} { return -code error $result }
	return [expr {$r == 1}]
}

# ----------------------------------------------------------------------
# The removed Extras catch-all
# ----------------------------------------------------------------------
proc ::mpaths::ExtrasAllowed {line} {
	if {[string match {set Extras*} [string trimleft $line]]} { return 1 }
	if {[string match {::menu::mc::Extras*} [string trimleft $line]]} { return 1 }
	if {[string match {*RegisterExtras*} $line]} { return 1 }
	if {[string match {*SelectExtra*} $line] || [string match {*DuplicateExtras*} $line]} { return 1 }
	return 0
}

proc ::mpaths::ExtrasFiles {} {
	variable Root
	return [lsort [::mpaths::ProductFiles [file join $Root tcl]]]
}

proc ::mpaths::ProductFiles {dir} {
	set files {}
	foreach path [glob -nocomplain -directory $dir -types f *] {
		if {[file extension $path] in {.tcl .txt .html}} { lappend files $path }
	}
	foreach path [glob -nocomplain -directory $dir -types d *] {
		lappend files {*}[::mpaths::ProductFiles $path]
	}
	return $files
}

proc ::mpaths::ExtrasBad {} {
	set bad {}
	foreach file [ExtrasFiles] {
		set commentAware [expr {[file extension $file] eq ".tcl"}]
		set text [ReadText $file]
		set lineNo 0
		foreach line [split $text \n] {
			incr lineNo
			if {$commentAware && [string index [string trimleft $line] 0] eq "#"} continue
			if {[ExtrasAllowed $line]} continue
			if {[string first {Extras} $line] >= 0} {
				lappend bad "[file tail $file]:$lineNo"
			}
		}
	}
	return $bad
}

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------
foreach lang [lsort [dict keys [::mpaths::Languages]]] {
	tcltest::test menu-paths-$lang [format {every menu path in the %s help and catalog resolves} $lang] -body [list ::mpaths::Check $lang] -result {}
}

tcltest::test menu-paths-stale {the paths the reseal removed no longer resolve} -body {
	set bad {}
	foreach {lang chain} {
		en {Main Menu > Setup > Engines}
		en {Main Menu > Setup > Keyboard Preferences}
		en {Main Menu > Search}
		en {Preferences > Assistant}
		en {Maintenance > Advanced Search}
		en {Maintenance > Pattern Search}
		en {Maintenance > Mark As > Openings}
		en {Database > Maintenance > Repertoire Type > Openings}
		en {File > Open > HTML documents}
		de {Main Menu > Einstellungen > Motoren (Schachprogramme)}
		de {Einstellungen > Assistent}
		es {Main Menu > Configurar > Motores}
		es {Preferencias > Asistente}
		hu {Main Menu > Beállítások > Elemző modulok}
		it {Main Menu > Imposta > Motori}
		it {Preferenze > Assistente}
		sv {Inställningar > Assistent}
	} {
		if {![::mpaths::Resolves $lang $chain]} continue
		lappend bad "$lang: $chain"
	}
	set bad
} -result {}

tcltest::test menu-paths-current {the replacement paths resolve in every language} -body {
	set bad {}
	foreach {lang chain} {
		en {Edit > Preferences > Engines}
		en {Edit > Keyboard Preferences}
		en {Database > Search > Advanced}
		en {Database > Search > Query Editor}
		en {Database > Maintenance > Change Icon}
		en {Tools > Choose Model}
		en {Tools > Assistant}
		en {Training > Play Against Engine}
		en {Database > Player Data > Update Rating Data}
		en {File > Open Database}
		de {Bearbeiten > Einstellungen > Motoren (Schachprogramme)}
		de {Bearbeiten > Tastaturbelegung}
		de {Datenbank > Suchen}
		es {Editar > Preferencias > Motores}
		es {Editar > Preferencias de teclado}
		es {Base > Buscar}
		hu {Szerkeszt > Beállítások > Elemző modulok}
		hu {Szerkeszt > Billentyűzet-beállítások}
		hu {Adatbázis > Keresés}
		it {Modifica > Preferenze > Motori}
		it {Modifica > Preferenze tastiera}
		it {Banca dati > Cerca}
		sv {Verktyg > Assistent}
	} {
		if {[::mpaths::Resolves $lang $chain]} continue
		lappend bad "$lang: $chain"
	}
	set bad
} -result {}

tcltest::test menu-paths-dynamic {dynamic cascades are checked down to the children the product posts} -body {
	set bad {}
	# Rows the product generates at runtime: the cascade exists and its real
	# children resolve.
	foreach {lang chain} {
		en {View > Icon Size}
		en {View > Icon Size > Small}
		en {Database > Maintenance > Repertoire Type}
		sv {Visa > Ikonstorlek > Liten}
	} {
		if {[::mpaths::Resolves $lang $chain]} continue
		lappend bad "missing: $lang: $chain"
	}
	# A value the product does not post under that cascade is not a menu path,
	# and an empty cascade has no children to name.
	foreach {lang chain} {
		en {View > Icon Size > Huge}
		en {Database > Maintenance > Repertoire Type > Openings}
	} {
		if {![::mpaths::Resolves $lang $chain]} continue
		lappend bad "still resolves: $lang: $chain"
	}
	set bad
} -result {}

tcltest::test menu-paths-context {context-menu paths resolve, and the removed rows do not} -body {
	set bad {}
	foreach chain {
		{Board tab > right-click the board > Set Start Board}
		{Database tab > right-click the database > Maintenance > Compact database}
		{Players tab > right-click the player > Show Player Card}
		{Analysis pane > right-click a line > Add Move}
	} {
		if {![::mpaths::Resolves en $chain]} { lappend bad "missing: $chain" }
	}
	foreach chain {
		{Database tab > right-click the database > Maintenance > Advanced Search}
		{Database tab > right-click it > Maintenance > Mark As > Openings}
		{Board tab > right-click the board > Append move}
	} {
		if {[::mpaths::Resolves en $chain]} { lappend bad "still resolves: $chain" }
	}
	set bad
} -result {}

tcltest::test menu-no-removed-extras-string {no product string or help page names the removed Extras menu} -body {
	::mpaths::ExtrasBad
} -result {}

tcltest::test menu-replacement-paths {rating updates and the 3D board name their real current route} -body {
	set bad {}
	set card [file join $::mpaths::Root tcl player-card.tcl]
	set ch [open $card rb]; set cardText [read $ch]; close $ch
	if {[string first {Database > Player Data > Update Rating Data} $cardText] < 0} {
		lappend bad player-rating
	}
	foreach lang {en de es hu it} {
		foreach ext {txt html} {
			set file [file join $::mpaths::Root tcl help $lang Welcome.$ext]
			set text [::mpaths::ReadText $file]
			set text [::mpaths::Unescape [::mpaths::Markup $text]]
			if {[string first {Open 3D Board} $text] < 0} { lappend bad 3d-$lang-$ext }
		}
	}
	set bad
} -result {}

::tcltest::cleanupTests
