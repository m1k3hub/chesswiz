# Never open PDFs, pages or media on the user's desktop during test runs:
# desktop openers become no-ops that log what they would have opened.
# Set CHESSWIZ_TEST_REAL_OPEN=1 to opt out. Source before tcl/chesswiz.
if {$::tcl_platform(platform) eq "unix" && ![info exists ::env(CHESSWIZ_TEST_REAL_OPEN)]} {
	set stubDir [file join [file dirname [file normalize [info script]]] tmp-app no-open-[pid]]
	file mkdir $stubDir
	set ::env(CHESSWIZ_TEST_OPEN_LOG) [file join $stubDir opened.log]
	foreach opener {xdg-open open gio gnome-open kde-open sensible-browser x-www-browser papers evince okular} {
		set f [open [file join $stubDir $opener] w]
		puts $f "#!/bin/sh\necho \"$opener \$*\" >> \"\$CHESSWIZ_TEST_OPEN_LOG\"\nexit 0"
		close $f
		file attributes [file join $stubDir $opener] -permissions 0755
	}
	set ::env(PATH) "$stubDir:$::env(PATH)"
	unset stubDir
}
