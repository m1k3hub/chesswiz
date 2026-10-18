# Headless regression tests: source the real procedures without starting Tk.
package require tcltest 2.5
interp create mediaStreamTest
mediaStreamTest eval [list set testDir [file dirname [file normalize [info script]]]]
mediaStreamTest eval {
package require tcltest 2.5
namespace eval ::application::media::mc {}
namespace eval ::media::mpv {
    proc _get {property} { return "loading failed" }
}
set streamSource [open [file join $testDir .. tcl app-media.tcl]]
set command {}
while {[gets $streamSource line] >= 0} {
    append command $line \n
    if {![info complete $command]} { continue }
    if {[regexp {^proc application::media::(isStreamUrl|StreamNeedsYtdlp|StreamFailure|CheckStream|PlayStream|UsesOsMedia|VlcRegistry|ExternalStreamPlayer|OpenStreamExternal) } [string trimleft $command]]} {
        eval $command
    } elseif {[regexp {^set (StreamFailed|StreamWaiting)\s} [string trimleft $command]]} {
        namespace eval ::application::media::mc $command
    }
    set command {}
}
close $streamSource

# Top-level namespaces form a single command in app-media.tcl; load the
# message's actual assignment independently of that enclosing namespace.
set streamSource [open [file join $testDir .. tcl app-media.tcl]]
while {[gets $streamSource line] >= 0} {
    if {[regexp {^set (StreamFailed|StreamWaiting)\s} $line]} {
        namespace eval ::application::media::mc $line
    }
}
close $streamSource

tcltest::test stream-host-classification {only real YouTube/Twitch authorities get the helper hint} -body {
    lmap url {
        https://youtube.com/watch?v=abc https://www.youtube.com/watch?v=abc
        https://youtu.be/abc https://clips.twitch.tv/abc HTTPS://WWW.TWITCH.TV:443/a
        https://youtube.com.evil.test/a https://notyoutube.com/a
        https://evil.test/youtube.com https://youtube.com@evil.test/a
        https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
        https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4
    } { ::application::media::StreamNeedsYtdlp $url }
} -result {1 1 1 1 1 0 0 0 0 0 0}

tcltest::test stream-error-message {direct links show backend error without irrelevant helper advice} -body {
    set direct [::application::media::StreamFailure https://example.test/live.m3u8]
    set site [::application::media::StreamFailure https://youtu.be/abc]
    list [string match {*loading failed*} $direct] [string match {*yt-dlp*} $direct] \
        [string match {*loading failed*yt-dlp*} $site]
} -result {1 0 1}

tcltest::test stream-error-before-close {read the native error before player destruction} -setup {
    proc ::application::media::MediaState {} { return error }
    proc ::application::media::MediaDebug {args} {}
    proc ::application::media::MediaDestroy {} { set ::media::mpv::destroyed 1 }
    rename ::media::mpv::_get ::media::mpv::savedGet
    proc ::media::mpv::_get {property} {
        if {$::media::mpv::destroyed} { return {} }
        return "unrecognized file format"
    }
    set ::media::mpv::destroyed 0
    set ::application::media::Priv(inprocess) 1
    set ::application::media::Priv(stream) https://example.test/a.mp4
} -body {
    ::application::media::CheckStream https://example.test/a.mp4 0
    list $::media::mpv::destroyed $::application::media::Priv(statusbar)
} -cleanup {
    rename ::media::mpv::_get {}
    rename ::media::mpv::savedGet ::media::mpv::_get
    foreach name {MediaState MediaDebug MediaDestroy} { rename ::application::media::$name {} }
} -result {1 {The stream could not be played: https://example.test/a.mp4. unrecognized file format}}

tcltest::test os-stream-fallback {OS failure opens externally after destruction; Linux keeps its error} -setup {
    proc ::application::media::MediaState {} { return error }
    proc ::application::media::MediaDebug {args} {}
    proc ::application::media::MediaDestroy {} { set ::destroyed 1 }
    rename ::application::media::UsesOsMedia ::application::media::savedOs
    rename ::application::media::OpenStreamExternal ::application::media::savedExternal
    proc ::application::media::UsesOsMedia {} { return $::osBackend }
    proc ::application::media::OpenStreamExternal {url} {
        if {!$::destroyed} { error {player still alive} }
        set ::application::media::Priv(statusbar) {Opened in VLC}
        return 1
    }
} -body {
    set results {}
    foreach ::osBackend {1 0} {
        set ::destroyed 0
        set ::application::media::Priv(inprocess) 1
        set ::application::media::Priv(stream) https://example.test/a.mp4
        ::application::media::CheckStream https://example.test/a.mp4 0
        lappend results $::application::media::Priv(statusbar)
    }
    set results
} -cleanup {
    foreach name {MediaState MediaDebug MediaDestroy UsesOsMedia OpenStreamExternal} {
        rename ::application::media::$name {}
    }
    rename ::application::media::savedOs ::application::media::UsesOsMedia
    rename ::application::media::savedExternal ::application::media::OpenStreamExternal
} -result {{Opened in VLC} {The stream could not be played: https://example.test/a.mp4. loading failed}}

tcltest::test stream-error-logged {the backend's error code reaches the log even when VLC takes over} -setup {
    proc ::application::media::MediaState {} { return error }
    proc ::application::media::MediaDebug {msg} { lappend ::medialog $msg }
    proc ::application::media::MediaDestroy {} {}
    rename ::application::media::UsesOsMedia ::application::media::savedOs
    rename ::application::media::OpenStreamExternal ::application::media::savedExternal
    proc ::application::media::UsesOsMedia {} { return 1 }
    proc ::application::media::OpenStreamExternal {url} {
        set ::application::media::Priv(statusbar) {Opened in VLC}
        return 1
    }
    rename ::media::mpv::_get ::media::mpv::savedGet
    proc ::media::mpv::_get {property} {
        return {Media Foundation error 4 (source-not-supported; HRESULT 0x80070032).}
    }
    set ::application::media::Priv(inprocess) 1
    set ::application::media::Priv(stream) https://example.test/a.mp4
    set ::medialog {}
} -body {
    ::application::media::CheckStream https://example.test/a.mp4 0
    set logged [join $::medialog "\n"]
    list $::application::media::Priv(statusbar) \
        [string match {*error 4*source-not-supported*} $logged] \
        [string match {*giving up*https://example.test/a.mp4*} $logged]
} -cleanup {
    foreach name {MediaState MediaDebug MediaDestroy UsesOsMedia OpenStreamExternal} {
        rename ::application::media::$name {}
    }
    rename ::application::media::savedOs ::application::media::UsesOsMedia
    rename ::application::media::savedExternal ::application::media::OpenStreamExternal
    rename ::media::mpv::_get {}
    rename ::media::mpv::savedGet ::media::mpv::_get
} -result {{Opened in VLC} 1 1}

namespace eval ::media::sync {
    proc load-timeline {args} {}
    proc load-events {args} {}
}
tcltest::test os-stream-routing {hosting sites bypass OS playback; direct links fall back only on failure} -setup {
    rename ::application::media::UsesOsMedia ::application::media::savedOs
    rename ::application::media::OpenStreamExternal ::application::media::savedExternal
    proc ::application::media::UsesOsMedia {} { return 1 }
    proc ::application::media::OpenStreamExternal {url} { incr ::external; return 1 }
    proc ::application::media::PlayInProcess {args} { incr ::internal; return $::accepted }
    set ::application::media::StreamOptions(recent) {}
} -body {
    set results {}
    foreach {url ::accepted} {
        https://www.youtube.com/watch?v=abc 1
        https://example.test/live.m3u8 1
        https://example.test/video.mp4 0
    } {
        set ::internal 0
        set ::external 0
        set ok [::application::media::PlayStream $url]
        lappend results [list $ok $::internal $::external]
        catch {after cancel $::application::media::Priv(checkid)}
    }
    set results
} -cleanup {
    foreach name {UsesOsMedia OpenStreamExternal PlayInProcess} {
        rename ::application::media::$name {}
    }
    rename ::application::media::savedOs ::application::media::UsesOsMedia
    rename ::application::media::savedExternal ::application::media::OpenStreamExternal
} -result {{1 0 1} {1 1 0} {1 1 1}}

# Exercise the transport with a fake native command: no process or network.
namespace eval ::util { proc source {args} {} }
source [file join $testDir .. tcl app-media-mpv.tcl]
namespace eval ::mpv {
    proc open {args} { set ::opened $args; return 1 }
    proc get {property} { return {} }
}
tcltest::test stream-launch-verbatim {direct HTTPS links reach native playback unchanged} -body {
    set url {https://example.test/a.mp4?one=1&two=hello%20world}
    set ok [::media::mpv::launch $url 42 0]
    list $ok [expr {[lindex $::opened 1] eq $url}] [lindex $::opened 0]
} -result {1 1 42}

tcltest::test stream-launch-error {native command errors remain available for the status message} -setup {
    rename ::mpv::open ::mpv::savedOpen
    proc ::mpv::open {args} { error "native initialization failed" }
} -body {
    list [::media::mpv::launch https://example.test/a.mp4 42] \
        [::application::media::StreamFailure https://example.test/a.mp4]
} -cleanup {
    rename ::mpv::open {}
    rename ::mpv::savedOpen ::mpv::open
} -result {0 {The stream could not be played: https://example.test/a.mp4. native initialization failed}}

# Installed-player lookup and launches are stubbed: no network or subprocesses.
proc fakeExists {path} { expr {$path in $::installed} }
proc fakeRegistry {key} { return {C:/Custom VLC} }
tcltest::test external-selection {registry, Program Files, macOS and missing VLC} -setup {
    set savedEnv [array get ::env]
    set ::env(ProgramFiles) {C:/Program Files}
    rename auto_execok savedAutoExecok
    proc auto_execok {args} { return {} }
} -body {
    set ::installed {{C:/Custom VLC/vlc.exe}}
    set a [::application::media::ExternalStreamPlayer {Windows NT} fakeExists fakeRegistry]
    set ::installed {{C:/Program Files/VideoLAN/VLC/vlc.exe}}
    set b [::application::media::ExternalStreamPlayer {Windows NT} fakeExists fakeRegistry]
    set ::installed {/Applications/VLC.app/Contents/MacOS/VLC}
    set c [::application::media::ExternalStreamPlayer Darwin fakeExists fakeRegistry]
    set ::installed {}
    list $a $b $c [::application::media::ExternalStreamPlayer Darwin fakeExists fakeRegistry]
} -cleanup {
    array unset ::env
    array set ::env $savedEnv
    rename auto_execok {}
    rename savedAutoExecok auto_execok
} -result {{{C:/Custom VLC/vlc.exe}} {{C:/Program Files/VideoLAN/VLC/vlc.exe}} {/usr/bin/open -a VLC} {}}

namespace eval ::platform::sys { proc openURL {url} { set ::browser $url } }
tcltest::test external-message {VLC launch, failed VLC and browser failure} -setup {
    rename ::application::media::ExternalStreamPlayer ::application::media::savedPlayer
    proc ::application::media::ExternalStreamPlayer {args} { return {{C:/VLC/vlc.exe}} }
    rename exec savedExec
    proc exec {args} { set ::launch $args; if {$::failExec} { error failed } }
} -body {
    set url {https://example.test/a?x=1&y=two%20words}
    set ::failExec 0
    set a [::application::media::OpenStreamExternal $url]
    set first $::application::media::Priv(statusbar)
    set ::failExec 1
    set b [::application::media::OpenStreamExternal $url]
    list $a $first [lindex $::launch 1] $b $::application::media::Priv(statusbar) $::browser
} -cleanup {
    rename exec {}
    rename savedExec exec
    rename ::application::media::ExternalStreamPlayer {}
    rename ::application::media::savedPlayer ::application::media::ExternalStreamPlayer
} -result {1 {Opened in VLC} https://example.test/a?x=1&y=two%20words 1 {Opened in your browser} https://example.test/a?x=1&y=two%20words}

tcltest::test external-unavailable {failed browser launch does not report success} -setup {
    rename ::application::media::ExternalStreamPlayer ::application::media::savedPlayer
    proc ::application::media::ExternalStreamPlayer {args} { return {} }
    rename ::platform::sys::openURL ::platform::sys::savedOpen
    proc ::platform::sys::openURL {args} { error unavailable }
} -body {
    ::application::media::OpenStreamExternal https://example.test/live.m3u8
} -cleanup {
    rename ::application::media::ExternalStreamPlayer {}
    rename ::application::media::savedPlayer ::application::media::ExternalStreamPlayer
    rename ::platform::sys::openURL {}
    rename ::platform::sys::savedOpen ::platform::sys::openURL
} -result 0

tcltest::cleanupTests
}
interp delete mediaStreamTest
