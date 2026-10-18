# ======================================================================
# ::playerdata -- the player dictionary's rating lists, kept current from
# their authoritative sources (player data plan, step 1: FIDE).
#
# Scidb ships FIDE's list of March 2012. FIDE publishes its combined list
# (standard, rapid, blitz; ID, name, federation, sex, titles, birth year)
# every month at ratings.fide.com. On request -- it is a download from the
# internet, never automatic -- the list is fetched, filtered to the players
# the dictionary keeps (rated 1800 or more in any of the three, or titled;
# about 250,000 of 1.9 million) into the user directory, and loaded into the
# running dictionary; at startup it replaces the shipped list. FIDE's
# spelling and federation win over the old ones; nothing is written into a
# database.
#
#   ::playerdata::fideFile              -> the updated list in the user directory
#   ::playerdata::fideInfo              -> {date D players N} of the update, or {}
#   ::playerdata::updateFide <parent> ?-confirm 0|1? ?-done CMD?
#       CMD gets {ok 1 players N read M} or {ok 0 error E}
#   ::playerdata::install <zip>         filter and load a downloaded list
#
# Names in a database are linked to the lists' entries when the database
# opens: exactly, or -- step 3 of the plan -- through other spellings
# (::scidb::db::linkPlayers: extra given names or a cut patronymic,
# initials, numbered namesakes, homonyms told apart by the games' Elo),
# only where the evidence agrees; the rest is left alone. A link changes
# what the player card and searches show, never the database.
#
#   ::playerdata::link <base>           link the names of an open database
#   ::playerdata::linkOpen              ... of every open database
#   ::playerdata::lastLink <base>       -> {linked N ambiguous {name ...}}
#
# What the rules leave is mostly other transliterations ("Tal, Mihail" for
# "Tal, Mikhail N"). On request -- the names go to the System One backend
# chosen in Extras > AI, possibly a cloud service -- a decision model judges
# whether the spellings name the same person. C++ has already kept only the
# entries of that surname whose initials, sex and rating agree with the games
# (::scidb::db::spellingCandidates); the model judges the name alone, which
# the experiments showed it does well, while it is unreliable on initials and
# Elo. A name is proposed only when exactly one entry reaches the threshold,
# and nothing is linked before the user confirms the list.
#
#   ::playerdata::spellingCheck <base> ?-threshold P? -done CMD
#       CMD gets {ok 1 proposals {{index name fideID entry p} ...} asked N}
#       or {ok 0 error E}
#   ::playerdata::applySpellings <base> <proposals>  -> number linked
#   ::playerdata::checkSpellings <parent>   the menu step for the current base
#
# Step 4 of the plan adds the national rating lists: the DWZ of the Deutscher
# Schachbund, the ECF's rating database and the ICCF's list. Their formats are
# their own and change (the DSB's CSV grew five columns since 2012, the ECF's
# grades became Elo-like ratings in 2020), so a download is converted into a
# list of Chesswiz' own format in the user directory, which startup then reads
# instead of the shipped list. Only the rows the dictionary keeps are written:
# rated high enough, or with a FIDE ID, or titled. A row with a FIDE ID joins
# that entry of the dictionary -- the national number, rating, birth year and
# titles are what FIDE's list lacks -- the others become entries of their own,
# and all of them are evidence for the linking above. docs/PLAYER_DATA_SOURCES.md
# has the URLs, the formats and what each federation asks for; the ICCF's
# download is a form of its web application, so that list is chosen as a file.
#
#   ::playerdata::ratingLists <parent>       the dialog of the three lists
#   ::playerdata::installList <kind> <file>  convert and load a fetched list
#
# Step 5 fixes the names of a database: a player linked to an entry of the
# rating lists has that entry's spelling as its canonical name. Where the
# database spells a name differently, the fix is proposed -- old name, new
# name, games affected, the list it comes from, a tick per row -- and nothing
# is renamed before the user confirms. The games keep pointing at their
# player, so a rename touches no game; it is written only when the database
# is saved, and closing the database without saving leaves the old names.
#
#   ::playerdata::fixNames <parent>           the preview for the current base
#   ::playerdata::revertNames <parent> <base>  rename the last fix back
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source player-data
}

namespace eval playerdata {
namespace eval mc {

set UpdateFide		"Update FIDE Rating List..."
set Confirm			"Download FIDE's current rating list (about 45 MB) from ratings.fide.com?"
set ConfirmDetail	"The list replaces the one Chesswiz ships (March 2012). Only players rated 1800 or more, or titled, are kept. Nothing is sent but the request."
set Downloading	"Downloading FIDE's rating list..."
set Done				"FIDE's rating list of %s is installed: %s players."
set Failed			"The FIDE rating list could not be updated: %s"
set CheckSpellings	"Link Other Spellings of Players..."
set SpellConfirm		"Ask the AI decision model whether %s unlinked player names are other spellings of rating-list entries?"
set SpellConfirmDetail	"The names and their candidates are sent to the System One backend chosen in Extras > AI (%s). Nothing is linked before you confirm."
set SpellNoBackend	"No System One backend is configured (Extras > AI)."
set SpellNothing		"No unlinked player name has a candidate with agreeing initials and rating."
set SpellNone		"None of the %s names could be matched with enough certainty."
set SpellPreview		"Link %s player names to these rating-list entries?"
set SpellMore		"... and %s more"
set SpellDone		"%s player name(s) linked."

set NationalLists	"&National Rating Lists..."
set ListsTitle		"National Rating Lists"
set ListsIntro		"Chesswiz can keep the rating lists of three federations beside FIDE's. A list is fetched only when you ask for it, is kept in your own directory, and is never written into a database."
set ListsFooter		"A fetched list is read at once, and replaces the shipped list at every start."
set ListInstalled	"installed %s: %s players"
set ListNotInstalled	"not installed"
set ListDownloading	"fetching..."
set ListDownload	"&Fetch"
set ListChoose		"Choose &File..."
set ListChooseTitle	"The ICCF rating list (a CSV file)"
set ListCsvFiles	"Rating lists"
set ListAllFiles	"All files"
set ListFailed		"The %s rating list could not be updated: %s"
set ListDone		"The %s rating list of %s is installed: %s player(s) kept of %s."
set ListFetching	"Fetching the %s rating list..."
set Close			"&Close"

set FixNames		"&Fix Player Names..."
set FixNamesTitle	"Fix Player Names"
set FixNamesConfirm	"Rename %s player name(s) of '%s' to the spelling of the rating lists?"
set FixNamesDetail	"A name is proposed where the database spells a player differently than the rating-list entry it is linked to. Untick a row to keep its name. Nothing is written until you save the database; closing it without saving leaves the old names."
set FixNamesNone	"No player name of this database differs from the rating-list entry it is linked to."
set FixNamesNoBase	"No database is open."
set FixNamesNothing	"No row is ticked: no name was changed."
set FixNamesDone	"%s player name(s) renamed. The database is not saved yet."
set FixNamesSkipped	"%s name(s) were left alone (%s)."
set FixNamesColOld	"Name in the database"
set FixNamesColNew	"Name in the rating list"
set FixNamesColGames	"Games"
set FixNamesColSource	"Source"
set FixNamesPickAll	"Tick &All"
set FixNamesPickNone	"Tick &None"
set FixNamesRevert	"&Undo Last Renaming"
set FixNamesReverted	"%s player name(s) renamed back."
set FixNamesNoUndo	"No renaming of this database to undo."

} ;# namespace mc

variable Url https://ratings.fide.com/download/players_list.zip
variable Busy 0
# LinkResult(<base>): what the last linking of <base> did
variable LinkResult
array set LinkResult {}
# the probability a spelling must reach (tuned on hand-made cases with
# jev-latest: true variants 0.79..0.98, contradicting names <= 0.15 once
# C++ has checked the initials)
variable SpellThreshold 0.9

# The national rating lists: whose list it is, where it comes from, and how.
# "download": the federation publishes the list for anyone to fetch; "file":
# the user has to fetch it (ICCF's download is a postback of its web
# application, which no HTTP client can repeat -- see
# docs/PLAYER_DATA_SOURCES.md). The notes are what the federations ask of us.
variable ListKinds {dwz ecf iccf}
variable ListSource
array set ListSource {
	dwz {
		name		"Deutscher Schachbund (DWZ)"
		how		download
		url		{https://www.schachbund.de/download-dwz-daten.html?file=files/wertungsportal/downloads/export/csv/LV-0-csv.zip}
		saved		LV-0-csv.zip
		note		"The DSB asks that its data not be published: Chesswiz fetches it only on your click, and keeps it in your own directory."
	}
	ecf {
		name		"English Chess Federation (ECF)"
		how		download
		url		{https://rating.englishchess.org.uk/api/rating-list/csv}
		saved		ecf-rating-list.csv
		note		"The ECF's rating API is public, and asks that one address not take more than ten minutes of processing a day."
	}
	iccf {
		name		"International Correspondence Chess Federation (ICCF)"
		how		file
		url		{https://www.iccf.com/ratings}
		saved		iccf-rating-list.csv
		note		"ICCF's list is a button of its web application, which no client can press for you: save the rating list as a CSV file and choose it here."
	}
}

# The proposals of a name fix, their ticks, and the way back
variable NameFix
array set NameFix {}

} ;# namespace playerdata


proc ::playerdata::Dir {} {
	return [file join $::scidb::dir::user ratings]
}


proc ::playerdata::fideFile {} {
	return [file join [Dir] fide-players.txt]
}


proc ::playerdata::fideInfo {} {
	set file [file join [Dir] fide-players.info]
	if {![file readable $file]} { return {} }
	if {[catch { set chan [open $file]; set info [read $chan]; close $chan }]} { return {} }
	if {![string is list $info] || [llength $info] % 2} { return {} }
	return $info
}


proc ::playerdata::updateFide {parent args} {
	variable Url
	variable Busy
	variable mc

	array set opts {-confirm 1 -done {}}
	array set opts $args

	if {$Busy} { return }
	if {$opts(-confirm)} {
		# the dialog of the rating lists: FIDE's download, and the way to the
		# national lists and to the names of a database
		set reply [::dialog::question -parent $parent -message $mc::Confirm -detail $mc::ConfirmDetail \
			-addbuttons [namespace code AddDataButtons]]
		switch -- $reply {
			yes			{}
			national	{ ratingLists $parent; return }
			names		{ fixNames $parent; return }
			default	{ return }
		}
	}
	set Busy 1
	::log::info "Player data" $mc::Downloading
	::application::download::Get $Url [namespace code [list Fetched $parent $opts(-done)]]
}


proc ::playerdata::Fetched {parent done result} {
	variable Busy
	variable mc

	if {![dict get $result ok]} {
		set Busy 0
		Report $parent $done [dict create ok 0 error [dict get $result error]]
		return
	}
	set zip [file join [Dir] players_list.zip]
	if {[catch {
		file mkdir [Dir]
		set chan [open $zip wb]
		puts -nonewline $chan [dict get $result data]
		close $chan
		set answer [install $zip]
	} err]} {
		set answer [dict create ok 0 error $err]
	}
	catch { file delete $zip }
	set Busy 0
	Report $parent $done $answer
}


# Filter FIDE's players_list.zip (or the text in it) into the user directory
# and load it into the dictionary.
proc ::playerdata::install {zip} {
	file mkdir [Dir]
	set file [fideFile]
	lassign [::scidb::app::filterFideList $zip $file.new] read kept
	file rename -force $file.new $file
	::scidb::app::load fide $file
	::scidb::app::load done
	# the new entries may fit names the old list did not
	linkOpen
	set info [dict create date [clock format [clock seconds] -format %Y-%m-%d] players $kept read $read]
	set chan [open [file join [Dir] fide-players.info] w]
	puts -nonewline $chan $info
	close $chan
	return [dict create ok 1 players $kept read $read]
}


proc ::playerdata::Report {parent done answer} {
	variable mc
	if {[dict get $answer ok]} {
		set text [format $mc::Done [dict get [fideInfo] date] [::locale::formatNumber [dict get $answer players]]]
		::log::info "Player data" $text
		if {![llength $done]} { ::dialog::info -parent $parent -message $text }
	} else {
		set text [format $mc::Failed [dict get $answer error]]
		::log::error "Player data" $text
		if {![llength $done]} { ::dialog::error -parent $parent -message $text }
	}
	if {[llength $done]} { uplevel #0 [list {*}$done $answer] }
}


proc ::playerdata::link {base} {
	variable LinkResult

	if {![llength [info commands ::scidb::db::linkPlayers]]} { return }
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	set linked 0
	set ambiguous {}
	foreach variant $variants {
		if {[catch { ::scidb::db::linkPlayers $base $variant } result]} { continue }
		incr linked [dict get $result linked]
		lappend ambiguous {*}[dict get $result ambiguous]
	}
	set LinkResult($base) [dict create linked $linked ambiguous $ambiguous]
	if {$linked} {
		::log::info "Player data" "[::util::databaseName $base]: $linked more player name(s) linked to the rating lists"
	}
	return $LinkResult($base)
}


proc ::playerdata::linkOpen {} {
	set bases {}
	catch {
		set switcher [::application::database::switcherWidget]
		if {[string length $switcher]} { set bases [$switcher bases] }
	}
	foreach base $bases { catch { link $base } }
}


proc ::playerdata::lastLink {base} {
	variable LinkResult
	if {[info exists LinkResult($base)]} { return $LinkResult($base) }
	return {}
}



proc ::playerdata::SpellQuestion {name entry} {
	return [dict create type noul \
		instructions "Could the chess player name \"$name\" be written for the same person as the rating-list name \"$entry\"? Accept transliteration variants (Mihail/Mikhail, Vasyl/Vassily), dropped patronymics and initials that match a given name; the surname must be the same name." \
		criteria [dict create \
			true "The two forms are compatible spellings of one person's name" \
			false "A given name contradicts, or the names are different names"]]
}


proc ::playerdata::spellingCheck {base args} {
	variable SpellThreshold
	array set opts [list -threshold $SpellThreshold -done {}]
	array set opts $args

	set work {}
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	foreach variant $variants {
		if {[catch { ::scidb::db::spellingCandidates $base $variant } rows]} { continue }
		foreach row $rows { lappend work [list $variant {*}$row] }
	}
	set state [dict create base $base work $work threshold $opts(-threshold) \
		done $opts(-done) proposals {} asked [llength $work]]
	after 0 [list ::playerdata::SpellNext $state]
	return [llength $work]
}


proc ::playerdata::SpellNext {state} {
	set work [dict get $state work]
	if {![llength $work]} {
		uplevel #0 [list {*}[dict get $state done] \
			[list ok 1 proposals [dict get $state proposals] asked [dict get $state asked]]]
		return
	}
	dict set state work [lrange $work 1 end]
	lassign [lindex $work 0] variant index name elo candidates
	set questions {}
	set k 0
	foreach c $candidates {
		dict set questions c[incr k] [SpellQuestion $name [lindex $c 1]]
	}
	::ai::systemone::evaluateAsync $name $questions \
		[list ::playerdata::SpellReply $state [list $variant $index $name $candidates]]
}


proc ::playerdata::SpellReply {state item reply} {
	if {![dict get $reply ok]} {
		uplevel #0 [list {*}[dict get $state done] [list ok 0 error [dict get $reply error]]]
		return
	}
	lassign $item variant index name candidates
	set answers [dict get $reply answers]
	set hits {}
	set k 0
	foreach c $candidates {
		set id c[incr k]
		if {![dict exists $answers $id noul]} { continue }
		set p [dict get $answers $id noul]
		if {$p >= [dict get $state threshold]} { lappend hits [list {*}$c $p] }
	}
	# exactly one entry, or none: two plausible entries are not a decision
	if {[llength $hits] == 1} {
		lassign [lindex $hits 0] identity entry fed rating p
		dict lappend state proposals [list $variant $index $name $identity $entry $p]
	}
	after 0 [list ::playerdata::SpellNext $state]
}


# <proposals> are the rows spellingCheck reported: the identity is the entry
# of a rating list, "fide:1503014", "dsb:10614-1081", "ecf:100011B" or
# "iccf:220015", not only a FIDE number.
proc ::playerdata::applySpellings {base proposals} {
	set linked 0
	foreach prop $proposals {
		lassign $prop variant index name identity
		if {![catch { ::scidb::db::linkPlayer $base $variant $index $identity } ok] && $ok} {
			incr linked
		}
	}
	if {$linked} {
		::log::info "Player data" "[::util::databaseName $base]: $linked player name(s) linked as other spellings"
	}
	return $linked
}


proc ::playerdata::checkSpellings {parent} {
	variable mc

	set base [::scidb::db::get name]
	if {![llength [info commands ::ai::systemone::enabled]] || ![::ai::systemone::enabled]} {
		::dialog::info -parent $parent -message $mc::SpellNoBackend
		return
	}
	set count 0
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	foreach variant $variants {
		catch { incr count [llength [::scidb::db::spellingCandidates $base $variant]] }
	}
	if {$count == 0} {
		::dialog::info -parent $parent -message $mc::SpellNothing
		return
	}
	set reply [::dialog::question -parent $parent -default no \
		-message [format $mc::SpellConfirm [::locale::formatNumber $count]] \
		-detail [format $mc::SpellConfirmDetail [::ai::systemone::describe]]]
	if {$reply ne "yes"} { return }
	::widget::busyCursor on
	spellingCheck $base -done [list ::playerdata::SpellPreview $parent $base]
}


proc ::playerdata::SpellPreview {parent base result} {
	variable mc

	::widget::busyCursor off
	if {![dict get $result ok]} {
		::dialog::error -parent $parent -message [dict get $result error]
		return
	}
	set proposals [dict get $result proposals]
	if {![llength $proposals]} {
		::dialog::info -parent $parent \
			-message [format $mc::SpellNone [::locale::formatNumber [dict get $result asked]]]
		return
	}
	set lines {}
	foreach prop [lrange $proposals 0 29] {
		lassign $prop variant index name fideID entry
		lappend lines "$name  \u2192  $entry ($fideID)"
	}
	if {[llength $proposals] > 30} {
		lappend lines [format $mc::SpellMore [expr {[llength $proposals] - 30}]]
	}
	set reply [::dialog::question -parent $parent -default no \
		-message [format $mc::SpellPreview [::locale::formatNumber [llength $proposals]]] \
		-detail [join $lines \n]]
	if {$reply ne "yes"} { return }
	set n [applySpellings $base $proposals]
	::dialog::info -parent $parent -message [format $mc::SpellDone [::locale::formatNumber $n]]
}


# ----------------------------------------------------------------------
# The national rating lists (step 4). The federations' downloads are
# converted into a list of Chesswiz' own format in the user directory
# (::scidb::app::filterRatingList), which startup reads instead of the
# shipped list (::scidb::app::load installed). Nothing is fetched but on a
# click of the user's, and nothing is written into a database.
# ----------------------------------------------------------------------

# The extra buttons of FIDE's dialog: that dialog is where the player data
# lives, and the menu has no room for the rest of it.
proc ::playerdata::AddDataButtons {f} {
	variable mc

	::tk::AmpWidget ::ttk::button $f.national -text " $mc::NationalLists" \
		-command [list set ::dialog::Reply([DialogOf $f]) national]
	::tk::AmpWidget ::ttk::button $f.names -text " $mc::FixNames" \
		-command [list set ::dialog::Reply([DialogOf $f]) names]
	pack $f.national $f.names -side left -padx {0 6}
}


# The dialog a frame of -addbuttons or -embed belongs to: a messagebox waits
# for ::dialog::Reply of that window.
proc ::playerdata::DialogOf {w} {
	return [winfo parent [winfo parent $w]]
}


proc ::playerdata::ratingLists {parent} {
	variable mc

	set msg "$mc::ListsIntro\n\n<embed>\n\n$mc::ListsFooter"
	::dialog::question -parent $parent -title $mc::ListsTitle -width 560 \
		-message $msg \
		-buttons [list [list cancel $mc::Close]] -default cancel \
		-embed [namespace code EmbedLists]
	return
}


# A row per federation: whose list it is, what is installed, and the button
# that fetches it.
proc ::playerdata::EmbedLists {w infoFont alertFont} {
	variable ListKinds
	variable mc

	set row 0
	foreach kind $ListKinds {
		set source [ListSource $kind]
		ttk::label $w.name$kind -text [dict get $source name] -font $alertFont
		ttk::label $w.status$kind -text [ListStatus $kind] -font $infoFont
		ttk::label $w.note$kind -text [dict get $source note] -font $infoFont \
			-wraplength 520 -justify left
		if {[dict get $source how] eq "download"} {
			::tk::AmpWidget ::ttk::button $w.button$kind -text " $mc::ListDownload" \
				-command [namespace code [list DownloadList $kind $w]]
		} else {
			::tk::AmpWidget ::ttk::button $w.button$kind -text " $mc::ListChoose" \
				-command [namespace code [list ChooseList $kind $w]]
		}
		grid $w.name$kind $w.status$kind $w.button$kind -row $row -sticky w -padx {0 8} -pady {8 0 0 0}
		grid $w.note$kind -row [incr row] -column 0 -columnspan 3 -sticky w -padx {0 8}
		grid columnconfigure $w 0 -weight 1
		incr row
	}
}


proc ::playerdata::ListSource {kind} {
	variable ListSource
	return [set ListSource($kind)]
}


proc ::playerdata::listFile {kind} {
	return [file join [Dir] $kind-ratings.txt]
}


proc ::playerdata::listInfoFile {kind} {
	return [file join [Dir] $kind-ratings.info]
}


# {date D players N read M source S} of an installed list, or {}
proc ::playerdata::listInfo {kind} {
	set file [listInfoFile $kind]
	if {![file readable $file]} { return {} }
	if {[catch { set chan [open $file]; set info [read $chan]; close $chan }]} { return {} }
	if {![string is list $info] || [llength $info] % 2} { return {} }
	return $info
}


proc ::playerdata::ListStatus {kind} {
	variable mc

	set info [listInfo $kind]
	if {![llength $info]} { return $mc::ListNotInstalled }
	return [format $mc::ListInstalled [dict get $info date] \
		[::locale::formatNumber [dict get $info players]]]
}


# Fetch a federation's list: the user's click is the only network traffic of
# this feature.
proc ::playerdata::DownloadList {kind w} {
	variable Busy
	variable mc

	if {$Busy} { return }
	set source [ListSource $kind]
	set Busy 1
	if {[winfo exists $w.button$kind]} {
		$w.button$kind configure -state disabled
		$w.status$kind configure -text $mc::ListDownloading
	}
	::log::info "Player data" [format $mc::ListFetching [dict get $source name]]
	::application::download::Get [dict get $source url] \
		[namespace code [list ListFetched $kind $w]]
}


proc ::playerdata::ListFetched {kind w result} {
	variable Busy

	set source [ListSource $kind]
	set answer [dict create ok 0 error "no answer"]

	if {![dict get $result ok]} {
		set answer [dict create ok 0 error [dict get $result error]]
	} elseif {[catch {
		file mkdir [Dir]
		set download [file join [Dir] [dict get $source saved]]
		set chan [open $download wb]
		puts -nonewline $chan [dict get $result data]
		close $chan
		set answer [installList $kind $download]
	} err]} {
		set answer [dict create ok 0 error $err]
	}

	set Busy 0
	if {[winfo exists $w.button$kind]} {
		$w.button$kind configure -state normal
		$w.status$kind configure -text [ListStatus $kind]
	}
	ReportList $kind $w $answer
}


# ICCF's list is fetched by hand: its download is a postback of its web
# application, which no HTTP client can repeat.
proc ::playerdata::ChooseList {kind w} {
	variable Busy
	variable mc

	if {$Busy} { return }
	set file [tk_getOpenFile -parent $w -title $mc::ListChooseTitle -filetypes [list \
		[list $mc::ListCsvFiles {.csv .txt .zip}] [list $mc::ListAllFiles *]]]
	if {![string length $file]} { return }
	if {[catch { installList $kind $file } answer]} {
		set answer [dict create ok 0 error $answer]
	}
	if {[winfo exists $w.status$kind]} {
		$w.status$kind configure -text [ListStatus $kind]
	}
	ReportList $kind $w $answer
}


# Convert a federation's download into a list of Chesswiz' own format in the
# user directory, and read it into the running dictionary; startup reads the
# same file instead of the shipped list.
proc ::playerdata::installList {kind source} {
	file mkdir [Dir]
	set file [listFile $kind]
	lassign [::scidb::app::filterRatingList $kind $source $file.new] read kept
	file rename -force $file.new $file
	::scidb::app::load installed $file
	::scidb::app::load done
	# the new entries may fit names the dictionary did not have
	linkOpen
	set info [dict create date [clock format [clock seconds] -format %Y-%m-%d] \
		players $kept read $read source [file tail $source]]
	set chan [open [listInfoFile $kind] w]
	puts -nonewline $chan $info
	close $chan
	return [dict create ok 1 players $kept read $read]
}


proc ::playerdata::ReportList {kind parent answer} {
	variable mc

	set name [dict get [ListSource $kind] name]
	if {[dict get $answer ok]} {
		set text [format $mc::ListDone $name [dict get [listInfo $kind] date] \
			[::locale::formatNumber [dict get $answer players]] \
			[::locale::formatNumber [dict get $answer read]]]
		::log::info "Player data" $text
		::dialog::info -parent $parent -message $text
	} else {
		set text [format $mc::ListFailed $name [dict get $answer error]]
		::log::error "Player data" $text
		::dialog::error -parent $parent -message $text
	}
	return [dict get $answer ok]
}


# ----------------------------------------------------------------------
# The canonical names of a database (step 5). A player linked to an entry of
# the rating lists has that entry's spelling as its canonical name; where the
# database spells it differently, the fix is proposed and applied only on a
# click. Renaming touches no game -- the games keep pointing at their player
# -- and is written only when the database is saved.
# ----------------------------------------------------------------------

# The Latin diacritics folded the German way ("Müller" is "Mueller"), and
# lower case: a comparison of two surnames should not fail on a letter the
# lists spell differently.
proc ::playerdata::Folded {name} {
	set folded [string map {
		ä ae ö oe ü ue Ä Ae Ö Oe Ü Ue ß ss
		à a á a â a ã a å a ā a ą a æ ae
		è e é e ê e ë e ē e ę e ė e
		ì i í i î i ï i ī i į i
		ò o ó o ô o õ o ø o ō o œ oe
		ù u ú u û u ū u ų u ů u
		ý y ÿ y ń n ñ n ř r š s ž z ć c č c
		đ d ł l ţ t ї i і i є e ґ g
	} $name]
	set ascii ""
	foreach c [split $folded ""] {
		scan $c %c n
		if {$n < 128} { append ascii $c }
	}
	return [string tolower $ascii]
}


# The surname of a "Surname, Given" name, folded.
proc ::playerdata::Surname {name} {
	set comma [string first , $name]
	if {$comma < 0} { return [Folded $name] }
	return [Folded [string range $name 0 [expr {$comma - 1}]]]
}


# Whether <new> -- the spelling of the rating-list entry a name is linked to
# -- is a name a database can be asked to take: a person of the "Surname,
# Given" form, and not one of the placeholders the lists use for a player
# they do not know.
proc ::playerdata::IsCanonicalName {new} {
	set comma [string first , $new]
	if {$comma < 2} { return 0 }

	set surname [string trim [string range $new 0 [expr {$comma - 1}]]]
	set given [string trim [string range $new [expr {$comma + 1}] end]]

	if {[string length $surname] < 2 || [string length $surname] > 60} { return 0 }
	if {[string length $given] < 2} { return 0 }
	if {[string length $new] > 200} { return 0 }

	switch -- [string tolower $surname] {
		n - nn - unknown - player - "?" - "??" - "-" { return 0 }
	}
	if {[string first "\n" $new] >= 0 || [string first "\r" $new] >= 0} { return 0 }

	return 1
}


# "fide:1503014" becomes "FIDE 1503014": the list a name comes from.
proc ::playerdata::FormatSource {identity} {
	set colon [string first : $identity]
	if {$colon < 0} { return $identity }
	set kind [string range $identity 0 [expr {$colon - 1}]]
	set number [string range $identity [expr {$colon + 1}] end]
	switch -- $kind {
		fide	{ set label FIDE }
		dsb	{ set label DWZ }
		ecf	{ set label ECF }
		iccf	{ set label ICCF }
		default	{ set label [string toupper $kind] }
	}
	return "$label $number"
}


# The names of a database that differ from the rating-list entry they are
# linked to: {variant index old new games source tick} per row. A row whose
# surnames differ is left unticked -- a rename of those is the user's call
# alone, since the link itself may rest on a rating and a federation.
proc ::playerdata::NameProposals {base} {
	set rows {}
	set variants Normal
	catch { set variants [::scidb::db::get variants $base] }
	foreach variant $variants {
		if {[catch { ::scidb::db::playerLinks $base $variant } links]} { continue }
		set index 0
		foreach link $links {
			lassign $link name games linked fideID elo federation entry identity
			if {	$linked
				&& [string length $identity]
				&& [string length $entry]
				&& $entry ne $name
				&& [IsCanonicalName $entry]} {
				lappend rows [list $variant $index $name $entry $games \
					[FormatSource $identity] [expr {[Surname $name] eq [Surname $entry]}]]
			}
			incr index
		}
	}
	return $rows
}


proc ::playerdata::Mark {tick} {
	if {$tick} { return {[x]} }
	return {[  ]}
}


proc ::playerdata::fixNames {parent} {
	variable NameFix
	variable mc

	set base [::scidb::db::get name]
	if {![string length $base]} {
		::dialog::info -parent $parent -message $mc::FixNamesNoBase
		return
	}
	::widget::busyCursor on
	set rows [NameProposals $base]
	::widget::busyCursor off
	if {![llength $rows]} {
		::dialog::info -parent $parent -message $mc::FixNamesNone
		return
	}

	set NameFix(base) $base
	set NameFix(rows) $rows
	set NameFix(tree) {}
	for {set i 0} {$i < [llength $rows]} {incr i} {
		set NameFix(tick,$i) [lindex [lindex $rows $i] 6]
	}

	set msg [format $mc::FixNamesConfirm [::locale::formatNumber [llength $rows]] \
		[::util::databaseName $base]]
	append msg "\n\n<embed>"

	set reply [::dialog::question -parent $parent -title $mc::FixNamesTitle -default no \
		-message $msg -detail $mc::FixNamesDetail \
		-embed [namespace code EmbedNameFixes] \
		-addbuttons [namespace code [list AddNameFixButtons $base]]]

	switch -- $reply {
		yes		{ ApplyNameFixes $parent $base }
		revert	{ revertNames $parent $base }
	}
	return
}


# The rows of the preview, one tick per row: old name, new name, games
# affected, and the list the new name comes from.
proc ::playerdata::EmbedNameFixes {w infoFont alertFont} {
	variable NameFix
	variable mc

	set rows $NameFix(rows)
	ttk::frame $w.box
	set tree [ttk::treeview $w.box.tree -show headings -selectmode none \
		-height [expr {min(12, max(3, [llength $rows]))}] \
		-columns {pick old new games source}]
	::ttk::scrollbar $w.box.scroll -command [list $tree yview]
	$tree configure -yscrollcommand [list $w.box.scroll set]

	$tree heading pick -text ""
	$tree heading old -text $mc::FixNamesColOld -anchor w
	$tree heading new -text $mc::FixNamesColNew -anchor w
	$tree heading games -text $mc::FixNamesColGames -anchor e
	$tree heading source -text $mc::FixNamesColSource -anchor w
	$tree column pick -width 34 -anchor center -stretch 0
	$tree column old -width 190 -anchor w
	$tree column new -width 190 -anchor w
	$tree column games -width 52 -anchor e -stretch 0
	$tree column source -width 110 -anchor w -stretch 0

	set i 0
	foreach row $rows {
		lassign $row variant index old new games source tick
		$tree insert {} end -id $i -values [list [Mark $tick] $old $new $games $source]
		incr i
	}

	bind $tree <Button-1> [namespace code [list ClickNameFix $tree %x %y]]
	set NameFix(tree) $tree

	grid $tree $w.box.scroll -sticky ns
	grid rowconfigure $w.box 0 -weight 1
	grid columnconfigure $w.box 0 -weight 1
	pack $w.box -side top -fill both -expand 1
}


proc ::playerdata::ClickNameFix {tree x y} {
	variable NameFix

	set row [$tree identify row $x $y]
	if {![string length $row] || ![info exists NameFix(tick,$row)]} { return }
	set NameFix(tick,$row) [expr {!$NameFix(tick,$row)}]
	$tree set $row pick [Mark $NameFix(tick,$row)]
}


proc ::playerdata::TickNameFixes {pick} {
	variable NameFix

	for {set i 0} {$i < [llength $NameFix(rows)]} {incr i} {
		set NameFix(tick,$i) $pick
	}
	if {[string length $NameFix(tree)] && [winfo exists $NameFix(tree)]} {
		for {set i 0} {$i < [llength $NameFix(rows)]} {incr i} {
			$NameFix(tree) set $i pick [Mark $pick]
		}
	}
}


# Tick all, tick none, and the way back of the last renaming.
proc ::playerdata::AddNameFixButtons {base f} {
	variable NameFix
	variable mc

	::tk::AmpWidget ::ttk::button $f.all -text " $mc::FixNamesPickAll" \
		-command [namespace code [list TickNameFixes 1]]
	::tk::AmpWidget ::ttk::button $f.none -text " $mc::FixNamesPickNone" \
		-command [namespace code [list TickNameFixes 0]]
	pack $f.all $f.none -side left -padx {0 6}

	if {[info exists NameFix(undo,$base)] && [llength $NameFix(undo,$base)]} {
		::tk::AmpWidget ::ttk::button $f.undo -text " $mc::FixNamesRevert" \
			-command [list set ::dialog::Reply([DialogOf $f]) revert]
		pack $f.undo -side left -padx {0 6}
	}
}


# Rename the ticked rows, all of a variant in one step: renaming sorts the
# namebase, so an index is only valid until then.
proc ::playerdata::ApplyNameFixes {parent base} {
	variable NameFix
	variable mc

	set byVariant {}
	set undo {}
	set picked 0
	set i 0

	foreach row $NameFix(rows) {
		lassign $row variant index old new games source tick
		if {$NameFix(tick,$i)} {
			incr picked
			dict lappend byVariant $variant $index $new
			lappend undo [list $variant $new $old]
		}
		incr i
	}

	if {!$picked} {
		::dialog::info -parent $parent -message $mc::FixNamesNothing
		return 0
	}

	set renamed 0
	set reasons {}
	foreach variant [dict keys $byVariant] {
		if {[catch { ::scidb::db::renamePlayers $base $variant [dict get $byVariant $variant] } result]} {
			lappend reasons $result
			continue
		}
		incr renamed [dict get $result renamed]
		foreach row [dict get $result skipped] {
			lassign $row index name reason
			if {[lsearch -exact $reasons $reason] < 0} { lappend reasons $reason }
		}
	}

	if {$renamed} {
		set NameFix(undo,$base) $undo
		if {$base eq [::scidb::db::get name]} {
			catch { ::application::database::refreshBase $base }
		}
		::log::info "Player data" "[::util::databaseName $base]: $renamed player name(s) fixed from the rating lists"
	} else {
		set NameFix(undo,$base) {}
	}

	set text [format $mc::FixNamesDone [::locale::formatNumber $renamed]]
	if {[llength $reasons]} {
		append text "\n" [format $mc::FixNamesSkipped [::locale::formatNumber $picked] [join $reasons "; "]]
	}
	::dialog::info -parent $parent -message $text
	return $renamed
}


# The way back: the names of the last fix become what they were. The indices
# of a namebase change with every renaming, so the names are looked up again.
proc ::playerdata::revertNames {parent base} {
	variable NameFix
	variable mc

	if {![info exists NameFix(undo,$base)] || ![llength $NameFix(undo,$base)]} {
		::dialog::info -parent $parent -message $mc::FixNamesNoUndo
		return 0
	}

	set byVariant {}
	foreach item $NameFix(undo,$base) {
		lassign $item variant new old
		dict lappend byVariant $variant [list $new $old]
	}

	set renamed 0
	foreach variant [dict keys $byVariant] {
		set renames {}
		foreach pair [dict get $byVariant $variant] {
			lassign $pair new old
			set index [NameIndex $base $variant $new]
			if {$index < 0} { continue }
			lappend renames $index $old
		}
		if {![llength $renames]} { continue }
		if {[catch { ::scidb::db::renamePlayers $base $variant $renames } result]} { continue }
		incr renamed [dict get $result renamed]
	}

	set NameFix(undo,$base) {}
	if {$renamed && $base eq [::scidb::db::get name]} {
		catch { ::application::database::refreshBase $base }
	}
	::log::info "Player data" "[::util::databaseName $base]: $renamed player name(s) renamed back"
	::dialog::info -parent $parent -message [format $mc::FixNamesReverted [::locale::formatNumber $renamed]]
	return $renamed
}


proc ::playerdata::NameIndex {base variant name} {
	if {[catch { ::scidb::db::playerLinks $base $variant } links]} { return -1 }
	set index 0
	foreach link $links {
		if {[lindex $link 0] eq $name} { return $index }
		incr index
	}
	return -1
}
