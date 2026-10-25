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
#   Lichess study
#     A study's PGN, by URL or id, with an optional chapter id:
#     https://lichess.org/api/study/<id>.pgn (or .../<id>/<chapter>.pgn).
#     The same Lichess token handling as for player games is used.
#   Lichess broadcast
#     A live broadcast: the games of one round or of a whole tournament.
#     The round URL (lichess.org/broadcast/<slug>/<roundSlug>/<roundId>) or
#     a tournament id is answered by the API as PGN
#     (lichess.org/api/broadcast/round/<roundId>.pgn, or
#     lichess.org/api/broadcast/<tournamentId>.pgn for all the rounds). The
#     games are imported into the database like the other sources. With
#     "refresh every N minutes" the round is fetched again and again, and
#     only the games that are not in the database yet are imported; they
#     are told apart by the game's own Lichess id (its Site tag) or by
#     its round and board. Cancel stops the refresh.
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
# covered by tests/test_app_download.tcl. Lichess study parsing and
# URLs live in app-lichess-study and are covered by
# tests/test_app_lichess_study.tcl.
# covered by tests/test_app_download.tcl; the broadcast helpers
# (broadcastSpec, broadcastUrls, broadcastKey) are covered by
# tests/test_app_lichess_broadcast.tcl.
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
set Study					"Lichess study"
set StudyDetail				"One study link or study id per line, optionally with a chapter id:"
set Broadcast				"Lichess broadcast"
set BroadcastDetail			"A round URL or a tournament id; the games are fetched as PGN and imported."
set BroadcastUrl			"Round URL or tournament id:"
set BroadcastRefresh			"Refresh every"
set BroadcastMinutes			"minutes"
set BroadcastImport			"Lichess broadcast import"
set BroadcastImported			"Imported %d new game(s)."
set BroadcastNoNew			"No new game(s); %d game(s) of the broadcast are already there."
set BroadcastNext			"%d game(s) imported; the next refresh is in %d minute(s). Cancel stops it."
set BroadcastFailed			"The broadcast could not be fetched: %s"
set NoBroadcast				"no Lichess broadcast round or tournament given"
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
set NoStudies				"no Lichess study links or ids found"
set NoUrl					"no URL given"
set NoTls					"The tls package is needed for https downloads."
set DownloadsDir			"downloads"
set TwicImport					"TWIC %s download import"
set LichessImport			"Lichess download import"
set StudyImport				"Lichess study import"
set UrlImport					"PGN download import"
set LichessToken			"Lichess API token (optional):"
set NeedToken				"Lichess refused the download without a login. Create a personal API token at lichess.org/account/oauth/token (no permissions needed) and enter it in this dialog."

} ;# namespace mc

array set Options {
	lichess:token ""
	lichess:broadcast ""
	lichess:refresh 0
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
	broadcast			""
	refresh			0
	refreshOn			0
	bcSpec				{}
	bcUrls				{}
	bcUrl				0
	bcKeys				{}
	bcGames			0
	bcImported			0
	bcFile				{}
	bcTimer			{}
	bcInterval			0
	bcActive			0
}

} ;# namespace download
} ;# namespace application


proc ::application::download::open {parent base} {
	variable Priv
	variable mc
	variable Options

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
	set Priv(studies) ""
	set Priv(broadcast) $Options(lichess:broadcast)
	set Priv(refresh) $Options(lichess:refresh)
	set Priv(refreshOn) [expr {$Options(lichess:refresh) > 0}]

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

	set study [ttk::frame $top.source.study]
	ttk::radiobutton $study.choice \
		-text $mc::Study -value study -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $study.detail -text $mc::StudyDetail -wraplength 360 -justify left
	tk::text $study.text \
		-width 48 -height 4 -wrap word -undo false \
		-highlightthickness 0 \
		;
	set Priv(studiesWidget) $study.text
	ttk::scrollbar $study.vs -orient vertical -command [list $study.text yview]
	$study.text configure -yscrollcommand [list $study.vs set]
	pack $study.choice -anchor w
	pack $study.detail -anchor w
	pack $study.text -side left -fill both -expand yes -pady [list 0 $::theme::pady]
	pack $study.vs -side right -fill y -pady [list 0 $::theme::pady]
	pack $study -fill both -expand yes -pady [list 0 $::theme::pady]
	set bc [ttk::frame $top.source.broadcast]
	ttk::radiobutton $bc.choice \
		-text $mc::Broadcast -value broadcast -variable [namespace current]::Priv(source) \
		-command [namespace code SourceChanged] \
		;
	ttk::label $bc.detail -text $mc::BroadcastDetail -wraplength 360 -justify left
	ttk::label $bc.urllabel -text $mc::BroadcastUrl
	ttk::entry $bc.url -textvariable [namespace current]::Priv(broadcast)
	set rrow [ttk::frame $bc.refresh]
	ttk::checkbutton $rrow.check -text $mc::BroadcastRefresh \
		-variable [namespace current]::Priv(refreshOn) \
		-command [namespace code RefreshChanged] \
		;
	ttk::spinbox $rrow.minutes -from 1 -to 240 -width 3 \
		-textvariable [namespace current]::Priv(refresh) -state disabled
	set Priv(refreshWidget) $rrow.minutes
	ttk::label $rrow.unit -text $mc::BroadcastMinutes
	pack $rrow.check -side left
	pack $rrow.minutes -side left -padx [list $::theme::padx 0]
	pack $rrow.unit -side left -padx [list 2 0]
	pack $bc.choice -anchor w
	pack $bc.detail -anchor w
	pack $bc.urllabel -anchor w
	pack $bc.url -fill x
	pack $rrow -anchor w -pady [list $::theme::pady 0]
	pack $bc -fill x -pady [list 0 $::theme::pady]

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
	RefreshChanged
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


# The study text from the dialog, or the headless -studies value.
proc ::application::download::StudyText {} {
	variable Priv
	if {[info exists Priv(studiesWidget)] && [winfo exists $Priv(studiesWidget)]} {
		return [$Priv(studiesWidget) get 1.0 end]
	}
	return [expr {[info exists Priv(studies)] ? $Priv(studies) : ""}]
}


# The refresh spinbox is only usable when the refresh is wanted.
proc ::application::download::RefreshChanged {} {
	variable Priv

	if {![info exists Priv(refreshWidget)]} { return }
	if {![winfo exists $Priv(refreshWidget)]} { return }
	$Priv(refreshWidget) configure -state [expr {$Priv(refreshOn) ? "normal" : "disabled"}]
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
	if {$Priv(bcActive)} {
		set Priv(bcActive) 0
		set Priv(running) 0
	}
	CancelRefresh
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
	variable Options

	if {$Priv(running)} { return }

	set dir [Dir]
	file mkdir $dir
	set Priv(cancel) 0
	set Priv(fetched) {}
	set Priv(failures) {}
	set queue {}
	CancelRefresh

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
		study {
			set specs [::application::lichess::study::specs [StudyText]]
			if {![llength $specs]} {
				Status $mc::NoStudies
				return
			}
			set Priv(title) $mc::StudyImport
			foreach entry $specs {
				lassign $entry id chapter
				lappend queue [list \
					[::application::lichess::study::pgnUrl $id $chapter] \
					[file join $dir [::application::lichess::study::fileName $id $chapter]] \
					[::application::lichess::study::label $id $chapter]]
			}
		}
		broadcast {
			set spec [broadcastSpec $Priv(broadcast)]
			if {$spec eq ""} {
				set Priv(bcUrls) {}
				set Priv(bcUrl) 0
				Status $mc::NoBroadcast
				return
			}
			set Priv(title) $mc::BroadcastImport
			set Priv(bcSpec) $spec
			set Priv(bcUrls) [broadcastUrls $spec]
			set Priv(bcUrl) 0
			set Priv(bcImported) 0
			set Priv(bcInterval) [RefreshSeconds]
			set Priv(bcActive) 1
			set Priv(bcFile) [file join $dir "lichess-broadcast-[broadcastFileId $spec].pgn"]
			# the games that are already in the database are not imported again
			lassign [broadcastDbKeys $Priv(base) [broadcastSpecRound $spec]] \
				Priv(bcKeys) Priv(bcGames)
			set Options(lichess:broadcast) $Priv(broadcast)
			set Options(lichess:refresh) [RefreshMinutes]
			if {[DialogExists]} { $Priv(dialog).ok configure -state disabled }
			set Priv(running) 1
			BroadcastFetch
			return
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


# ----------------------------------------------------------------------
# The Lichess broadcast: one round or a whole tournament. The games are
# fetched as PGN and imported; with a refresh the round is fetched again
# and again, and only the games that are not in the database yet are
# imported.
# ----------------------------------------------------------------------

# The refresh interval in minutes (0 when there is no refresh).
proc ::application::download::RefreshMinutes {} {
	variable Priv

	if {!$Priv(refreshOn)} { return 0 }
	set minutes $Priv(refresh)
	if {![string is integer -strict $minutes] || $minutes < 1} { set minutes 1 }
	if {$minutes > 240} { set minutes 240 }
	return $minutes
}


# The refresh interval in seconds; the timer waits for it.
proc ::application::download::RefreshSeconds {} {
	return [expr {[RefreshMinutes] * 60}]
}


# Whether the broadcast is fetched again and again.
proc ::application::download::RefreshActive {} {
	variable Priv

	return [expr {$Priv(bcInterval) > 0}]
}


# The next fetch of the broadcast, in <interval> seconds.
proc ::application::download::ScheduleRefresh {} {
	variable Priv
	variable mc

	if {![RefreshActive]} { return }
	if {$Priv(cancel)} { return }
	if {![DialogExists]} { return }
	set Priv(bcTimer) [after [expr {$Priv(bcInterval) * 1000}] \
		[namespace code BroadcastRefresh]]
	Status [format $mc::BroadcastNext $Priv(bcImported) [RefreshMinutes]]
	return
}


# The pending refresh is dropped: the broadcast is fetched only once.
proc ::application::download::CancelRefresh {} {
	variable Priv

	if {[string length $Priv(bcTimer)]} {
		catch { after cancel $Priv(bcTimer) }
		set Priv(bcTimer) {}
	}
	set Priv(bcInterval) 0
	return
}


# The timer of the refresh fired: the round is fetched again.
proc ::application::download::BroadcastRefresh {} {
	variable Priv

	if {[string length $Priv(bcTimer)]} {
		catch { after cancel $Priv(bcTimer) }
		set Priv(bcTimer) {}
	}
	if {$Priv(cancel) || !$Priv(bcActive)} { return }
	set Priv(running) 1
	BroadcastFetch
	return
}


# The next candidate URL of the broadcast is fetched.
proc ::application::download::BroadcastFetch {} {
	variable Priv

	# a new fetch starts at the first candidate
	set Priv(bcUrl) 0
	BroadcastTry
	return
}


# The candidate URL of the broadcast is fetched; a wrong id answers 404
# and the next candidate is tried.
proc ::application::download::BroadcastTry {} {
	variable Priv
	variable mc

	set url [lindex $Priv(bcUrls) $Priv(bcUrl)]
	if {$url eq ""} {
		BroadcastDone [format $mc::Failed $mc::Broadcast $mc::NoBroadcast] 0
		return
	}
	incr Priv(bcUrl)
	Status [format $mc::Fetching [broadcastLabel $Priv(bcSpec)]]
	Get $url [namespace code [list OnBroadcast $url 0]]
	return
}


# The broadcast was fetched: the new games are imported.
proc ::application::download::OnBroadcast {url retry result} {
	variable Priv
	variable RetryDelay
	variable mc

	set ok [dict get $result ok]
	set code [dict get $result code]
	if {!$ok && $retry == 0 && ($code eq "timeout" || $code eq "eof" || $code >= 500 || $code == 429 || $code == 408)} {
		set Priv(bcTimer) [after $RetryDelay \
			[list [namespace current]::Get $url [namespace code [list OnBroadcast $url 1]]]]
		return
	}
	if {!$ok} {
		# a wrong id answers 404: the same id may be a tournament
		if {$code == 404 && $Priv(bcUrl) < [llength $Priv(bcUrls)]} {
			BroadcastTry
			return
		}
		set error [dict get $result error]
		if {[string match https://lichess.org/* $url] && $code in {303 401 403}} {
			set error $mc::NeedToken
		}
		lappend Priv(failures) [format $mc::Failed [broadcastLabel $Priv(bcSpec)] $error]
		BroadcastDone [format $mc::BroadcastFailed $error] 0
		return
	}

	if {$Priv(cancel)} {
		BroadcastDone [format $mc::Cancelled 0] 0
		return
	}

	# the round as it was fetched is kept in the downloads directory
	set file $Priv(bcFile)
	file mkdir [file dirname $file]
	set chan [::open $file wb]
	fconfigure $chan -translation binary
	puts -nonewline $chan [dict get $result data]
	close $chan

	BroadcastImport [dict get $result data]
	return
}


# A file name that is not in use yet: name, name-2, name-3, ... Every
# import keeps its own file, so a refresh does not overwrite the file of
# the import before it.
proc ::application::download::freeFile {name} {
	set stem [file rootname $name]
	set ext [file extension $name]
	set n 1
	set file $name
	while {[file exists $file]} {
		incr n
		set file "$stem-$n$ext"
	}
	return $file
}


# The games of the fetched PGN that are not in the database yet are
# written to a file of their own and imported.
proc ::application::download::BroadcastImport {data} {
	variable Priv
	variable mc

	set round [broadcastSpecRound $Priv(bcSpec)]
	lassign [broadcastNewGames [encoding convertfrom utf-8 $data] $Priv(bcKeys) $round] text keys count
	if {!$count} {
		set Priv(bcImported) 0
		BroadcastDone [format $mc::BroadcastNoNew $Priv(bcGames)] 1
		return
	}

	set file [freeFile [file join [Dir] "[file rootname [file tail $Priv(bcFile)]]-new.pgn"]]
	file mkdir [file dirname $file]
	set chan [::open $file wb]
	fconfigure $chan -translation binary
	puts -nonewline $chan [encoding convertto utf-8 $text]
	close $chan

	set parent .
	if {[DialogExists]} { set parent [winfo parent $Priv(dialog)] }
	set base $Priv(base)
	if {[catch { ::import::import $parent $base $file $Priv(title) utf-8 } err]} {
		catch { ::dialog::error -parent $parent -message $err }
		BroadcastDone [format $mc::Failed $mc::Broadcast $err] 0
		return
	}
	foreach key $keys { dict set Priv(bcKeys) $key 1 }
	set Priv(bcImported) $count
	incr Priv(bcGames) $count
	if {[catch { ::scidb::db::get name } name] == 0 && $base eq $name} {
		catch { ::application::database::refreshBase $base }
	}
	BroadcastDone [format $mc::BroadcastImported $Priv(bcImported)] 1
	return
}


# The broadcast is done: the dialog stays open when the refresh goes on.
proc ::application::download::BroadcastDone {text ok} {
	variable Priv
	variable mc

	set Priv(running) 0
	if {[DialogExists]} {
		$Priv(dialog).ok configure -state normal
		Status $text
	}
	# the refresh needs the dialog: it goes on until the dialog is closed
	if {$ok && [RefreshActive] && [DialogExists]} {
		ScheduleRefresh
		return
	}
	CancelRefresh
	set Priv(bcActive) 0
	if {$ok} {
		Done [dict create ok 1 files $Priv(bcImported) base $Priv(base)]
	} else {
		Done [dict create ok 0 error $text]
	}
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
	set Priv(studies) [expr {[dict exists $spec -studies] ? [dict get $spec -studies] : ""}]
	set Priv(url)     [expr {[dict exists $spec -url]     ? [dict get $spec -url]     : ""}]
	set Priv(site)    [expr {[dict exists $spec -site]    ? [dict get $spec -site]    : "Chess.com"}]
	set Priv(player)  [expr {[dict exists $spec -player]  ? [dict get $spec -player]  : ""}]
	set Priv(months)  [expr {[dict exists $spec -months]  ? [dict get $spec -months]  : 1}]
	set Priv(broadcast) [expr {[dict exists $spec -broadcast] ? [dict get $spec -broadcast] : ""}]
	set Priv(refresh)  [expr {[dict exists $spec -refresh]  ? [dict get $spec -refresh]  : 0}]
	set Priv(refreshOn) [expr {$Priv(refresh) > 0}]
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


# ----------------------------------------------------------------------
# The Lichess broadcast helpers (UI-free; covered by
# tests/test_app_lichess_broadcast.tcl).
# ----------------------------------------------------------------------

# The broadcast of <text>, as a dict: {kind round|tournament|auto,
# tournament T, round R, label L}. The kinds are
#   round       a round of a tournament (the round URL),
#   tournament  a tournament (all its rounds),
#   auto        a bare id: it may be a round or a tournament, both are
#               tried.
# The round URL is lichess.org/broadcast/<slug>/<roundSlug>/<roundId>; the
# tournament URL is lichess.org/broadcast/<tournamentId>. A round URL
# with a game id behind it names the round of the game. "" when <text>
# is no broadcast at all.
proc ::application::download::broadcastSpec {text} {
	set text [string trim $text]
	if {$text eq ""} { return {} }
	# a query or a fragment says nothing about the round
	set text [lindex [split $text "?"] 0]
	set text [lindex [split $text "#"] 0]
	set text [string trim $text]
	if {$text eq ""} { return {} }

	# a bare id: a round or a tournament, both are tried
	if {![string match "*/*" $text]} {
		if {![regexp {^[A-Za-z0-9_-]+$} $text]} { return {} }
		return [dict create kind auto id $text label $text]
	}

	if {![regexp {^(?:https?://)?(?:www\.)?lichess\.org/(.*)$} $text -> path]} { return {} }
	set path [string trim $path "/"]
	set parts [split $path "/"]
	if {[lindex $parts 0] ne "broadcast"} { return {} }
	set rest [lrange $parts 1 end]
	foreach part $rest {
		if {![regexp {^[A-Za-z0-9_-]+$} $part]} { return {} }
	}
	switch -- [llength $rest] {
		1 {
			return [dict create kind tournament \
				tournament [lindex $rest 0] label [lindex $rest 0]]
		}
		2 - 3 {
			return [dict create kind round \
				tournament [lindex $rest 0] round [lindex $rest end] \
				label [lindex $rest end]]
		}
		4 {
			# a game of a round: the round is the third part
			return [dict create kind round \
				tournament [lindex $rest 0] round [lindex $rest 2] \
				label [lindex $rest 2]]
		}
	}
	return {}
}


# The PGN URLs of a broadcast: the round of a round URL, all the rounds of
# a tournament. A bare id is tried as a round first and as a tournament
# afterwards.
proc ::application::download::broadcastUrls {spec} {
	if {$spec eq ""} { return {} }
	switch -- [dict get $spec kind] {
		round {
			return [list "https://lichess.org/api/broadcast/round/[dict get $spec round].pgn"]
		}
		tournament {
			return [list "https://lichess.org/api/broadcast/[dict get $spec tournament].pgn"]
		}
		auto {
			set id [dict get $spec id]
			return [list "https://lichess.org/api/broadcast/round/$id.pgn" \
				"https://lichess.org/api/broadcast/$id.pgn"]
		}
	}
	return {}
}


# The name of a broadcast in the status line.
proc ::application::download::broadcastLabel {spec} {
	if {$spec eq ""} { return "lichess.org/broadcast" }
	switch -- [dict get $spec kind] {
		round { return "lichess.org/broadcast/[dict get $spec round]" }
		tournament { return "lichess.org/broadcast/[dict get $spec tournament]" }
		auto { return "lichess.org/broadcast/[dict get $spec id]" }
	}
	return "lichess.org/broadcast"
}


# The file name part of a broadcast: its round or its tournament id.
proc ::application::download::broadcastFileId {spec} {
	if {$spec eq ""} { return "round" }
	switch -- [dict get $spec kind] {
		round { return [dict get $spec round] }
		tournament { return [dict get $spec tournament] }
		auto { return [dict get $spec id] }
	}
	return "round"
}


# The Lichess game id in a URL, or "". A game URL is
# lichess.org/<id> or lichess.org/game/export/<id>; in a broadcast the
# game has its own URL behind the round
# (lichess.org/broadcast/<slug>/<roundSlug>/<roundId>/<gameId>). The URL
# of the round itself names the round, not a game: it is no game id.
proc ::application::download::broadcastGameId {url roundId} {
	if {![regexp {lichess\.org/(.*)$} $url -> path]} { return "" }
	set parts [split [string trim $path "/"] "/"]
	switch -- [llength $parts] {
		1 {
			if {[regexp {^[A-Za-z0-9]{8}$} [lindex $parts 0]]} { return [lindex $parts 0] }
		}
		3 {
			if {[lindex $parts 0] eq "game" && [lindex $parts 1] eq "export"} {
				return [lindex $parts 2]
			}
		}
		5 {
			if {[lindex $parts 0] eq "broadcast"} {
				set id [lindex $parts 4]
				if {[regexp {^[A-Za-z0-9]{8}$} $id] && $id ne $roundId} { return $id }
			}
		}
	}
	return ""
}


# The round id in a broadcast URL, or "": the last part of a broadcast
# URL, unless the game of the round stands behind it.
proc ::application::download::broadcastRoundOf {url} {
	if {![regexp {lichess\.org/(.*)$} $url -> path]} { return "" }
	set parts [split [string trim $path "/"] "/"]
	if {[lindex $parts 0] ne "broadcast"} { return "" }
	switch -- [llength $parts] {
		3 { return [lindex $parts 2] }
		4 - 5 { return [lindex $parts 3] }
	}
	return ""
}


# The game of a broadcast game: its Lichess id and its Lichess URL. The
# id is in the Site tag of a game of a round, but some tournaments put
# the place of the game in the Site tag and its own URL in the GameURL
# tag; both are read.
proc ::application::download::broadcastGame {tags {roundId ""}} {
	set id ""
	set url ""
	foreach name {Site GameURL} {
		if {![dict exists $tags $name]} { continue }
		set candidate [dict get $tags $name]
		if {$id eq ""} {
			set found [broadcastGameId $candidate $roundId]
			if {$found ne ""} { set id $found }
		}
		if {$url eq "" && [string match *lichess.org* $candidate]} { set url $candidate }
	}
	return [list $id $url]
}


# The keys that tell a broadcast game from another one: its own Lichess
# id (its Site or GameURL tag), its round and its board, its round, its
# players and its date. The database keeps the round, the players and the
# date, but not the id of the game: a game is known when one of its keys
# is known.
proc ::application::download::broadcastKeys {tags {roundId ""}} {
	set keys {}
	lassign [broadcastGame $tags $roundId] id url
	if {$id ne ""} { lappend keys "lichess:$id" }

	# the round of the game is its Round tag; the round of the broadcast is
	# only the fallback, for a game without a round of its own
	set event ""
	set date ""
	if {[dict exists $tags Event]} { set event [dict get $tags Event] }
	if {[dict exists $tags Date]} { set date [dict get $tags Date] }
	set round ""
	if {[dict exists $tags Round]} { set round [dict get $tags Round] }
	if {$round eq "" && $url ne ""} { set round [broadcastRoundOf $url] }
	if {$round eq ""} { set round $roundId }

	set board ""
	if {[dict exists $tags Board]} { set board [dict get $tags Board] }
	if {$board ne ""} { lappend keys [list board $event $date $round $board] }

	set white ""
	set black ""
	if {[dict exists $tags White]} { set white [dict get $tags White] }
	if {[dict exists $tags Black]} { set black [dict get $tags Black] }
	if {$white ne "" || $black ne ""} {
		set date ""
		if {[dict exists $tags Date]} { set date [dict get $tags Date] }
		lappend keys [list players $event $date $round $white $black]
	}
	return $keys
}


# The key of a broadcast game: its first key (see broadcastKeys).
proc ::application::download::broadcastKey {tags {roundId ""}} {
	return [lindex [broadcastKeys $tags $roundId] 0]
}


# The round id of a broadcast, or "": a tournament has no round of its own.
proc ::application::download::broadcastSpecRound {spec} {
	if {[dict exists $spec round]} { return [dict get $spec round] }
	return ""
}


# The games of a PGN text: each one a dict with the tags, the order of
# the tag names and the moves.
proc ::application::download::broadcastGames {pgn} {
	set games {}
	set tags {}
	set order {}
	set body {}
	set haveBody 0
	set tagDone 0

	foreach line [split $pgn "\n"] {
		set line [string trimright $line "\r"]
		if {[regexp {^\[([A-Za-z0-9_]+)\s+"((?:[^"\\]|\\.)*)"\]\s*$} $line -> name value]} {
			if {$haveBody || $tagDone} {
				lappend games [dict create tags $tags order $order body [string trim [join $body "\n"]]]
				set tags {}
				set order {}
				set body {}
				set haveBody 0
				set tagDone 0
			}
			dict set tags $name $value
			if {$name ni $order} { lappend order $name }
			continue
		}
		if {[string trim $line] eq ""} {
			if {$haveBody} { lappend body $line }
			continue
		}
		set haveBody 1
		lappend body $line
	}
	if {[llength $tags] || [llength $body]} {
		lappend games [dict create tags $tags order $order body [string trim [join $body "\n"]]]
	}
	return $games
}


# A game as PGN again.
proc ::application::download::broadcastGameText {game} {
	set tags [dict get $game tags]
	set text ""
	foreach name [dict get $game order] {
		set value [dict get $tags $name]
		append text "\[$name \"$value\"]\n"
	}
	set body [dict get $game body]
	if {[string length $body]} {
		append text "\n$body\n"
	}
	return $text
}


# The games of <pgn> that are not in <keys> yet: the PGN of the new games,
# their keys and their number. A game is known when one of its keys is
# known; a game without a key is always new.
proc ::application::download::broadcastNewGames {pgn keys {roundId ""}} {
	set text ""
	set newKeys {}
	set seen {}
	set count 0
	foreach game [broadcastGames $pgn] {
		set gameKeys [broadcastKeys [dict get $game tags] $roundId]
		set known 0
		foreach key $gameKeys {
			if {[dict exists $keys $key] || [dict exists $seen $key]} {
				set known 1
				break
			}
		}
		if {$known} { continue }
		foreach key $gameKeys { dict set seen $key 1 }
		lappend newKeys {*}$gameKeys
		incr count
		append text [broadcastGameText $game]
	}
	return [list $text $newKeys $count]
}


# The keys of the broadcast games that are already in <base>, and their
# number. The games of other sources have no key and are left alone.
proc ::application::download::broadcastDbKeys {base {roundId ""}} {
	set keys [dict create]
	set games 0
	if {[llength [info commands ::scidb::db::get]] == 0} { return [list $keys $games] }
	if {[catch { ::scidb::db::get open? $base } open]} { return [list $keys $games] }
	if {![string is boolean -strict $open] || !$open} { return [list $keys $games] }
	if {[catch { ::scidb::db::count games $base Normal } count]} { return [list $keys $games] }
	if {![string is integer -strict $count]} { return [list $keys $games] }
	for {set index 0} {$index < $count} {incr index} {
		if {[catch { ::scidb::db::get tags $index $base Normal } pairs]} { continue }
		set tags {}
		foreach pair $pairs { dict set tags {*}$pair }
		set gameKeys [broadcastKeys $tags $roundId]
		if {![llength $gameKeys]} { continue }
		incr games
		foreach key $gameKeys { dict set keys $key 1 }
	}
	return [list $keys $games]
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
