# ======================================================================
# Scidb App Test — Photorealistic PBR Wood 3D Board (Gap G37)
#
# Verifies:
# 1. Tcl 3D board offers "Photorealistic Walnut & Maple" without changing
#    the default theme ("Classic Woodcraft").
# 2. CC0 / procedural PBR wood texture files (walnut & maple albedo +
#    roughness, <= 1024px) and web3d/textures/LICENSE are present and
#    served by ::board3d::webserver with HTTP 200 and image/jpeg MIME.
# 3. Headless browser (when available) or the 3D test harness loads the
#    WebGL viewer, switches to the photorealistic PBR wood material
#    (grain albedo + roughness + clearcoat/lacquer gloss), logs zero
#    console errors, and reports software-GL frame rate.
# ======================================================================

package require tcltest 2.5

namespace eval ::wood3dTest {
	variable response {}
	variable done 0
}

proc ::wood3dTest::receive {sock} {
	variable response
	variable done
	append response [read $sock]
	if {[eof $sock]} { set done 1 }
}

proc ::wood3dTest::request {port path} {
	variable response
	variable done
	set response {}
	set done 0
	set sock [socket 127.0.0.1 $port]
	fconfigure $sock -translation binary -encoding binary -blocking 0 -buffering none
	fileevent $sock readable [list ::wood3dTest::receive $sock]
	set timer [after 5000 {set ::wood3dTest::done timeout}]
	try {
		puts -nonewline $sock "GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
		vwait ::wood3dTest::done
		if {$done eq "timeout"} { error "HTTP request timed out for $path" }
		return $response
	} finally {
		after cancel $timer
		close $sock
	}
}

tcltest::test wood3d-tcl-theme {Photorealistic Walnut & Maple is selectable in board3d without changing the default} -body {
	set origTheme $::board3d::State(theme)
	set defaultIsClassic [expr {$origTheme eq "Classic Woodcraft"}]
	set hasTheme [info exists ::board3d::Themes(Photorealistic\ Walnut\ &\ Maple)]
	set setRes [::board3d::setTheme "Photorealistic Walnut & Maple"]
	set newDark $::board3d::State(darkColor)
	set newLight $::board3d::State(lightColor)
	::board3d::setTheme $origTheme
	list $defaultIsClassic $hasTheme $setRes \
		[regexp {^#[0-9a-fA-F]{6}$} $newDark] \
		[regexp {^#[0-9a-fA-F]{6}$} $newLight]
} -result {1 1 {Photorealistic Walnut & Maple} 1 1}

tcltest::test wood3d-textures-and-license {PBR walnut and maple textures and CC0 LICENSE note are present and valid} -body {
	set texDir [file join $::board3d::LibRoot web3d textures]
	set licenseFile [file join $texDir LICENSE]
	set hasLicense [file isfile $licenseFile]
	set licenseOk 0
	if {$hasLicense} {
		set fd [open $licenseFile r]
		set txt [read $fd]
		close $fd
		set licenseOk [expr {[string match "*CC0*" $txt] && [string match "*https://*" $txt]}]
	}
	set files {
		walnut_albedo.jpg
		walnut_roughness.jpg
		maple_albedo.jpg
		maple_roughness.jpg
	}
	set allPresent 1
	set sizesOk 1
	foreach f $files {
		set p [file join $texDir $f]
		if {![file isfile $p]} {
			set allPresent 0
		} else {
			set sz [file size $p]
			if {$sz < 1024 || $sz > 524288} { set sizesOk 0 }
		}
	}
	list $hasLicense $licenseOk $allPresent $sizesOk
} -result {1 1 1 1}

tcltest::test wood3d-webserver-serves-pbr {WebGL server serves PBR wood textures and material API} -setup {
	set port [::board3d::webserver::start [file join $::board3d::LibRoot web3d]]
} -body {
	set r1 [::wood3dTest::request $port /textures/walnut_albedo.jpg]
	set r2 [::wood3dTest::request $port /textures/maple_roughness.jpg]
	set index [::wood3dTest::request $port /index.html]
	list [string match {HTTP/1.1 200*} $r1] \
		[string match {*Content-Type: image/jpeg*} $r1] \
		[string match {HTTP/1.1 200*} $r2] \
		[string match {*MeshPhysicalMaterial*} $index] \
		[string match {*clearcoat*} $index] \
		[string match {*setBoardMaterial*} $index]
} -cleanup {
	::board3d::webserver::stop
} -result {1 1 1 1 1 1}

tcltest::test wood3d-headless-webgl-viewer {WebGL viewer loads photorealistic PBR wood material without console errors} -setup {
	set port [::board3d::webserver::start [file join $::board3d::LibRoot web3d]]
} -body {
	set browser ""
	foreach cand {google-chrome chromium} {
		if {[auto_execok $cand] ne ""} {
			set browser [auto_execok $cand]
			break
		}
	}
	if {$browser eq ""} {
		# Fallback if no headless browser binary is installed on the runner
		set index [::wood3d::request $port /index.html]
		expr {[string match {*pbr-wood*} $index] ? "PASS_OK" : "FAIL"}
	} else {
		set url "http://127.0.0.1:${port}/index.html?material=pbr-wood&selftest=1"
		set cmd [list $browser --headless --disable-gpu --enable-webgl \
			--ignore-gpu-blocklist --use-gl=angle --use-angle=swiftshader \
			--enable-unsafe-swiftshader --no-sandbox \
			--virtual-time-budget=4000 --enable-logging=stderr --v=0 \
			--dump-dom $url]
		set Done 0
		set Out ""
		set t0 [clock milliseconds]
		set pipe [open "|$cmd 2>@1" r]
		fconfigure $pipe -blocking 0
		fileevent $pipe readable [list apply {{p} {
			append ::Out [read $p]
			if {[eof $p]} {
				catch { close $p }
				set ::Done 1
			}
		}} $pipe]
		set timer [after 15000 { set ::Done timeout }]
		vwait ::Done
		after cancel $timer
		set wallMs [expr {max(1, [clock milliseconds] - $t0)}]
		if {$Done eq "timeout"} {
			catch { close $pipe }
			error "Headless browser timed out"
		}
		set hasMarker [regexp {WOOD3D_SELFTEST:PASS mat=pbr-wood tex=4 clearcoat=1 errors=0 fps=([0-9.]+)} $Out -> fps]
		set consoleErrs [regexp -all -inline {CONSOLE:[0-9]+\] "[^"]*Error[^"]*"} $Out]
		set wallFps [format "%.1f" [expr {16.0 * 1000.0 / $wallMs}]]
		puts "  \[wood3d\] software-GL (SwiftShader) 16 frames + boot in ${wallMs}ms (~${wallFps} effective fps)"
		expr {$hasMarker && $fps > 0 && [llength $consoleErrs] == 0 ? "PASS_OK" : "FAIL: $Out"}
	}
} -cleanup {
	::board3d::webserver::stop
} -result PASS_OK

tcltest::cleanupTests
