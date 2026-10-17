# ======================================================================
# ::application::download -- download games from the internet.
#
# The database menu's "Download Games..." fetches games from public
# sources into the database it was opened for, through the same
# ::import::import path as "Import PGN files...". The files are kept in
# <Scidb home>/downloads.
#
#   TWIC (The Week in Chess)
#     The last one to twelve weekly issues; each is a zip holding one PGN
#     with the week's new games (https://theweekinchess.com/zips/twic<N>g.zip).
#     The current issue number is parsed from the TWIC index page, so no
#     number is ever hard-coded. The server rejects plain command-line
#     user agents, so requests identify themselves as a browser.
#   Lichess
#     Single games, by URL or game id, one per line
#     (https://lichess.org/game/export/<id> answers application/x-chess-pgn).
#   Player games
#     A Chess.com or Lichess player's games of the last months. Chess.com
#     lists a player's monthly archives (api.chess.com/pub/player/<p>/games/
#     archives); each month's PGN is <archive>/pgn. Lichess sends a player's
#     games since a time as one PGN (lichess.org/api/games/user/<p>?since=).
#     Lichess may refuse anonymous exports (303 to /signup, 404, 401); a
#     personal API token (lichess.org/account/oauth/token, no scopes needed)
#     is then sent, to lichess.org only, as a Bearer header.
#   URL
#     Any PGN, zipped PGN or gzipped PGN file on the web.
#
# Downloads are asynchronous (the dialog stays responsive, each file is
# fetched to its end before the next starts) and can be cancelled; the
# import runs only over the files that arrived. HTTPS uses the tls
# package with per-host Server Name Indication (hosts behind a proxy
# answer 421 without it).
#
#   ::application::download::open $parent $base
#
# The pure helpers (twicIssues, lichessGameIds, chessComArchives,
# playerName, lichessUserUrl, destName) are UI-free and
# covered by tests/test_app_download.tcl.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-download-games
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval download {
namespace eval mc {

set Title					"Download Games"
set Source					"Source"
set Twic					"The Week in Chess"
set TwicDetail				"The latest weekly issues; each zip holds one PGN with the week's new games."
set Issues					"Issues to fetch:"
set Lichess					"Lichess games"
set LichessDetail			"One game link or game id per line:"
set Player					"A player's games"
set PlayerDetail			"All games of a Chess.com or Lichess player in the last months:"
set Site					"Site:"
set PlayerName				"Player:"
set Months					"Months:"
set NoPlayer				"no valid player name given"
set NoArchives				"Chess.com has no games of %s in the last %d month(s)"
set PlayerImport			"%s games of %s download import"
set Url						"PGN file from URL"
set UrlDetail				"Any PGN, zipped PGN or gzipped PGN file:"
set Import					"Import into:"
set Download				"Download"
set Cancel					"Cancel"
set FetchingIndex			"Asking The Week in Chess for the current issue..."
set Fetching				"Fetching %s..."
set Fetched					"Fetched %s (%s)"
set Done					"Downloaded %d file(s) to %s; importing..."
set DoneNoImport			"Downloaded %d file(s) to %s."
set NothingFetched			"Nothing was downloaded."
set Cancelled				"Cancelled; %d file(s) fetched; importing..."
set Failed					"%s failed (%s)"
set NoIssues				"could not find an issue number on the TWIC index page"
set NoGames					"no Lichess game links or ids found"
set NoUrl					"no URL given"
set NoTls					"The tls package is needed for https downloads."
set DownloadsDir			"downloads"
set TwicImport					"TWIC %s download import"
set LichessImport			"Lichess download import"
set UrlImport					"PGN download import"
set LichessToken			"Lichess API token (optional):"
set NeedToken				"Lichess refused the download without a login. Create a personal API token at lichess.org/account/oauth/token (no permissions needed) and enter it in this dialog."

} ;# namespace mc

array set Options {
	lichess:token ""
}

variable Timeout 120000
variable RetryDelay 3000

array set Priv {
	dialog			{}
	running			0
	cancel				0
	queue				{}
	fetched			{}
	failures			{}
	title				{}
	base				{}
}

} ;# namespace download
} ;# namespace application


proc ::application::download::open {parent base} {
	variable Priv
	variable mc

	set dlg $parent.__download__
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}
	set Priv(dialog) $dlg
	set Priv(base) $base
	set Priv(doneCmd) {}
	set Priv(source) twic
	set Priv(issues) 1
	set Priv(lichess) ""
	set Priv(url) ""
	set Priv(site) Chess.com
	set Priv(player) ""
	set Priv(months) 1

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### source ################################################################
	ttk::labelframe $top.source -text " $mc::Source " -padding $::theme::padx

	set twic [ttk::frame $top.source.twic]
	ttk::radiobutton $twic.choice \
		-text $mc::Twic -value twic -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $twic.detail -text $mc::TwicDetail -wraplength 360 -justify left
	set issues [ttk::frame $twic.issues]
	ttk::label $issues.label -text $mc::Issues
	ttk::spinbox $issues.count -from 1 -to 12 -width 3 -textvariable [namespace current]::Priv(issues)
	pack $issues.label -side left
	pack $issues.count -side left -padx [list $::theme::padx 0]
	pack $twic.choice -anchor w
	pack $twic.detail -anchor w -pady [list 0 $::theme::pady]
	pack $issues -anchor w
	pack $twic -fill x -pady [list 0 $::theme::pady]

	set lichess [ttk::frame $top.source.lichess]
	ttk::radiobutton $lichess.choice \
		-text $mc::Lichess -value lichess -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $lichess.detail -text $mc::LichessDetail -wraplength 360 -justify left
	tk::text $lichess.text \
		-width 48 -height 5 -wrap word -undo false \
		-highlightthickness 0 \
		;
	set Priv(lichessWidget) $lichess.text
	ttk::scrollbar $lichess.vs -orient vertical -command [list $lichess.text yview]
	$lichess.text configure -yscrollcommand [list $lichess.vs set]
	pack $lichess.choice -anchor w
	pack $lichess.detail -anchor w
	pack $lichess.text -side left -fill both -expand yes -pady [list 0 $::theme::pady]
	pack $lichess.vs -side right -fill y -pady [list 0 $::theme::pady]
	pack $lichess -fill both -expand yes -pady [list 0 $::theme::pady]

	set player [ttk::frame $top.source.player]
	ttk::radiobutton $player.choice \
		-text $mc::Player -value player -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $player.detail -text $mc::PlayerDetail -wraplength 360 -justify left
	set row [ttk::frame $player.row]
	ttk::label $row.lsite -text $mc::Site
	ttk::combobox $row.site -state readonly -width 10 -values {Chess.com Lichess} \
		-textvariable [namespace current]::Priv(site)
	ttk::label $row.lname -text $mc::PlayerName
	ttk::entry $row.name -width 18 -textvariable [namespace current]::Priv(player)
	ttk::label $row.lmonths -text $mc::Months
	ttk::spinbox $row.months -from 1 -to 24 -width 3 -textvariable [namespace current]::Priv(months)
	pack $row.lsite $row.site -side left
	pack $row.lname -side left -padx [list $::theme::padx 0]
	pack $row.name -side left -fill x -expand yes
	pack $row.lmonths -side left -padx [list $::theme::padx 0]
	pack $row.months -side left
	set trow [ttk::frame $player.token]
	ttk::label $trow.label -text $mc::LichessToken
	ttk::entry $trow.entry -show * -width 30 \
		-textvariable [namespace current]::Options(lichess:token)
	pack $trow.label -side left
	pack $trow.entry -side left -fill x -expand yes -padx [list $::theme::padx 0]
	pack $player.choice -anchor w
	pack $player.detail -anchor w
	pack $row -fill x
	pack $trow -fill x -pady [list $::theme::pady 0]
	pack $player -fill x -pady [list 0 $::theme::pady]

	set url [ttk::frame $top.source.url]
	ttk::radiobutton $url.choice \
		-text $mc::Url -value url -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $url.detail -text $mc::UrlDetail -wraplength 360 -justify left
	ttk::entry $url.entry -textvariable [namespace current]::Priv(url)
	pack $url.choice -anchor w
	pack $url.detail -anchor w
	pack $url.entry -fill x
	pack $url -fill x

	pack $top.source -fill both -expand yes

	### status ###############################################################
	set name [::util::databaseName $base]
	ttk::label $top.target -text "$mc::Import $name"
	ttk::label $top.status -wraplength 420 -justify left
	pack $top.target -fill x -pady [list $::theme::pady 0]
	pack $top.status -fill x

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::Download -command [namespace code Start]
	$dlg.cancel configure -text $mc::Cancel -command [namespace code Close]

	set Priv(status) $top.status

	SourceChanged
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $twic.choice
	return $dlg
}


# The active database's download dialog; the Extras menu entry uses this,
# the database popup menu opens a specific base directly.
proc ::application::download::openActive {parent} {
	set base [::scidb::db::get name]
	return [open $parent $base]
}


proc ::application::download::SourceChanged {} {
	# all sources keep their input; only the active one is used on start
	return
}


# The dialog path is only valid while the dialog exists: after Close it
# is empty, and winfo errors on the empty string.
proc ::application::download::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::application::download::Close {} {
	variable Priv

	set Priv(cancel) 1
	if {![DialogExists]} { set Priv(dialog) {} ; return }
	if {$Priv(running)} {
		# let the queue stop by itself; the running fetch cannot be aborted
		$Priv(status) configure -text ""
		destroy $Priv(dialog)
	} else {
		destroy $Priv(dialog)
	}
	set Priv(dialog) {}
}


# ----------------------------------------------------------------------
# The fetch queue: a list of {url file label}; files land in the
# downloads directory. One request at a time, one retry on a transient
# failure, cancellable between files.
# ----------------------------------------------------------------------

proc ::application::download::Start {} {
	variable Priv
	variable mc

	if {$Priv(running)} { return }

	set dir [Dir]
	file mkdir $dir
	set Priv(cancel) 0
	set Priv(fetched) {}
	set Priv(failures) {}
	set queue {}

	switch -- $Priv(source) {
		twic {
			set Priv(title) $mc::TwicImport
			Status $mc::FetchingIndex
			if {[DialogExists]} { $Priv(dialog).ok configure -state disabled }
			set Priv(running) 1
			Get https://theweekinchess.com/twic [namespace code [list OnTwicIndex]]
			return
		}
		lichess {
			set ids [lichessGameIds [$Priv(lichessWidget) get 1.0 end]]
			if {![llength $ids]} {
				Status $mc::NoGames
				return
			}
			set Priv(title) $mc::LichessImport
			foreach id $ids {
				lappend queue [list [lichessUrl $id] \
					[file join $dir "lichess-$id.pgn"] "lichess.org/$id"]
			}
		}
		player {
			set name [playerName $Priv(player)]
			if {$name eq ""} {
				Status $mc::NoPlayer
				return
			}
			set months [Months]
			set Priv(title) [format $mc::PlayerImport $Priv(site) $name]
			if {$Priv(site) eq "Lichess"} {
				set since [expr {([clock seconds] - $months*31*86400)*1000}]
				lappend queue [list [lichessUserUrl $name $since] \
					[file join $dir "lichess-$name.pgn"] "lichess.org/@/$name"]
			} else {
				if {[DialogExists]} { $Priv(dialog).ok configure -state disabled }
				set Priv(running) 1
				Status [format $mc::Fetching "chess.com/member/$name"]
				Get [chessComArchivesUrl $name] \
					[namespace code [list OnChessComArchives $name $months]]
				return
			}
		}
		url {
			set url [string trim $Priv(url)]
			if {$url eq ""} {
				Status $mc::NoUrl
				return
			}
			set Priv(title) $mc::UrlImport
			lappend queue [list $url [file join $dir [destName $url]] [file tail $url]]
		}
	}

	if {[DialogExists]} { $Priv(dialog).ok configure -state disabled }
	set Priv(running) 1
	set Priv(queue) $queue
	FetchNext
}


proc ::application::download::OnTwicIndex {result} {
	variable Priv
	variable mc

	if {![dict get $result ok]} {
		Finish [format $mc::Failed $mc::Twic [dict get $result error]]
		return
	}
	set issues [twicIssues [dict get $result data]]
	if {![llength $issues]} {
		Finish [format $mc::Failed $mc::Twic $mc::NoIssues]
		return
	}
	set latest [lindex $issues 0]
	set count $Priv(issues)
	if {![string is integer -strict $count] || $count < 1} { set count 1 }
	if {$count > [llength $issues]} { set count [llength $issues] }
	if {$count > 12} { set count 12 }

	set dir [Dir]
	set queue {}
	set first [expr {$latest - $count + 1}]
	foreach n [lrange $issues 0 [expr {$count - 1}]] {
		lappend queue [list [twicZipUrl $n] [file join $dir [twicZipName $n]] "TWIC $n"]
	}
	if {$count > 1} {
		set Priv(title) [format $mc::TwicImport "$first-$latest"]
	} else {
		set Priv(title) [format $mc::TwicImport $latest]
	}
	set Priv(queue) $queue
	FetchNext
}


proc ::application::download::OnChessComArchives {name months result} {
	variable Priv
	variable mc

	if {![dict get $result ok]} {
		Finish [format $mc::Failed "chess.com/member/$name" [dict get $result error]]
		return
	}
	set archives [chessComArchives [dict get $result data] $months]
	if {![llength $archives]} {
		Finish [format $mc::NoArchives $name $months]
		return
	}
	set dir [Dir]
	set queue {}
	foreach url $archives {
		regexp {(\d{4})/(\d{2})$} $url _ y m
		lappend queue [list $url/pgn [file join $dir "chesscom-$name-$y-$m.pgn"] "chess.com $name $y-$m"]
	}
	set Priv(queue) $queue
	FetchNext
}


proc ::application::download::Months {} {
	variable Priv
	set months $Priv(months)
	if {![string is integer -strict $months] || $months < 1} { set months 1 }
	if {$months > 24} { set months 24 }
	return $months
}


proc ::application::download::FetchNext {} {
	variable Priv
	variable mc

	if {$Priv(cancel)} {
		Finish [format $mc::Cancelled [llength $Priv(fetched)]]
		return
	}
	if {![llength $Priv(queue)]} {
		Finish [format $mc::Done [llength $Priv(fetched)] [Dir]]
		return
	}

	lassign [lindex $Priv(queue) 0] url file label
	set Priv(queue) [lrange $Priv(queue) 1 end]
	Status [format $mc::Fetching $label]
	Get $url [namespace code [list OnFetched $url $file $label 0]]
}


proc ::application::download::OnFetched {url file label retry result} {
	variable Priv
	variable Timeout
	variable RetryDelay
	variable mc

	set ok [dict get $result ok]
	set code [dict get $result code]
	if {!$ok && $retry == 0 && ($code eq "timeout" || $code eq "eof" || $code >= 500 || $code == 429 || $code == 408)} {
		after $RetryDelay [namespace code [list Get $url [namespace code [list OnFetched $url $file $label 1]]]]
		return
	}
	if {!$ok} {
		set error [dict get $result error]
		if {[string match https://lichess.org/* $url] && $code in {303 401 403 404}} {
			set error $mc::NeedToken
		}
		lappend Priv(failures) [format $mc::Failed $label $error]
	} else {
		file mkdir [file dirname $file]
		set chan [::open $file wb]
		fconfigure $chan -translation binary
		puts -nonewline $chan [dict get $result data]
		close $chan
		lappend Priv(fetched) $file
		Status [format $mc::Fetched $label [size [file size $file]]]
	}
	FetchNext
}


# A status line update that tolerates a dialog closed mid-run.
proc ::application::download::Status {text} {
	variable Priv
	if {[DialogExists]} {
		$Priv(status) configure -text $text
	}
}


# All done (or cancelled): import what arrived, then report.
proc ::application::download::Finish {text} {
	variable Priv
	variable mc

	set Priv(running) 0
	set files $Priv(fetched)
	set failures $Priv(failures)

	if {![llength $files]} {
		set text [expr {[llength $failures] ? [join $failures "; "] : $mc::NothingFetched}]
		Status $text
		if {[DialogExists]} {
			$Priv(dialog).ok configure -state normal
		}
		Done [dict create ok 0 error $text]
		return
	}

	set parent .
	if {[DialogExists]} {
		set parent [winfo parent $Priv(dialog)]
		destroy $Priv(dialog)
	}
	set Priv(dialog) {}
	set base $Priv(base)
	if {[catch { ::import::import $parent $base $files $Priv(title) utf-8 } err]} {
		catch { ::dialog::error -parent $parent -message $err }
		Done [dict create ok 0 error "import failed: $err"]
		return
	}
	if {[catch { ::scidb::db::get name } name] == 0 && $base eq $name} {
		catch { ::application::database::refreshBase $base }
	}
	Done [dict create ok 1 files [llength $files] base $base]
}


# The headless completion callback, if the run was started by
# ::application::download::run (the assistant), not by the dialog.
proc ::application::download::Done {result} {
	variable Priv

	set cmd [expr {[info exists Priv(doneCmd)] ? $Priv(doneCmd) : {}}]
	set Priv(doneCmd) {}
	if {[llength $cmd]} { catch { {*}$cmd $result } }
	return
}


# Headless entry: download <spec> into <base>, then call <doneCmd> with
# {ok 1 files N base B} or {ok 0 error TEXT}. Used by the assistant tool
# download_games; the dialog uses Start directly.
#
#   ::application::download::run $base {-source twic -issues 2} $cmd
proc ::application::download::run {base spec doneCmd} {
	variable Priv

	if {[expr {[info exists Priv(running)] ? $Priv(running) : 0}]} {
		{*}$doneCmd [list ok 0 error "a download is already running"]
		return
	}
	set Priv(source)  [expr {[dict exists $spec -source]  ? [dict get $spec -source]  : "twic"}]
	set Priv(issues)  [expr {[dict exists $spec -issues]  ? [dict get $spec -issues]  : 1}]
	set Priv(lichess) [expr {[dict exists $spec -lichess] ? [dict get $spec -lichess] : ""}]
	set Priv(url)     [expr {[dict exists $spec -url]     ? [dict get $spec -url]     : ""}]
	set Priv(site)    [expr {[dict exists $spec -site]    ? [dict get $spec -site]    : "Chess.com"}]
	set Priv(player)  [expr {[dict exists $spec -player]  ? [dict get $spec -player]  : ""}]
	set Priv(months)  [expr {[dict exists $spec -months]  ? [dict get $spec -months]  : 1}]
	set Priv(base)    $base
	set Priv(dialog)  {}
	set Priv(doneCmd) $doneCmd
	Start
	return
}


# ----------------------------------------------------------------------
# HTTP plumbing (UI-free).
# ----------------------------------------------------------------------

# https needs the tls package, registered with the host in the Server Name
# Indication; hosts behind a proxy answer 421 without it. One registration
# is cached per host.
proc ::application::download::Tls {host} {
	variable TlsHost

	if {[string match http://* $host]} { return 1 }
	if {![info exists TlsHost] || $TlsHost ne $host} {
		if {[catch { package require tls }]} { return 0 }
		::platform::sys::tlsInit
		::http::register https 443 [list ::tls::socket -servername $host]
		set TlsHost $host
	}
	return 1
}


# A browser identity: TWIC (and others) reject plain command-line agents
# with 406.
proc ::application::download::UserAgent {} {
	return "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
}


# <done> is called with {ok 1 data D code 200} or {ok 0 error E code C}.
proc ::application::download::Get {url done} {
	variable Timeout

	if {[catch { package require http 2.7 } err]} {
		after 0 [list {*}$done [list ok 0 error $err code 0]]
		return
	}
	if {[regexp {^https://([^/:]+)} $url _ host] && ![Tls $host]} {
		variable mc
		after 0 [list {*}$done [list ok 0 error $mc::NoTls code 0]]
		return
	}

	set headers [list User-Agent [UserAgent] Accept "*/*"]
	if {[string match https://lichess.org/* $url]} {
		variable Options
		set headers [list User-Agent [UserAgent] Accept application/x-chess-pgn]
		set token [string trim $Options(lichess:token)]
		if {$token ne ""} { lappend headers Authorization "Bearer $token" }
	}
	# the opening explorer (explorer.lichess.ovh) also requires the token
	if {[string match https://explorer.lichess.ovh/* $url]} {
		variable Options
		set headers [list User-Agent [UserAgent] Accept application/json]
		set token [string trim $Options(lichess:token)]
		if {$token ne ""} { lappend headers Authorization "Bearer $token" }
	}
	if {[catch { ::http::geturl $url \
		-headers $headers \
		-timeout $Timeout -binary 1 -command [namespace code [list OnHttp $done]] \
	} token]} {
		# a synchronous failure (malformed url, unknown protocol);
		# asynchronous failures arrive through OnHttp
		after 0 [list {*}$done [list ok 0 error $token code 0]]
	}
	return
}


proc ::application::download::OnHttp {done token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set error [::http::error $token]
	set data [::http::data $token] ;# raw bytes: zips stay intact, PGN is decoded at import
	::http::cleanup $token

	if {$status eq "ok" && $code == 200} {
		set result [list ok 1 data $data code $code]
	} else {
		if {![string length $error]} { set error $status }
		set result [list ok 0 error $error code $code]
	}
	uplevel #0 [list {*}$done $result]
	return
}


# ----------------------------------------------------------------------
# Pure helpers (UI-free; covered by tests/test_app_download.tcl).
# ----------------------------------------------------------------------

# The issue numbers on the TWIC index page, newest first. The page lists
# the zips of the last issues, in the current (twic<N>g.zip PGN,
# twic<N>c6.zip ChessBase) and older (twic<N>.zip) layouts.
proc ::application::download::twicIssues {html} {
	set numbers {}
	foreach {_ n} [regexp -all -inline {zips/twic(\d+)(?:g|c6)?\.zip} $html] {
		if {$n ni $numbers} { lappend numbers $n }
	}
	return [lsort -decreasing -integer $numbers]
}


proc ::application::download::twicZipUrl {n} {
	return "https://theweekinchess.com/zips/twic${n}g.zip"
}


proc ::application::download::twicZipName {n} {
	return "twic${n}g.zip"
}


# Lichess game ids out of free text: full URLs, /game/export/<id> links or
# bare ids, one or many per line, also comma or space separated. Lichess
# game ids are 8 characters; anything else in a bare chunk is left alone.
proc ::application::download::lichessGameIds {text} {
	set ids {}
	foreach chunk [split $text "\n, \t;"] {
		set chunk [string trim $chunk]
		if {$chunk eq ""} { continue }
		if {[regexp {(?:https?://)?(?:www\.)?lichess\.org/(?:game/export/)?([A-Za-z0-9]{8})} $chunk _ id]} {
			if {$id ni $ids} { lappend ids $id }
		} elseif {[regexp {^[A-Za-z0-9]{8}$} $chunk]} {
			if {$chunk ni $ids} { lappend ids $chunk }
		}
	}
	return $ids
}


proc ::application::download::lichessUrl {id} {
	return "https://lichess.org/game/export/$id"
}


# A player name as both sites accept it (letters, digits, - and _), or "".
proc ::application::download::playerName {text} {
	set text [string trim $text]
	regexp {(?:chess\.com/member/|lichess\.org/@/)([^/?#\s]+)} $text _ text
	if {![regexp {^[A-Za-z0-9_-]{2,30}$} $text]} { return "" }
	return $text
}


proc ::application::download::chessComArchivesUrl {name} {
	return "https://api.chess.com/pub/player/[string tolower $name]/games/archives"
}


# The last <months> monthly archive URLs out of the Chess.com archives JSON
# ({"archives":["https://api.chess.com/pub/player/p/games/2026/09",...]},
# oldest first), oldest first.
proc ::application::download::chessComArchives {json months} {
	set urls [regexp -all -inline {https://api\.chess\.com/pub/player/[^"/]+/games/\d{4}/\d{2}} $json]
	set urls [lsort -unique $urls]
	return [lrange $urls end-[expr {$months - 1}] end]
}


proc ::application::download::lichessUserUrl {name since} {
	return "https://lichess.org/api/games/user/$name?since=$since&clocks=false&evals=false"
}


# A safe file name for a URL download.
proc ::application::download::destName {url} {
	set path [lindex [split $url ?] 0]
	set tail [file tail $path]
	if {[string length $tail] == 0 || $tail eq "/"} { set tail download.pgn }
	set tail [regsub -all -- {[^A-Za-z0-9._-]} $tail _]
	if {![regexp {\.(pgn|zip|gz)$} $tail]} { append tail ".pgn" }
	return $tail
}


proc ::application::download::Dir {} {
	return [file join $::scidb::dir::home $::application::download::mc::DownloadsDir]
}


proc ::application::download::size {bytes} {
	if {$bytes >= 1048576} {
		return [format "%.1f MB" [expr {$bytes / 1048576.0}]]
	}
	return [format "%.0f KB" [expr {$bytes / 1024.0}]]
}


proc ::application::download::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::application::download::WriteOptions

# vi:set ts=3 sw=3:
