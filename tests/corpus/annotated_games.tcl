# ======================================================================
# Annotated-game display corpus
# ======================================================================
# Adversarial PGN inputs for auditing the annotated-game display pipeline
# (edit-node layout, comment/NAG/mark/variation rendering).  Sourced by
# test_app_annotated_display.tcl; writeCorpusPgn emits them as one .pgn
# file for manual loading or database-level import tests.

namespace eval ::scidb::test::corpus {

variable annotated

# ChessBase-style command tags, NAG spectrum, deep nesting, diagram NAG $220.
set annotated(chessbase) {[Event "Annotation audit: ChessBase style"]
[Site "?"]
[Date "2026.09.06"]
[Round "1"]
[White "Annotator"]
[Black "Tester"]
[Result "1-0"]

{Pre-game comment with [%csl Gd4,Re5] squares and [%cal Ge2e4] arrow.}
1. e4 $1 {Good start [%clk 0:05:00]} e5 $6 (1... c5 $5 {Sicilian
[%eval -0.30]} 2. Nf3 d6 (2... Nc6 3. d4 {deep} (3. Bb5 {deeper}
3... g6 (3... a6 $2)))) 2. Nf3 $14 $36 Nc6 3. Bb5 $220 a6
{[%emt 0:00:30] after think} 4. Ba4 Nf6 5. O-O $10 $13 1-0}

# Scid-native graphical annotation syntax.
set annotated(scid) {[Event "Annotation audit: Scid style"]
[Site "?"]
[Date "2026.09.06"]
[Round "2"]
[White "Annotator"]
[Black "Tester"]
[Result "1/2-1/2"]

1. d4 {[%draw full,d4,green][%draw arrow,d1,d4,red] center pawn} d5
2. c4 {[%mark c4] gambit} e6 3. Nc3 Nf6 1/2-1/2}

# Unicode comments, NAG pile-up (7 max), promotion/underpromotion, mate.
set annotated(unicode) {[Event "Annotation audit: unicode + edge cases"]
[Site "?"]
[Date "2026.09.06"]
[Round "3"]
[White "Annotator"]
[Black "Tester"]
[Result "1-0"]

{Многоязычный комментарий — 中文注释 — Ünïcödé ♞♛ test}
1. f4 $1 $14 $36 $40 $44 $132 $140 e5 2. fxe5 f6 3. exf6 gxf6
{comment before a quiet move} 4. Nf3 $22 1-0}

proc writeCorpusPgn {path} {
	variable annotated
	set out {}
	foreach key {chessbase scid unicode} {
		append out $annotated($key) \n\n
	}
	set chan [open $path w]
	fconfigure $chan -encoding utf-8
	puts -nonewline $chan $out
	close $chan
	return $path
}

} ;# namespace ::scidb::test::corpus
