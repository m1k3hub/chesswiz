# ======================================================================
# Scidb App Test - Roadmap P11 Dark UI Theme
#
# Verifies:
#   1. The "dark" ttk theme is registered and selectable in the
#      Settings > View > Theme menu (::menu::FillTheme / ::menu::Theme).
#   2. Applying the dark theme sets dark backgrounds and light foregrounds
#      across ttk styles, the Tk option database for classic widgets,
#      semantic ::colors::lookup keys (pgn, table, treectrl, gamebar,
#      switcher, analysis, tree, html, etc.), and live widgets in the main
#      window, game list, and dialogs with sufficient contrast (no
#      dark-on-dark text).
#   3. Picking "dark" in Settings > View > Theme persists to options and
#      restores the dark theme on a fresh application restart.
# ======================================================================
package require tcltest 2.5

namespace eval ::darkThemeTest {
	variable root [file dirname $::scidb::test::app::testDir]
	variable phase [file join $::scidb::test::app::testDir fixtures theme-restart phase.tcl]
}

proc ::darkThemeTest::luminance {w color} {
	if {$color eq ""} { return -1.0 }
	if {[catch {winfo rgb $w $color} rgb]} { return -1.0 }
	lassign $rgb r g b
	set rf [expr {$r / 65535.0}]
	set gf [expr {$g / 65535.0}]
	set bf [expr {$b / 65535.0}]
	return [expr {0.2126 * $rf + 0.7152 * $gf + 0.0722 * $bf}]
}

proc ::darkThemeTest::runPhase {home which theme} {
	set limit {timeout 180}
	if {[tk windowingsystem] eq "aqua"} {
		set limit {perl -e {alarm shift; exec @ARGV} 180}
	}
	catch {
		::util::execSafe {*}$limit env \
			HOME=$home \
			TH_ROOT=$::darkThemeTest::root \
			TH_PHASE=$which \
			TH_THEME=$theme \
			[info nameofexecutable] $::darkThemeTest::phase 2>@1
	} output
	return $output
}

proc ::darkThemeTest::tempHome {} {
	set home [file join $::scidb::test::app::testDir tmp-app roadmap-partial dark dark-theme-restart-[pid]]
	file delete -force $home
	file mkdir $home
	return $home
}

tcltest::test dark-theme-registered-and-menu {dark theme is registered in ttk and selectable in Theme menu} -setup {
	set testMenu [menu .darkThemeTestMenu -tearoff 0]
} -body {
	set inTtk [expr {"dark" in [ttk::style theme names]}]
	::menu::FillTheme $testMenu
	set end [$testMenu index end]
	set foundInMenu 0
	set varName ""
	if {$end ne "none"} {
		for {set i 0} {$i <= $end} {incr i} {
			if {[$testMenu type $i] eq "radiobutton"} {
				if {[$testMenu entrycget $i -value] eq "dark"} {
					set foundInMenu 1
					set varName [$testMenu entrycget $i -variable]
					break
				}
			}
		}
	}
	list $inTtk $foundInMenu $varName
} -cleanup {
	destroy $testMenu
} -result {1 1 ::menu::Theme}

tcltest::test dark-theme-apply-and-contrast {dark theme sets dark palette, classic options, semantic colors, and live widget contrast} -setup {
	set prevTheme [::theme::currentTheme]
} -body {
	set ::menu::Theme dark
	::theme::setTheme dark
	update

	set failures {}

	if {[::theme::currentTheme] ne "dark"} {
		lappend failures "currentTheme=[::theme::currentTheme]"
	}
	if {![::theme::isDark]} {
		lappend failures "isDark=0"
	}

	# 1. Check Ttk styles have dark background and light foreground
	foreach style {. TButton TEntry TCombobox TSpinbox TNotebook.Tab Heading Treeview} {
		set bg [ttk::style lookup $style -background]
		if {$style in {TEntry TCombobox TSpinbox Treeview}} {
			set fbg [ttk::style lookup $style -fieldbackground]
			if {$fbg ne ""} { set bg $fbg }
		}
		set fg [ttk::style lookup $style -foreground]
		set bgL [::darkThemeTest::luminance . $bg]
		set fgL [::darkThemeTest::luminance . $fg]
		if {$bgL < 0.0 || $bgL > 0.25} {
			lappend failures "ttk-bg:$style=$bg/$bgL"
		}
		if {$fgL < 0.65} {
			lappend failures "ttk-fg:$style=$fg/$fgL"
		}
		if {($fgL - $bgL) < 0.45} {
			lappend failures "ttk-contrast:$style=$bgL/$fgL"
		}
	}

	# 2. Check newly created classic Tk widgets inherit dark palette from option database
	foreach spec {
		{frame .darkProbeFrame Frame 0}
		{label .darkProbeLabel Label 1}
		{button .darkProbeButton Button 1}
		{radiobutton .darkProbeRadio Radiobutton 1}
		{checkbutton .darkProbeCheck Checkbutton 1}
		{menubutton .darkProbeMenubutton Menubutton 1}
		{menu .darkProbeMenu Menu 1}
		{entry .darkProbeEntry Entry 1}
		{spinbox .darkProbeSpinbox Spinbox 1}
		{listbox .darkProbeListbox Listbox 1}
		{text .darkProbeText Text 1}
		{canvas .darkProbeCanvas Canvas 0}
	} {
		lassign $spec cmd w cls hasFg
		$cmd $w
		set bg [$w cget -background]
		set bgL [::darkThemeTest::luminance $w $bg]
		if {$bgL < 0.0 || $bgL > 0.25} {
			lappend failures "opt-bg:$cls=$bg/$bgL"
		}
		if {$hasFg} {
			set fg [$w cget -foreground]
			set fgL [::darkThemeTest::luminance $w $fg]
			if {$fgL < 0.65} {
				lappend failures "opt-fg:$cls=$fg/$fgL"
			}
			if {($fgL - $bgL) < 0.45} {
				lappend failures "opt-contrast:$cls=$bgL/$fgL"
			}
		}
		destroy $w
	}

	# 3. Check semantic colors via ::colors::lookup for contrast (no dark-on-dark)
	foreach pair {
		{pgn,background pgn,foreground:main}
		{pgn,background pgn,foreground:variation}
		{pgn,background pgn,foreground:comment}
		{pgn,background pgn,foreground:nag}
		{pgn,background pgn,foreground:marks}
		{pgn,background pgn,foreground:nagtext}
		{table,background table,foreground}
		{table,stripes table,foreground}
		{tlistbox,background tlistbox,foreground}
		{treetable,background treetable,foreground}
		{gamebar,background:normal gamebar,foreground:normal}
		{gamebar,background:selected gamebar,foreground:normal}
		{switcher,normal:background switcher,normal:foreground}
		{switcher,selected:background switcher,normal:foreground}
		{analysis,background analysis,info:foreground}
		{tree,background darkblue}
		{tree,background darkgreen}
		{tree,background darkred}
		{help,background:gray help,foreground:litegray}
	} {
		lassign $pair bgKey fgKey
		set bg [::colors::lookup $bgKey]
		set fg [::colors::lookup $fgKey]
		set bgL [::darkThemeTest::luminance . $bg]
		set fgL [::darkThemeTest::luminance . $fg]
		if {$bgL < 0.0 || $bgL > 0.30} {
			lappend failures "color-bg:$bgKey=$bg/$bgL"
		}
		if {$fgL < 0.35} {
			lappend failures "color-fg:$fgKey=$fg/$fgL"
		}
		if {($fgL - $bgL) < 0.20} {
			lappend failures "color-contrast:$bgKey/$fgKey=$bgL/$fgL"
		}
	}

	# 4. Open a classic dialog (About dialog) and inspect live widget tree for dark-on-dark text
	::info::openDialog .application
	update
	if {![winfo exists .application.infoDialog]} {
		lappend failures "infoDialog-not-opened"
	} else {
		set dlgBg [.application.infoDialog cget -background]
		set dlgBgL [::darkThemeTest::luminance . $dlgBg]
		if {$dlgBgL < 0.0 || $dlgBgL > 0.25} {
			lappend failures "dialog-bg:$dlgBg/$dlgBgL"
		}
	}

	# Walk live widgets in .application and .application.infoDialog
	set stack [list .application]
	while {[llength $stack] > 0} {
		set w [lindex $stack end]
		set stack [lrange $stack 0 end-1]
		if {![winfo exists $w]} continue
		foreach child [winfo children $w] {
			lappend stack $child
		}
		set cls [winfo class $w]
		if {$cls in {Text Listbox Entry Spinbox Menu Message TreeCtrl}} {
			if {![catch {$w cget -background} bg] && ![catch {$w cget -foreground} fg]} {
				if {$bg ne "" && $fg ne ""} {
					set bgL [::darkThemeTest::luminance $w $bg]
					set fgL [::darkThemeTest::luminance $w $fg]
					if {$bgL > 0.50} {
						lappend failures "live-light-bg:$w/$cls=$bg/$bgL"
					}
					if {$fgL >= 0.0 && $bgL >= 0.0 && ($fgL - $bgL) < 0.25} {
						lappend failures "live-dark-on-dark:$w/$cls=$bg/$bgL/$fg/$fgL"
					}
				}
			}
		}
	}

	if {[winfo exists .application.infoDialog]} {
		destroy .application.infoDialog
		update
	}

	return $failures
} -cleanup {
	if {[winfo exists .application.infoDialog]} {
		destroy .application.infoDialog
	}
	set ::menu::Theme $prevTheme
	::theme::setTheme $prevTheme
	update
} -result {}

tcltest::test dark-theme-dialog-pane-roundtrip {light colours survive dialog and pane churn before a runtime round trip} -setup {
	set previous [::theme::currentTheme]
	set originalPanes [[::application::twm board] leaves]
	::theme::setTheme clam
	update
	menu .darkRoundtripMenu -tearoff 0
	entry .darkRoundtripEntry
	label .darkRoundtripLabel -background linen -foreground darkred
	set before [list [.darkRoundtripMenu configure] [.darkRoundtripEntry configure] [.darkRoundtripLabel configure]]
} -body {
	foreach uid {editor tree games} {
		set pane [::application::openPane $uid]
		update
		if {$pane eq ""} { error "failed to open $uid" }
		set twm [::application::twm board]
		$twm close $pane
		update
	}
	foreach unused {1 2 3} {
		::info::openDialog .application
		update
		destroy .application.infoDialog
		update
	}
	::theme::setTheme dark
	update
	# Destroy a widget with queued theme events, then reuse its path.
	label .darkDestroyedProbe
	destroy .darkDestroyedProbe
	::theme::setTheme clam
	update
	label .darkDestroyedProbe
	menu .darkFreshMenu -tearoff 0
	entry .darkFreshEntry
	set after [list [.darkRoundtripMenu configure] [.darkRoundtripEntry configure] [.darkRoundtripLabel configure]]
	list [expr {$before eq $after}] \
		[expr {[.darkFreshMenu cget -activebackground] eq [.darkRoundtripMenu cget -activebackground]}] \
		[expr {[.darkFreshEntry cget -background] eq [.darkRoundtripEntry cget -background]}]
} -cleanup {
	foreach w {.darkRoundtripMenu .darkRoundtripEntry .darkRoundtripLabel .darkDestroyedProbe .darkFreshMenu .darkFreshEntry .application.infoDialog} {
		catch {destroy $w}
	}
	foreach uid {editor tree games} {
		if {$uid in $originalPanes} { ::application::openPane $uid }
	}
	::theme::setTheme $previous
	update
} -result {1 1 1}

tcltest::test dark-theme-persist-restart {picking dark in Settings > Theme persists and restores on restart} -setup {
	set home [::darkThemeTest::tempHome]
} -body {
	set picked [::darkThemeTest::runPhase $home set dark]
	set started [::darkThemeTest::runPhase $home get dark]
	list \
		[regexp {THEME picked dark dark} $picked] \
		[regexp {THEME start dark dark dark} $started]
} -cleanup {
	file delete -force $home
} -result {1 1}

tcltest::cleanupTests
