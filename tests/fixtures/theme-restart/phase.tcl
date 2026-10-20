# ======================================================================
# Theme persistence phases: one fresh app process per phase, so that the
# real startup and the real shutdown paths run (G21). The parent test
# (tests/test_app_theme_persist.tcl) reads the lines prefixed "THEME".
#
#   phase set         pick TH_THEME in the Settings > Theme menu and quit
#                     through ::application::shutdown, the path the close
#                     button takes, which saves the options file.
#   phase get         report the theme the fresh start came up with.
#   phase seed-stale  save TH_THEME as the chosen theme without applying
#                     it, as an older configuration or another platform
#                     would have left it.
#
# Environment: TH_PHASE, TH_ROOT (repository root), TH_THEME.
# ======================================================================

set argv {--single-process}
set argc 1
set root $::env(TH_ROOT)
source -encoding utf-8 [file join $root tcl chesswiz]
set ::scidb::dir::setup 0

proc themeOut {args} { puts "THEME [join $args { }]"; flush stdout }

proc themeRadio {menu theme} {
	for {set i 0} {$i <= [$menu index end]} {incr i} {
		if {[$menu type $i] eq "radiobutton" && [$menu entrycget $i -value] eq $theme} {
			return $i
		}
	}
	return -1
}

proc themeCascade {menu label} {
	for {set i 0} {$i <= [$menu index end]} {incr i} {
		if {[$menu type $i] eq "cascade"
			&& [string trim [$menu entrycget $i -label]] eq $label} {
			return [$menu entrycget $i -menu]
		}
	}
	return ""
}

after 2500 {
	switch -- $::env(TH_PHASE) {
		set {
			set mb .application.nb.menu_main
			::application::BuildSettingsMenu $mb
			# Decision 003: the drop-down is the settings menu; View fills
			# lazily and Theme is one of its dynamic cascades.
			::menu::FillTop View $mb.entries.view
			set m [themeCascade $mb.entries.view [::menu::MC Theme]]
			::menu::FillDynamic Theme $m
			set idx [themeRadio $m $::env(TH_THEME)]
			themeOut found $idx
			if {$idx >= 0} { $m invoke $idx }
			themeOut picked [::theme::currentTheme] $::menu::Theme
			# the user's Quit: same save path as the close button
			::application::shutdown
		}
		seed-stale {
			set ::menu::Theme $::env(TH_THEME)
			::options::startTransaction
			::options::saveOptionsFile
			::options::endTransaction
			themeOut seeded $::env(TH_THEME) [file exists $::scidb::file::options]
			exit 0
		}
		get {
			themeOut start [::theme::currentTheme] $::menu::Theme [ttk::style theme use]
			exit 0
		}
	}
}

after 60000 { themeOut timeout; exit 2 }
