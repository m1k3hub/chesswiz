# ======================================================================
# Scidb App Test - live streams and video links in the media panel
# ======================================================================
# The player is stubbed (no network, no libmpv); a live check against a
# real HLS stream was run by hand (2026-10-17: playing, nvdec-copy).
# ======================================================================
package require tcltest 2.5

tcltest::test stream-url {which links are streams} -body {
	lmap u {https://www.youtube.com/watch?v=abc https://x.test/live.m3u8 rtmp://a.b/live/key rtsp://cam/1
		srt://h:9000 http://127.0.0.1:8817/a.mp4 /home/me/video.mp4 C:/x.wmv "https://a b" ftp://x/y} {
		::application::media::isStreamUrl $u
	}
} -result {1 1 1 1 1 1 0 0 0 0}

tcltest::test stream-play {a stream plays in process and is remembered first, without duplicates} -setup {
	rename ::application::media::PlayInProcess ::scidb::test::realPlayInProcess
	proc ::application::media::PlayInProcess {path {startMs {}} {endMs {}}} {
		set ::scidb::test::played $path
		set ::application::media::Priv(inprocess) 1
		return 1
	}
	set saved $::application::media::StreamOptions(recent)
	set ::application::media::StreamOptions(recent) {https://a.test/1.m3u8 https://b.test/2.m3u8}
} -body {
	set ok [::application::media::PlayStream https://b.test/2.m3u8]
	list $ok $::scidb::test::played $::application::media::StreamOptions(recent) \
		[string match Connecting* $::application::media::Priv(statusbar)] \
		[::application::media::PlayStream "no link"]
} -cleanup {
	catch { after cancel $::application::media::Priv(checkid) }
	set ::application::media::Priv(inprocess) 0
	rename ::application::media::PlayInProcess {}
	rename ::scidb::test::realPlayInProcess ::application::media::PlayInProcess
	set ::application::media::StreamOptions(recent) $saved
} -result {1 https://b.test/2.m3u8 {https://b.test/2.m3u8 https://a.test/1.m3u8} 1 0}

tcltest::test stream-check {a stream that never starts fails after the retries; a playing one is reported} -setup {
	rename ::application::media::MediaState ::scidb::test::realMediaState
	rename ::application::media::MediaDestroy ::scidb::test::realMediaDestroy
	proc ::application::media::MediaDestroy {} { set ::scidb::test::destroyed 1 }
	set ::application::media::Priv(inprocess) 1
	set ::application::media::Priv(stream) https://s.test/x.m3u8
	set ::scidb::test::destroyed 0
} -body {
	proc ::application::media::MediaState {} { return playing }
	::application::media::CheckStream https://s.test/x.m3u8 0
	set a [string match Streaming* $::application::media::Priv(statusbar)]
	proc ::application::media::MediaState {} { return idle }
	::application::media::CheckStream https://s.test/x.m3u8 8
	list $a $::scidb::test::destroyed [string match "*could not be played*" $::application::media::Priv(statusbar)]
} -cleanup {
	catch { after cancel $::application::media::Priv(checkid) }
	set ::application::media::Priv(inprocess) 0
	rename ::application::media::MediaState {}
	rename ::scidb::test::realMediaState ::application::media::MediaState
	rename ::application::media::MediaDestroy {}
	rename ::scidb::test::realMediaDestroy ::application::media::MediaDestroy
} -result {1 1 1}

tcltest::test stream-live-sites {live chess sites: a channel fills the link, a directory opens the browser} -setup {
	rename ::platform::sys::openURL ::scidb::test::realOpenURL
	proc ::platform::sys::openURL {x} { set ::scidb::test::opened $x }
	set ::scidb::test::opened {}
	::application::media::OpenStream .application
	set dlg .application.__mediastream__
} -body {
	set buttons [lsort -dictionary [winfo children $dlg.top.sites]]
	set kinds [lsort -unique [lmap s $::application::media::LiveSites { lindex $s 1 }]]
	foreach site $::application::media::LiveSites {
		lassign $site label kind url
		if {$kind eq "channel" && ![info exists channel]} { set channel $url }
		if {$kind eq "browse" && ![info exists browse]} { set browse $url }
	}
	::application::media::LiveSite $dlg.top.url channel $channel
	set filled [$dlg.top.url get]
	::application::media::LiveSite $dlg.top.url browse $browse
	list [expr {[llength $buttons] - 1 == [llength $::application::media::LiveSites]}] $kinds \
		[expr {$filled eq $channel}] [expr {$::scidb::test::opened eq $browse}] \
		[expr {[$dlg.top.url get] eq $channel}] \
		[lsort -unique [lmap s $::application::media::LiveSites { ::application::media::isStreamUrl [lindex $s 2] }]]
} -cleanup {
	destroy $dlg
	rename ::platform::sys::openURL {}
	rename ::scidb::test::realOpenURL ::platform::sys::openURL
} -result {1 {browse channel} 1 1 1 1}

tcltest::cleanupTests
