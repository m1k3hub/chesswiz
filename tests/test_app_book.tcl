# ======================================================================
# Scidb App Test - the polyglot opening book editor
# (src/app/app_polyglot_book.cpp, src/tcl/tcl_book.cpp, tcl/book.tcl)
# ======================================================================
# Round trip (create from a small game set, write, read back with the
# reader, same moves/weights), the editing operations (add, remove,
# reweight, save), the polyglot byte format (the standard Zobrist keys
# and move encodings), and the Tcl UI wiring (the editor window, the
# create-from-database dialog, the board position hook, the menu).
# ======================================================================

package require tcltest 2.5

namespace eval ::scidb::test::book {

variable ::scidb::test::book::testDir [file dirname [file normalize [info script]]]
variable ::scidb::test::book::tmpDir [file join $::scidb::test::book::testDir tmp-app book]

# ======================================================================
# Helpers
# ======================================================================

proc ::scidb::test::book::setup {} {
	variable tmpDir
	file mkdir $tmpDir
}

proc ::scidb::test::book::tempPath {stem ext} {
	variable tmpDir
	return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

# Three small but distinct games: 1. d4 (Capablanca wins), 1. d4
# (Lasker draws), 1. e4 (Alekhine loses as White).
proc ::scidb::test::book::makePgn {} {
	set path [tempPath games pgn]
	set fh [open $path w]
	puts $fh {[Event "London 1922"]}
	puts $fh {[Site "London"]}
	puts $fh {[Date "1922.??.??"]}
	puts $fh {[Round "1"]}
	puts $fh {[White "Capablanca"]}
	puts $fh {[Black "Tarrasch"]}
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Nbd7 1-0}
	puts $fh ""
	puts $fh {[Event "New York 1924"]}
	puts $fh {[Site "New York"]}
	puts $fh {[Date "1924.??.??"]}
	puts $fh {[Round "2"]}
	puts $fh {[White "Lasker"]}
	puts $fh {[Black "Reti"]}
	puts $fh {[Result "1/2-1/2"]}
	puts $fh ""
	puts $fh {1. d4 Nf6 2. c4 e6 3. Nc3 d5 4. Bg5 Be7 1/2-1/2}
	puts $fh ""
	puts $fh {[Event "Casablanca 1921"]}
	puts $fh {[Site "Casablanca"]}
	puts $fh {[Date "1921.??.??"]}
	puts $fh {[Round "3"]}
	puts $fh {[White "Alekhine"]}
	puts $fh {[Black "Bogoljubow"]}
	puts $fh {[Result "0-1"]}
	puts $fh ""
	puts $fh {1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 0-1}
	close $fh
	return $path
}

proc ::scidb::test::book::openDatabase {pgn} {
	::application::database::openBase .application $pgn no
	# let the switch settle (progress windows, board update)
	set ::scidb::test::book::settled 0
	after 300 {set ::scidb::test::book::settled 1}
	vwait ::scidb::test::book::settled
}

proc ::scidb::test::book::readFile {path} {
	set fh [open $path r]
	fconfigure $fh -translation binary
	set data [read $fh]
	close $fh
	return $data
}

# The moves of a probe result as {san weight learn} triples, in probe
# order (the heaviest move first).
proc ::scidb::test::book::probeList {handle fen} {
	set result {}
	foreach move [::scidb::book::probe $handle $fen] {
		lappend result [list [dict get $move san] [dict get $move weight] [dict get $move learn]]
	}
	return $result
}

# The encoded moves of the 16-byte records of a book file, in file order.
proc ::scidb::test::book::readMoves {path} {
	set data [readFile $path]
	set moves {}
	for {set i 0} {$i < [string length $data]} {incr i 16} {
		binary scan [string range $data $i [expr {$i + 15}]] H16H4 k m
		lappend moves $m
	}
	return $moves
}

# The entries of a table position -> move -> {count wins draws} at one
# position, as {san weight} pairs.
proc ::scidb::test::book::movesAt {entries fen} {
	set result {}
	foreach e $entries {
		if {[lindex $e 0] eq $fen} { lappend result [list [lindex $e 1] [lindex $e 2]] }
	}
	return $result
}

::scidb::test::book::setup

# ======================================================================
# The polyglot byte format: the standard Zobrist keys and move
# encodings, records sorted by key, weight and learn at their offsets.
# ======================================================================

variable ::scidb::test::book::start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

tcltest::test book-polyglot-bytes {the writer writes the standard polyglot format} -body {
	set path [tempPath bytes bin]
	::scidb::book::write $path [list \
		[list $::scidb::test::book::start e4 7 0] \
		[list $::scidb::test::book::start d4 3 0] \
		[list $::scidb::test::book::start Nf3 1 0] \
		]
	set data [readFile $path]
	list [string length $data] \
		[binary scan $data H16H4H4H8 key1 move1 weight1 learn1] \
		[binary scan [string range $data 16 end] H16H4H4H8 key2 move2 weight2 learn2] \
		[binary scan [string range $data 32 end] H16H4H4H8 key3 move3 weight3 learn3] \
		$key1 $move1 $weight1 $learn1 \
		$move2 $weight2 $move3 $weight3
} -result {48 4 4 4 463b96181691fc9c 0195 0001 00000000 02db 0003 031c 0007}

tcltest::test book-polyglot-castling {castling is written as the king moving two squares} -body {
	set fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
	set path [tempPath castling bin]
	::scidb::book::write $path [list [list $fen O-O 5] [list $fen O-O-O 3] [list $fen Rf1 1]]
	# O-O = e1g1 = 0x0106, O-O-O = e1c1 = 0x0102, Rf1 = h1f1 = 0x01c5
	lsort [readMoves $path]
} -result {0102 0106 01c5}

tcltest::test book-polyglot-promotion {promotions carry the piece in bits 12-14} -body {
	set fen "7k/P7/8/8/8/8/8/K7 w - - 0 1"
	set path [tempPath promo bin]
	::scidb::book::write $path [list [list $fen a8=Q 2] [list $fen a8=R 1]]
	# a7a8Q = 0x4c38, a7a8R = 0x3c38
	lsort [readMoves $path]
} -result {3c38 4c38}

tcltest::test book-polyglot-duplicates {a position and move written twice keeps the heaviest entry} -body {
	set path [tempPath dup bin]
	::scidb::book::write $path [list \
		[list $::scidb::test::book::start d4 3 0] \
		[list $::scidb::test::book::start d4 9 0] \
		[list $::scidb::test::book::start d4 1 0] \
		]
	set h [::scidb::book::open $path]
	set result [probeList $h $::scidb::test::book::start]
	::scidb::book::close $h
	list [llength $result] $result [file size $path]
} -result {1 {{d4 9 0}} 16}

tcltest::test book-polyglot-empty {an empty entry list writes an empty (valid) book} -body {
	set path [tempPath empty bin]
	::scidb::book::write $path {}
	set h [::scidb::book::open $path]
	list [file size $path] [::scidb::book::count $h] [::scidb::book::probe $h $::scidb::test::book::start]
} -cleanup {
	::scidb::book::close $h
} -result {0 0 {}}

# ======================================================================
# Round trip: write with the editor's writer, read back with the
# existing reader; the same moves, weights and learn values.
# ======================================================================

tcltest::test book-roundtrip {write and read back give the same moves and weights} -body {
	set start $::scidb::test::book::start
	set aftere4 "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
	set cast "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
	set promo "7k/P7/8/8/8/8/8/K7 w - - 0 1"
	set path [tempPath roundtrip bin]
	::scidb::book::write $path [list \
		[list $start e4 7 65537] \
		[list $start d4 3] \
		[list $start Nf3 1] \
		[list $aftere4 e5 5] \
		[list $cast O-O 5] \
		[list $cast O-O-O 3] \
		[list $cast Rf1 1] \
		[list $promo a8=Q 2] \
		[list $promo a8=R 1] \
		]
	set h [::scidb::book::open $path]
	list [::scidb::book::count $h] \
		[probeList $h $start] \
		[probeList $h $aftere4] \
		[probeList $h $cast] \
		[probeList $h $promo]
} -cleanup {
	::scidb::book::close $h
} -result {9 {{e4 7 65537} {d4 3 0} {Nf3 1 0}} {{e5 5 0}} {{O-O 5 0} {O-O-O 3 0} {Rf1 1 0}} {{a8=Q 2 0} {a8=R 1 0}}}

# ======================================================================
# Editing: add, remove, reweight, save; reopen shows the same book.
# ======================================================================

tcltest::test book-editing {add, reweight and remove a move, save, and read it back} -body {
	set start $::scidb::test::book::start
	set path [tempPath edit bin]
	::scidb::book::write $path [list \
		[list $start e4 7] \
		[list $start d4 3] \
		[list $start Nf3 1] \
		]
	set h [::scidb::book::open $path]
	set beforeEdit [list [::scidb::book::count $h] [::scidb::book::modified $h]]
	# add a new move
	::scidb::book::add $h $start c2c4 2
	# reweight an existing one
	::scidb::book::reweight $h $start e4 9
	# update through add (weight and learn)
	::scidb::book::add $h $start d4 4 5
	# remove one
	set removed [::scidb::book::remove $h $start g1f3]
	set missing [::scidb::book::remove $h $start g1f3]
	set before [probeList $h $start]
	list $beforeEdit [::scidb::book::count $h] [::scidb::book::modified $h] $removed $missing $before \
		[::scidb::book::save $h] [::scidb::book::modified $h] \
		[file size $path]
} -cleanup {
	::scidb::book::close $h
} -result {{3 0} 3 1 1 0 {{e4 9 0} {d4 4 5} {c4 2 0}} 1 0 48}

tcltest::test book-editing-persisted {a saved book reads back the same through a fresh handle} -body {
	set start $::scidb::test::book::start
	set path [tempPath persisted bin]
	::scidb::book::write $path [list [list $start e4 7] [list $start d4 3]]
	set h [::scidb::book::open $path]
	::scidb::book::add $h $start Nf3 1
	::scidb::book::reweight $h $start d4 6
	::scidb::book::remove $h $start e2e4
	::scidb::book::save $h
	::scidb::book::close $h
	# a fresh handle: the reader must see the saved book
	set h2 [::scidb::book::open $path]
	list [::scidb::book::count $h2] [probeList $h2 $start]
} -cleanup {
	::scidb::book::close $h2
} -result {2 {{d4 6 0} {Nf3 1 0}}}

# Regression: saving twice to the same file on the same open handle, then
# reopening. On Windows Book::save() used to reopen the file for writing
# while the book's memory mapping still held an exclusive handle
# (CreateFile with no sharing), so the write failed with a sharing
# violation -> IO-Error Open_Failed "cannot write file". The fix releases
# the mapping before writing; Linux never noticed because mmap does not
# lock the file. The first save() of an already non-empty book and the
# second save() after an edit are both exercised here.
tcltest::test book-save-twice {saving twice to the same open handle works and reopens} -body {
	set start $::scidb::test::book::start
	set path [tempPath savetwice bin]
	# a non-empty book: opening it establishes the file mapping that save
	# has to let go of before it rewrites the file
	::scidb::book::write $path [list [list $start e4 7] [list $start d4 3]]
	set h [::scidb::book::open $path]
	# first save on the open handle: rewrites the model and re-establishes
	# the mapping on the new file
	set save1 [::scidb::book::save $h]
	# edit, then save again to the same handle: the second write must not
	# collide with the mapping from the first save
	::scidb::book::add $h $start Nf3 1
	set modified [::scidb::book::modified $h]
	set save2 [::scidb::book::save $h]
	set afterSave [::scidb::book::modified $h]
	set size [file size $path]
	::scidb::book::close $h
	# reopen: a fresh handle must see both saves' result
	set h2 [::scidb::book::open $path]
	set count [::scidb::book::count $h2]
	set at [probeList $h2 $start]
	::scidb::book::close $h2
	list $save1 $modified $save2 $afterSave $size $count $at
} -result {1 1 1 0 48 3 {{e4 7 0} {d4 3 0} {Nf3 1 0}}}

tcltest::test book-second-handle {saving preserves another handle's unsaved model} -body {
	set start $::scidb::test::book::start
	set path [tempPath second bin]
	::scidb::book::write $path [list [list $start e4 7]]
	set h [::scidb::book::open $path]
	set h2 [::scidb::book::open $path]
	::scidb::book::add $h2 $start d4 3
	::scidb::book::add $h $start Nf3 2
	set saved [::scidb::book::save $h]
	set other [probeList $h2 $start]
	set dirty [::scidb::book::modified $h2]
	::scidb::book::write $path [list [list $start c4 9]]
	set h3 [::scidb::book::open $path]
	list $saved $other $dirty [probeList $h $start] [probeList $h3 $start] [file exists "$path.tmp"]
} -cleanup {
	foreach handle [list $h $h2 $h3] { catch {::scidb::book::close $handle} }
} -result {1 {{e4 7 0} {d4 3 0}} 1 {{e4 7 0} {Nf3 2 0}} {{c4 9 0}} 0}

tcltest::test book-rename-failure {failed replacement raises WriteFailed and removes temporary file} -body {
	set path [tempPath renamefail bin]
	file mkdir $path
	set failed [catch {::scidb::book::write $path [list [list $::scidb::test::book::start e4 1]]} msg]
	list $failed [string match {*WriteFailed*} $msg] [file isdirectory $path] [file exists "$path.tmp"]
} -cleanup {
	file delete -force $path
} -result {1 1 1 0}

tcltest::test book-save-rename-failure {failed save keeps edits for retry} -body {
	set start $::scidb::test::book::start
	set path [tempPath savefail bin]
	::scidb::book::write $path [list [list $start e4 7]]
	set h [::scidb::book::open $path]
	::scidb::book::add $h $start d4 3
	file delete $path
	file mkdir $path
	set failed [catch {::scidb::book::save $h} msg]
	set result [list $failed [string match {*WriteFailed*} $msg] [file exists "$path.tmp"] [::scidb::book::modified $h]]
	file delete $path
	lappend result [::scidb::book::save $h]
	set h2 [::scidb::book::open $path]
	lappend result [probeList $h2 $start]
	set result
} -cleanup {
	catch {::scidb::book::close $h}
	catch {::scidb::book::close $h2}
} -result {1 1 0 1 1 {{e4 7 0} {d4 3 0}}}

tcltest::test book-editing-readonly {a read-only book refuses to save} -body {
	set path [tempPath readonly bin]
	::scidb::book::write $path [list [list $::scidb::test::book::start e4 1]]
	file attributes $path -permissions 0444
	set h [::scidb::book::open $path]
	list [::scidb::book::readonly $h] [::scidb::book::add $h $::scidb::test::book::start d2d4 1] \
		[::scidb::book::save $h] [::scidb::book::modified $h]
} -cleanup {
	file attributes $path -permissions 0644
	::scidb::book::close $h
} -result {1 1 0 1}

# ======================================================================
# The pure helpers of the book creation.
# ======================================================================

tcltest::test book-helpers {weights, shares and score modes} -body {
	list \
		[::book::weightFromCounts 3 2 1 frequency] \
		[::book::weightFromCounts 3 2 1 score] \
		[::book::weightFromCounts 1 0 0 score] \
		[::book::weightFromCounts 0 0 0 score] \
		[::book::sharePercent 3 7] \
		[::book::sharePercent 0 7] \
		[::book::sharePercent 7 0] \
		[::book::SideToMove {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}] \
		[::book::SideToMove {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1}] \
		[::book::MoveScore 1-0 w] [::book::MoveScore 1-0 b] \
		[::book::MoveScore 0-1 w] [::book::MoveScore 1/2-1/2 b] [::book::MoveScore * w]
} -result {3 3 1 1 43% 0% 0% w b win loss loss draw {}}

tcltest::test book-entries-from-games {aggregated table entries with min games and weight modes} -body {
	set table [dict create \
		fen1 {d4 {2 1 1} e4 {1 0 0} Nf3 {2 0 2}} \
		fen2 {c4 {1 1 0} e6 {1 0 1}} \
		]
	list \
		[lsort [::book::entriesFromGames $table 1 frequency]] \
		[lsort [::book::entriesFromGames $table 2 frequency]] \
		[lsort [::book::entriesFromGames $table 2 score]]
} -result {{{fen1 Nf3 2 0} {fen1 d4 2 0} {fen1 e4 1 0} {fen2 c4 1 0} {fen2 e6 1 0}} {{fen1 Nf3 2 0} {fen1 d4 2 0}} {{fen1 Nf3 1 0} {fen1 d4 2 0}}}

# ======================================================================
# Creating a book from a database: the aggregation of the games, and
# the round trip through ::scidb::book::write and the reader.
# ======================================================================

variable ::scidb::test::book::pgn [::scidb::test::book::makePgn]
::scidb::test::book::openDatabase $::scidb::test::book::pgn

tcltest::test book-game-numbers {all games of the database, or the rows of a view} -body {
	set base $::scidb::test::book::pgn
	set all [::book::gameNumbers $base Normal {}]
	set view [::scidb::view::new $base Normal unused unused unused unused master slave]
	::scidb::view::setGames $base Normal $view {0 2}
	set inView [::book::gameNumbers $base Normal $view]
	::scidb::view::close $base Normal $view
	list $all $inView
} -result {{0 1 2} {0 2}}

tcltest::test book-collect-entries {the creation aggregates the games' first plies} -body {
	set base $::scidb::test::book::pgn
	set numbers [::book::gameNumbers $base Normal {}]
	set entries [::book::collectEntries $base Normal $numbers 4 1 frequency]
	# d4 was played in two games (one won by White, one drawn), e4 in one lost one
	list [llength $entries] [lsort [movesAt $entries $::scidb::test::book::start]] \
		[movesAt [::book::collectEntries $base Normal $numbers 4 2 frequency] \
			$::scidb::test::book::start] \
		[lsort [movesAt [::book::collectEntries $base Normal $numbers 4 1 score] \
			$::scidb::test::book::start]]
} -result {11 {{d4 2} {e4 1}} {{d4 2}} {{d4 2} {e4 1}}}

tcltest::test book-create-roundtrip {the created book reads back with the same moves and weights} -body {
	set base $::scidb::test::book::pgn
	set start $::scidb::test::book::start
	set numbers [::book::gameNumbers $base Normal {}]
	set entries [::book::collectEntries $base Normal $numbers 4 1 frequency]
	set path [tempPath created bin]
	::scidb::book::write $path $entries
	set h [::scidb::book::open $path]
	list [::scidb::book::count $h] [probeList $h $start] [file size $path]
} -cleanup {
	::scidb::book::close $h
} -result {11 {{d4 2 0} {e4 1 0}} 176}

# ======================================================================
# The Tcl UI wiring: the editor window, its buttons and the dialog.
# ======================================================================

tcltest::test book-ui-wiring {the editor is reachable from the registry and follows the board} -body {
	# Decision 003: the drop-down is generated from the action registry, so
	# the entry point is the registered action, not text in ::menu::build.
	catch { destroy .booktestmenu }
	menu .booktestmenu
	::menu::BuildDropdown .booktestmenu
	set rec [::action::get menu.tools.book]
	set result [list \
		[llength [info commands ::book::openEditor]] \
		[expr {[dict get $rec label] eq [::menu::MC OpeningBookEditor]}] \
		[expr {[dict get $rec dropdown] ne ""}] \
		[string match {*::book::positionChanged*} [info body ::application::board::update]]]
	destroy .booktestmenu
	set result
} -result {1 1 1 1}

tcltest::test book-ui-editor {the editor window shows, edits and saves the book moves} -body {
	set start $::scidb::test::book::start
	set path [tempPath ui bin]
	::scidb::book::write $path [list [list $start e4 7] [list $start d4 3] [list $start Nf3 1]]

	set dlg [::book::openEditor .application]
	set tree $dlg.top.moves.list.tree
	::book::OpenHandle $path

	# load a game and follow its position: the board at the start position
	set curpos [::scidb::game::current]
	::scidb::game::load $curpos $::scidb::test::book::pgn Normal 0
	::scidb::game::go start
	::book::Refresh

	set rows {}
	foreach id [$tree children {}] {
		lappend rows [list $id [$tree set $id weight] [$tree set $id share]]
	}

	# reweight the selected move
	$tree selection set d4
	::book::SelectionChanged
	set ::book::Priv(weight) 12
	::book::SetWeight

	# delete a move
	$tree selection set Nf3
	::book::SelectionChanged
	::book::DeleteMove

	# add the move just played: go to after 1. d4 d5 2. c4
	::scidb::game::go start
	::scidb::game::position forward
	::scidb::game::position forward
	::scidb::game::position forward
	lassign [::book::LastMove] san fenBefore
	::book::AddLastMove
	::book::Save

	set handle $::book::Priv(handle)
	set unsaved [::scidb::book::modified $handle]
	::scidb::book::close $handle
	set ::book::Priv(handle) {}
	set ::book::Options(file) ""

	# the reader sees the saved book
	set h2 [::scidb::book::open $path]
	set atStart [probeList $h2 $start]
	set atBefore [probeList $h2 $fenBefore]
	::scidb::book::close $h2
	list $rows $unsaved $atStart $atBefore
} -cleanup {
	catch { ::scidb::game::go start }
	catch { ::book::Close }
} -result {{{e4 7 64%} {d4 3 27%} {Nf3 1 9%}} 0 {{d4 12 0} {e4 7 0}} {{c4 12 0}}}

tcltest::test book-ui-create-dialog {Create Book from Database writes the aggregated book} -body {
	set path [tempPath uidialog bin]
	set parent [::book::openEditor .application]
	set dlg [::book::CreateDialog $parent]
	set ::book::${dlg}::Vars(file) $path
	set ::book::${dlg}::Vars(plies) 4
	::book::CreateStart $dlg
	set entries [file size $path]
	set handle $::book::Priv(handle)
	# the editor switched to the new book
	set atStart [probeList $handle $::scidb::test::book::start]
	::book::Save
	::scidb::book::close $handle
	set ::book::Priv(handle) {}
	set ::book::Options(file) ""
	# and the reader reads it back
	set h2 [::scidb::book::open $path]
	set readBack [probeList $h2 $::scidb::test::book::start]
	::scidb::book::close $h2
	list $entries $atStart $readBack
} -cleanup {
	catch { destroy $dlg }
	catch { ::book::Close }
} -result {176 {{d4 2 0} {e4 1 0}} {{d4 2 0} {e4 1 0}}}

# Regression (G03): writing a book while it is open in the editor must
# not fail with a sharing violation. On Windows the memory mapping holds
# an exclusive handle; the fix closes the handle before writing and
# reopens after. Also exercises rewrite and delete of an open book.
# Note: Linux does not enforce the same file locking as Windows, so this
# test verifies the close/write/reopen logic but cannot reproduce the
# original Windows-only sharing violation. The laptop loop should retest
# on real Windows hardware.
tcltest::test book-write-while-open {write to a book file that is open in the editor succeeds} -body {
	set start $::scidb::test::book::start
	set path [tempPath writeopen bin]
	# Create an initial book and open it in the editor.
	::scidb::book::write $path [list [list $start e4 5] [list $start d4 3]]
	::book::OpenHandle $path
	set handleBefore $::book::Priv(handle)
	set countBefore [::scidb::book::count $handleBefore]
	# Now create a new book at the SAME path via CreateStart (the path
	# that failed on Windows with %IO-Error% OpenFailed).
	set parent [::book::openEditor .application]
	set dlg [::book::CreateDialog $parent]
	set ::book::${dlg}::Vars(file) $path
	set ::book::${dlg}::Vars(plies) 4
	::book::CreateStart $dlg
	# After CreateStart the editor should have reopened the book.
	set handleAfter $::book::Priv(handle)
	set countAfter [::scidb::book::count $handleAfter]
	set atStart [probeList $handleAfter $start]
	# Rewrite via NewBook path (also had the same issue).
	set ::book::Priv(handle) $handleAfter
	set ::book::Options(file) $path
	set ::book::Priv(file) [file normalize $path]
	# Direct write while open: should succeed with the temp+rename fix.
	::scidb::book::write $path [list [list $start Nf3 8]]
	# Reopen to verify the content.
	catch { ::scidb::book::close $handleAfter }
	set ::book::Priv(handle) {}
	set h3 [::scidb::book::open $path]
	set finalCount [::scidb::book::count $h3]
	set finalAt [probeList $h3 $start]
	::scidb::book::close $h3
	# Clean up the temp file if any was left behind.
	catch { file delete "$path.tmp" }
	list $countBefore $countAfter $atStart $finalCount $finalAt
} -cleanup {
	catch { destroy $dlg }
	catch { ::book::Close }
	catch { file delete $path }
	catch { file delete "$path.tmp" }
} -result {2 11 {{d4 2 0} {e4 1 0}} 1 {{Nf3 8 0}}}

# leave the app tidy for the next test file. Close the base the low-level
# way: closeBase would ask about the still open game (a modal dialog,
# which blocks the headless test run).
catch { $::application::database::Vars(switcher) remove $::scidb::test::book::pgn }
catch { ::scidb::db::close $::scidb::test::book::pgn }
# Free one game slot so the app's nine-slot pool is not full for the files
# after this one: test_app_convert's database copy needs a scratch game and
# fails with a bare "Clipbase" error when every slot is taken.  Do not call
# ::scidb::game::new here (as this file used to): it allocates a slot rather
# than freeing one.  Release through both bookkeeping layers -- the gamebar
# row and the game slot -- or the gamebar's digit badges (1..9) desynchronise.
foreach ::scidb::test::book::slot {8 7 6 5 4 3 2 1 0} {
	if {[lindex [::game::gameList] $::scidb::test::book::slot 0] ne ""} {
		catch { ::application::pgn::release $::scidb::test::book::slot }
		catch { ::game::release $::scidb::test::book::slot }
		break
	}
}
unset -nocomplain ::scidb::test::book::slot

} ;# namespace eval ::scidb::test::book

tcltest::cleanupTests

# vi:set ts=3 sw=3:
