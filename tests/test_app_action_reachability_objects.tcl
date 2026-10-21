# Data-dependent companion to the fresh-start audit. Each case owns a HOME,
# generated native database and process. No private database or handler stub.
package require tcltest 2.5
set ::env(SCIDB_REACHABILITY_LIBRARY) 1
source [file join [file dirname [info script]] test_app_action_reachability.tcl]
unset ::env(SCIDB_REACHABILITY_LIBRARY)
namespace eval ::scidb::test::objects {
    variable root [file dirname [file dirname [file normalize [info script]]]]
    variable dir [file join $root tests tmp-app object-audit-[pid]]
    variable skips {
        c4.save_changes {native SCI edits are saved immediately; no dirty PGN save object exists in the native fixture}
        c11.classify_comment {requires a configured language/model service; no network in this fixture}
        c11.detect_language {requires a configured language/model service; no network in this fixture}
        c11.draft_comment {requires a configured language/model service; no network in this fixture}
        c11.explain_comment {requires a configured language/model service; no network in this fixture}
        c2.explain_move {requires a configured language/model service; no network in this fixture}
        c3.ask_about_game {requires a configured language/model service; no network in this fixture}
        c6.explain_line {requires a configured language/model service; no network in this fixture}
        c2.add_variation {requires a pending alternative move; fixture object is an already-played move}
        c2.exchange_move {requires a pending alternative move; fixture object is an already-played move}
        c2.new_main_line {requires a pending alternative move; fixture object is an already-played move}
        c2.replace_move {requires a pending alternative move; fixture object is an already-played move}
        c2.load_continuation {requires a selected continuation search result; fixture supplies a notation move}
        c2.strip.language {requires a selected language submenu item; fixture comment is untagged xx}
        c12.save.line {requires a repertoire destination; generated tournament base is Unspecific}
        c12.save.repertoire {requires a repertoire destination; generated tournament base is Unspecific}
        c8.save_line {requires a repertoire destination; generated tournament base is Unspecific}
        c3.open_url {opens an external browser/player; no external applications in headless audit}
        c5.event_url {opens an external browser/player; no external applications in headless audit}
        c5.site_url {opens an external browser/player; no external applications in headless audit}
        c7.external {opens an external browser/player; no external applications in headless audit}
        c5.insights {capability insights is absent; no insights backend is shipped}
        c6.add_sequence {requires an end-of-line position; fixture deliberately remains mid-game}
        c9.assistant.cloud {requires a configured provider; fixture has no local/cloud model service}
        c9.assistant.local {requires a configured provider; fixture has no local/cloud model service}
        c9.explorer.tablebase {requires online tablebase service; no network in this fixture}
        c9.report.family {requires an HTML report header; the C9 fixture selects the notation pane}
        c9.report.print {requires an HTML report header; the C9 fixture selects the notation pane}
        c9.report.size {requires an HTML report header; the C9 fixture selects the notation pane}
        c9.report.zoom {requires an HTML report header; the C9 fixture selects the notation pane}
    }
    proc cases {} {
        set cases {}
        foreach {kind ids} {
            board {c1.set_start_board c1.set_start_position c1.start.standard c1.start.chess960 c1.start.symm960 c1.start.shuffle c1.start.setup c1.board_setup c1.copy_fen c1.copy_diagram c1.edit_annotation c1.flip_board c1.insert_null}
            move {c2.try_variation c2.annot.prefix c2.annot.infix c2.annot.suffix c2.import_game c2.import_variation c2.promote_variation c2.remove_variation c2.comment_after c2.comment_before c2.marks_palette c2.move_info c2.insert_diagram c2.insert_diagram_black c2.strip.moves c2.strip.truncate c2.strip.variations c2.strip.annotations c2.strip.info c2.strip.marks c2.strip.comments c2.copy_comments c2.undo c2.redo c2.collapse c2.expand}
            game {c3.sort.column c3.sort.asc c3.sort.desc c3.paste_games c3.merge c3.load c3.browse c3.overview c3.tournament c3.games_like c3.edit_characteristics c3.delete c3.copy_game}
            database {c4.new.scid c4.new.pgn c4.close c4.open_new_tab c4.download_games c4.import.pgn c4.open_database c4.help c4.maintenance.compact c4.export.pgn c4.symbol.small c4.symbol.normal c4.symbol.large c4.properties c4.readonly c4.search.current c4.reports.opening}
            player {c5.player_card c5.prep_report}
            site {c5.open_switcher c5.save_working_set}
            event {c5.event_table}
            engine {c6.add_move c6.add_line c6.add_all c6.add_merge c6.add_include c6.insert_comment c6.copy_line c6.copy_fen c6.pause_resume c6.close_engine c6.lock_engine c6.opponents_view c6.best_first c6.multi.1 c6.multi.2 c6.multi.3 c6.multi.4 c6.multi.5 c6.multi.6 c6.multi.7 c6.multi.8 c6.lines.1 c6.lines.2 c6.lines.3 c6.lines.4 c6.setup_engine c6.setup_eval_edges c9.analysis.setup c9.analysis.best c9.analysis.opponents}
            pane {c9.board_setup c9.not.configure c9.not.font_reset c9.stay_on_top c9.hide_leaving c9.maximise c9.fold c9.amalgamate c9.float c9.docking c9.close c9.flip_board c9.not.font_inc c9.not.font_dec c9.not.spacing c9.not.numbering c9.not.markers c9.not.diagrams c9.not.emoticons}
            assistant {c9.assistant.clear c9.assistant.model}
            tree {c8.start_search c8.move_actions c8.analyze c8.highlight c9.tree.automatic c9.tree.novelties c8.search.exact c8.search.slow c8.search.fast c8.automatic c8.inside_variations c8.lock_reference c8.reference.none c8.copy_line c8.opening_report}
            media {c7.open_stream c9.media.show c9.media.stream c7.play c7.open_report c7.show_in_board c7.sync.position c7.sync.timeline}
            column {c10.fill_column c10.hide c10.auto_stretch c10.optimize c10.fit c10.squeeze c10.configure}
            comment {c11.undo c11.redo c11.revert c11.display_emoticons c11.copy c11.cut c11.paste c11.select_all c11.clear}
            tab {c12.remove_history c12.merge.game c12.new.standard c12.new.chess960 c12.import_game c12.paste.game c12.paste.variation c12.save.replace c12.save.replace_moves c12.save.new c12.clear_history c12.close_tab c12.load_number c12.reload c12.copy_game c12.copy_clipboard c12.export}
        } {
            foreach id $ids {
                lappend cases [list $id {} $kind]
            }
        }
        for {set n 1} {$n <= 19} {incr n} { lappend cases [list c3.flag.$n {} game] }
        return $cases
    }
    proc noLinks {path} {
        if {[file type $path] eq {link}} { error "fixture contains a symlink: $path" }
        if {[file isdirectory $path]} {
            foreach child [glob -nocomplain -directory $path * .*] {
                if {[file tail $child] ni {. ..}} { noLinks $child }
            }
        }
    }
    proc nop {args} { return 0 }
    proc confirm {what} { return 1 }
    proc tool {id {argv {}}} {
        set reply [::action::run $id $argv]
        if {[string match -nocase error:* $reply]} { error "$id: $reply" }
        return $reply
    }
    proc setup {id kind} {
        variable dir
        variable object
        variable base [file join $dir scratch.sci]
        file mkdir $dir
        set ::application::assistant::Priv(confirm) [namespace current]::confirm
        set ::action::ConfirmHook [namespace current]::confirm
        set ::action::BulkHook [namespace current]::confirm
        # Exercise the real fact/report pipeline without a network provider.
        set ::application::ai::Config(provider) stub
        ::ai::provider::configure -name stub -chatResponses [list {}]
        set pgn [file join $dir generated.pgn]
        set f [open $pgn w]
        # TWIC-style tags, several rounds, names and results, wholly synthetic.
        for {set n 1} {$n <= 8} {incr n} {
            puts $f "\[Event \"Generated Open\"\]\n\[Site \"Fixture City\"\]\n\[Date \"2026.10.01\"\]\n\[Round \"$n\"\]\n\[White \"Fixture, Alice\"\]\n\[Black \"Fixture, Bob$n\"\]\n\[WhiteElo \"2400\"\]\n\[BlackElo \"2350\"\]\n\[Result \"1-0\"\]\n"
            puts $f {1. e4 e5 2. Nf3 Nc6 3. Bb5 $1 {Fixture comment. [%clk 0:10:00] [%csl Re4]} (3. Bc4 Nf6) a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 1-0}
            puts $f {}
        }
        close $f
        ::scidb::db::open $pgn [namespace current]::nop {} [namespace current]::nop {}
        ::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
        ::scidb::db::attach $base $base
        ::scidb::db::copy $pgn $base {} [namespace current]::nop {} [namespace current]::nop {}
        ::scidb::db::save $base [namespace current]::nop {}
        ::scidb::db::close $base
        ::scidb::db::close $pgn
        # The immutable control is a byte-for-byte COPY, never a symlink.
        variable control {}
        foreach path [glob [file rootname $base].*] {
            file copy $path $path.control
            dict set control $path [bytes $path.control]
        }
        tool open_database [list path $base]
        tool open_game {number 1 move 3 after white}
        update
        variable slot [::scidb::game::current]
        tool switch_tab {tab database}
        update
        set twm $::application::database::Vars(games).twm
        set table [set ::application::database::games::${twm}::Priv(table)]
        set object [dict create base $base variant Normal index 0 view 0 parent .application \
            position $slot gameSlot $slot id $slot ply 5 san Bb5 fen [::scidb::pos::fen] \
            square e4 widget $::application::board::Vars(widget:frame) path $table table $table column white sortable 1]
        if {$kind eq {player}} { dict set object kind player; dict set object name {Fixture, Alice} }
        if {$kind eq {event}} { dict set object kind event; dict set object name {Generated Open} }
        if {$kind eq {site}} { dict set object kind site; dict set object name {Fixture City} }
        if {$kind eq {engine}} {
            set program [file join $::scidb::test::objects::root tests fixtures fake-uci-engine.tcl]
            if {[info exists ::env(SCIDB_TEST_ENGINE)]} { set program $::env(SCIDB_TEST_ENGINE) }
            # The fixture is copied to make executable without changing its mode.
            set input [open $program rb]
            set output [open [file join $dir engine] wb]
            fcopy $input $output
            close $input
            close $output
            file attributes [file join $dir engine] -permissions 0755
            set ::engine::Engines {}
            puts {OBJECT ENGINE install}; flush stdout
            # This fixture is a known UCI engine. Use the production protocol-
            # specific registration path instead of spending the whole WB
            # discovery timeout on every unrelated context-action probe.
            if {![::engine::ProbeNewEngine .application [list Command [file join $dir engine]] UCI]} {
                error {fixture did not answer the real UCI probe}
            }
            ::engine::SaveEngineList
            set name {}
            foreach entry $::engine::Engines {
                if {[dict get $entry Command] eq [file join $dir engine]} { set name [dict get $entry Name]; break }
            }
            if {$name eq {}} { error {installed fixture engine was not registered} }
            puts {OBJECT ENGINE start}; flush stdout
            set reply [tool start_engine [list engine $name lines 1 threads 1 hash 16]]
            regexp {analysis pane (\d+)} $reply -> number
            puts "OBJECT ENGINE started: $reply"; flush stdout
            set tree $::application::analysis::NumberToTree($number)
            set deadline [expr {[clock milliseconds]+10000}]
            while {[lindex [lindex [::application::analysis::BestLine $tree] 1] 8] eq {}} {
                update; after 20
                if {[clock milliseconds]>$deadline} { error {engine produced no analysis line} }
            }
            lassign [::application::analysis::BestLine $tree] row line
            dict set object tree $tree
            dict set object number $number
            dict set object engine [::engine::id $number]
            dict set object lineId $row
            dict set object pv [lindex $line 8]
            if {$id eq {c6.copy_line}} {
                # Use the actual popup object: TreeCtrl item IDs start at 1,
                # but engine lines are zero-based visible row numbers.
                lassign [$tree item bbox Line$row] x y right bottom
                ::application::analysis::PopupMenu $tree $number [expr {$x+4}] [expr {$y+4}]
                set menu $tree.__menu__
                set found 0
                for {set i 0} {$i <= [$menu index end]} {incr i} {
                    if {[$menu type $i] ne {command}} { continue }
                    set command [$menu entrycget $i -command]
                    if {[lindex $command 1] eq {c6.copy_line}} {
                        set popupObject [dict get [lindex $command 2] object]
                        if {[dict get $popupObject lineId] != $row || [dict get $popupObject pv] eq {}} { error {engine popup lost its selected line} }
                        set object [dict merge $object $popupObject]
                        set found 1
                        break
                    }
                }
                if {[tk windowingsystem] eq "aqua"} {
                    event generate $menu <<MenuUnpost>> -when now
                } else {
                    ::tk::MenuUnpost $menu
                }
                destroy $menu
                if {!$found} { error {engine popup has no Copy Line command} }
            }
        }
        if {$kind eq {pane}} {
            set layout [::application::twm board]
            dict set object paneUid editor
            dict set object frame [$layout leaf editor]
            dict set object twm $layout
        }
        if {$kind eq {tree}} {
            ::scidb::tree::set $base
            dict set object table $::application::tree::Vars(table)
            dict set object row 0
            dict set object move a6
            if {$id eq {c8.search.exact}} { set ::application::tree::Options(search:mode) fast }
            if {$id eq {c8.search.fast}} { set ::application::tree::Options(search:mode) slow }
        }
        if {$kind eq {media}} {
            set fixture [file join $::scidb::test::objects::root tests tmp-app media-test]
            foreach path [glob [file join $fixture MediaTest.*]] {
                noLinks $path
                file copy $path $dir
            }
            set media [file join $dir MediaTest.sci]
            tool open_database [list path $media]
            tool open_game {number 2 move 3 after white}
            set key [::scidb::game::position key]
            set comment [::scidb::misc::xml fromList [list [list {} [list [list str {Fixture media comment.}]]]]]
            ::scidb::game::update addcomment $key after $comment
            ::scidb::game::variation new d6
            ::application::media::Ensure
            ::application::media::Update [::scidb::game::current]
            update
            set tree $::application::media::Priv(tree)
            set rows [::application::media::MediaRows]
            if {![llength $rows]} { error {copied media fixture has no media rows} }
            set row [lindex $rows 0]
            foreach candidate $rows {
                lassign [$tree item $candidate -values] type title path index
                if {$id eq {c7.open_report} && [file extension $path] in {.htm .html}} { set row $candidate; break }
                if {$id eq {c7.play} && [file extension $path] in {.png .jpg .jpeg}} { set row $candidate; break }
            }
            lassign [$tree item $row -values] type title path index
            dict set object base $media
            dict set object mediaId $index
            dict set object path $path
            dict set object type $type
            dict set object title $title
        }
        if {$id eq {c2.expand}} { ::scidb::game::variation fold on }
        if {$id eq {c2.redo}} { ::scidb::game::strip comments; ::scidb::game::execute undo }
        if {$id eq {c2.undo}} { ::scidb::game::strip comments }
        if {$id eq {c3.load}} { dict set object index 1 }
        if {$id eq {c3.copy_game}} { ::scrolledtable::select $table [::scrolledtable::indexToRow $table 0] }
        if {$kind ni {column game}} { tool switch_tab {tab board} }
        if {$kind eq {column}} { dict set object table [::scrolledtable::table $table] }
        if {$id eq {c2.strip.marks}} { ::scidb::game::update marks [::scidb::game::position key] full red 28 28 }
        if {$id in {c2.promote_variation c2.remove_variation}} {
            ::scidb::game::go start
            ::scidb::game::go 4
            ::scidb::game::go variation 0
            ::scidb::game::go 1
        }
        if {$id eq {c6.multi.1}} { ::application::analysis::SetMultiPV [dict get $object tree] 2 }
        if {[string match c6.lines.* $id]} {
            set ::application::analysis::[dict get $object number]::Options(engine:nlines) [expr {[lindex [split $id .] end] == 1 ? 2 : 1}]
        }
        if {$id eq {c9.not.font_reset}} { ::context::PaneFont $object +1 }
        if {$id in {c9.stay_on_top c9.hide_leaving}} {
            ::twm::Undock [dict get $object twm] [dict get $object frame]
            update
        }
        if {$id eq {c10.fill_column}} { [dict get $object table].t column configure tail -visible no }
        if {$id in {c10.optimize c10.fit c10.squeeze}} {
            set tree [dict get $object table].t
            foreach column [$tree column list] {
                if {$column ne "tail"} { $tree column configure $column -width 500 -weight 0 }
            }
        }
        if {[string match c4.symbol.* $id]} { set ::database::switcher::Options(iconsize) [expr {$id eq "c4.symbol.small" ? 48 : 24}] }
        if {$id eq {c2.strip.info}} { ::scidb::game::update moveinfo [::scidb::game::position key] cclk {PT10M} }
        if {$id eq {c3.delete}} { ::gamestable::SortColumn $table black descending }
        if {$id eq {c3.paste_games}} { ::game::clipboard::copy $base Normal {1} }
        if {[string match c3.sort.* $id]} {
            dict set object column black
            ::gamestable::SortColumn $table black [expr {$id eq "c3.sort.desc" ? "ascending" : "descending"}]
        }
        if {$id in {c3.merge c12.merge.game}} {
            set second [::game::new .application -base $base -variant Normal -number 1]
            ::application::pgn::select $slot
            dict set object gameSlot $second
            dict set object id $second
            dict set object index 1
        }
        if {$id eq {c12.remove_history}} { dict set object historyIndex 0 }
        if {$kind eq {assistant}} {
            ::application::assistant::show
            set text $::application::assistant::Priv(text)
            $text configure -state normal
            $text insert end {Fixture conversation}
            $text configure -state disabled
        }
        if {$id in {c12.paste.game c12.paste.variation c2.import_game c2.import_variation}} {
            clipboard clear
            clipboard append {[Event "Inserted fixture"]
[White "Insert"]
[Black "Fixture"]
[Result "*"]

1. d4 d5 2. c4 *}
        }

        if {$id eq {c4.maintenance.compact}} { ::scidb::db::set delete 7 -1 $base Normal 1 }
        if {$id in {c12.reload c12.save.replace c12.save.replace_moves c12.save.new}} { ::annotation::addNag suffix 5 }
        return $object
    }
    proc texts {w} {
        set out {}
        foreach c [winfo children $w] {
            if {[winfo class $c] in {Text Comment}} { lappend out $c }
            lappend out {*}[texts $c]
        }
        return $out
    }
    proc bytes {path} { set f [open $path rb]; set b [read $f]; close $f; return $b }
    proc state {} {
        variable object
        set out [::scidb::test::reachability::snapshot]
        lappend out [::board::diagram::rotated? $::application::board::board]
        catch {lappend out marks [::scidb::game::query marks] annotation [::scidb::game::query annotation] info [::scidb::game::count info]}
        catch {lappend out trial [::game::trialMode?]}
        catch {lappend out bases [$::application::database::Vars(switcher) bases]}
        catch {lappend out history [::game::historyIsEmpty?]}
        catch {lappend out layout [[::application::twm board] inspect]}
        catch {lappend out folded [::scidb::game::variation folded? m-0.4.0]}
        catch {lappend out fen [::scidb::pos::fen] pgn [::scidb::game::toPGN [expr {[::scidb::game::query modified?] ? "modified" : "original"}]]}
        catch {lappend out clipboard [clipboard get]}
        foreach w [texts .] { catch {lappend out $w [$w get 1.0 end] [$w tag ranges sel]} }
        foreach name {::comment::Options ::pgn::editor::Options ::application::analysis::1::Options ::application::tree::Options ::application::twm::Options ::mediainset::Options ::mediasync::opts ::database::switcher::Options} {
            if {[array exists $name]} { lappend out $name [lsort -stride 2 -index 0 [array get $name]] }
        }
        if {[dict exists $object tree]} {
            set name ::application::analysis::[dict get $object tree]::Vars
            foreach key {engine:pause engine:locked engine:opponent engine:stopped} { catch {lappend out $key [set ${name}($key)]} }
        }
        if {[dict exists $object table]} {
            set table [dict get $object table]
            catch {lappend out columns [$table.t column list -visible]}
            if {[winfo exists $table.t]} {
                catch {lappend out tail-visible [$table.t column cget tail -visible]}
                foreach column [$table.t column list] {
                    foreach attr {-width -weight -visible} { catch {lappend out $column $attr [$table.t column cget $column $attr]} }
                }
            }
        }
        variable base
        variable control
        dict for {path expected} $control { catch {lappend out control-target $path [zlib crc32 [bytes $path]]} }
        foreach path [glob -nocomplain [file rootname $base].*] {
            if {[file extension $path] ne {.control}} { catch {lappend out disk $path [zlib crc32 [bytes $path]]} }
        }
        catch {lappend out count [::scidb::db::count games $base Normal]}
        catch {
            set deleted {}
            for {set row 0} {$row < [::scidb::db::count games $base Normal]} {incr row} {
                lappend deleted [::scidb::db::get deleted? $row -1 $base Normal]
            }
            lappend out deleted $deleted
        }
        catch {lappend out gameclipboard [::game::clipboard::entries]}
        catch {lappend out clipcount [::scidb::db::count games $::scidb::clipbaseName Normal]}
        catch {lappend out flags [::scidb::db::get gameInfo 0 0 $base Normal]}
        catch {lappend out readonly [::scidb::db::get readonly? $base]}
        return $out
    }
    proc exportFile {} {
        variable dir
        if {[winfo exists .application.export] && [winfo ismapped .application.export] && [grab current] eq {.application.export} && [info exists ::export::Info(fsbox)]} {
            ::export::DoExport .application .application.export [file join $dir exported.pgn]
        } elseif {![file exists [file join $dir exported.pgn]]} { after 100 [namespace current]::exportFile }
    }
    proc widgets {w} {
        set out [list $w]
        foreach c [winfo children $w] { lappend out {*}[widgets $c] }
        return $out
    }
    proc acceptDialogs {} {
        foreach w [::scidb::test::reachability::windows] {
            if {$w in $::scidb::test::reachability::baseline || ![winfo exists $w] || ![winfo ismapped $w]} { continue }
            foreach button [widgets $w] {
                if {[winfo class $button] ni {TButton Button}} { continue }
                if {[winfo name $button] in {yes ok bt-yes bt-ok} && [$button cget -state] ne {disabled}} { puts "OBJECT ACCEPT $button"; flush stdout; $button invoke; break }
            }
        }
        after 100 [namespace current]::acceptDialogs
    }
    proc chooseVariation {} {
        set m $::application::board::board.popup_confirm
        if {[winfo exists $m]} {
            $m invoke 1
            if {[tk windowingsystem] eq "aqua"} {
                event generate $m <<MenuUnpost>> -when now
            } else {
                ::tk::MenuUnpost $m
            }
        } else { after 100 [namespace current]::chooseVariation }
    }
    proc commentProbe {id} {
        variable object
        variable commentResult
        set w [set ::comment::Vars(widget:main)]
        set text $::comment::Vars(widget:text:$::comment::Vars(lang)).text
        dict set object widget $text
        if {$id ne {c11.select_all}} { $text tag add sel 1.0 end-1c }
        if {$id in {c11.undo c11.redo c11.revert}} {
            ::comment::SetUndoPoint $text
            $text insert end { edited}
            ::comment::SetUndoPoint $text
            if {$id eq {c11.redo}} { ::comment::EditUndo }
        }
        clipboard clear; clipboard append {Inserted fixture text}
        set code [catch {
            set result [probe $id comment]
            if {$id in {c11.cut c11.paste c11.clear}} {
                variable base
                variable control
                set beforeFiles {}
                dict for {path expected} $control { dict set beforeFiles $path [bytes $path] }
                set dlg $::comment::Vars(dialog)
                $dlg.apply invoke
                ::scidb::game::save $base Normal [concat {*}[::scidb::game::tags]] WhiteElo BlackElo [namespace current]::nop {} -replace 1
                ::scidb::db::save $base [namespace current]::nop {}
                set changed 0
                dict for {path expected} $beforeFiles { if {[bytes $path] ne $expected} { set changed 1 } }
                if {!$changed} { error "$id did not persist the edited scratch comment" }
                dict for {path expected} $control { if {[bytes $path.control] ne $expected} { error "$id changed the control" } }
            }
            set result
        } reply options]
        set commentResult [list $code $reply $options]
        # Discard editor changes through the actual Cancel command.
        set dlg $::comment::Vars(dialog)
        $dlg.cancel invoke
    }
    proc run {id kind} {
        if {$kind eq {comment}} {
            after 300 [list [namespace current]::commentProbe $id]
            ::application::pgn::editComment after
            variable commentResult
            lassign $commentResult code reply options
            if {$code} { return -options $options $reply }
            return $reply
        }
        return [probe $id $kind]
    }
    proc probe {id kind} {
        variable object
        variable control
        set ::scidb::test::reachability::baseline [::scidb::test::reachability::windows]
        set ::scidb::test::reachability::seen {}
        set ::scidb::test::reachability::nativeAccept 0
        set ::scidb::test::reachability::before [::scidb::test::reachability::snapshot]
        if {[string match c2.strip.* $id]} {
            variable base
            # The edited marks/info are part of the scratch fixture on disk
            # before stripping, so persistence is checked against that state.
            ::scidb::game::save $base Normal [concat {*}[::scidb::game::tags]] WhiteElo BlackElo [namespace current]::nop {} -replace 1
            ::scidb::db::save $base [namespace current]::nop {}
        }
        set filesBefore {}
        dict for {path expected} $control { dict set filesBefore $path [bytes $path] }
        set infoBefore [::scidb::game::count info]
        set before [state]
        set gameBefore {}
        catch {set gameBefore [::scidb::game::toPGN [expr {[::scidb::game::query modified?] ? "modified" : "original"}]]}
        set marksBefore [::scidb::game::query marks]
        if {$id eq {c1.insert_null} && [tk windowingsystem] ne "aqua"} {
            after 100 [list [namespace current]::chooseVariation]
        }
        if {$id in {c4.export.pgn c12.export}} { after 100 [namespace current]::exportFile }
        if {$id in {c12.reload c4.close c4.save_changes c5.save_working_set c4.maintenance.compact c12.save.replace c12.save.replace_moves c12.save.new}} {
            # Match this fixture's real Yes/OK driver at Aqua's OS boundary.
            set ::scidb::test::reachability::nativeAccept 1
            after 100 [list [namespace current]::acceptDialogs]
        } elseif {$id ni {c4.export.pgn c12.export}} { after 500 ::scidb::test::reachability::cancelDialogs }
        puts "OBJECT ACTION $id begin"; flush stdout
        set reply [::scidb::test::reachability::runAction [list tool $id [list object $object]]]
        puts "OBJECT ACTION $id returned"; flush stdout
        update
        if {$id in {c4.export.pgn c12.export}} {
            variable dir
            exportFile
            if {![file exists [file join $dir exported.pgn]] || [file size [file join $dir exported.pgn]] == 0} { error "$id did not export data" }
        }
        if {$id eq {c8.copy_line}} {
            if {[clipboard get] ne {e4 e5 Nf3 Nc6 Bb5 a6}} { error {Copy Line did not copy exactly the selected continuation} }
            set saved [::scidb::game::position key]
            ::scidb::game::go start
            ::scidb::game::go 4
            ::scidb::game::go variation 0
            ::scidb::game::go 1
            set variation $object
            dict set variation move Nf6
            set fen [::scidb::pos::fen]
            tool c8.copy_line [list object $variation]
            if {[clipboard get] ne {e4 e5 Nf3 Nc6 Bc4 Nf6} || [::scidb::pos::fen] ne $fen} {
                error {Copy Line lost the variation path or moved the board}
            }
            ::scidb::game::go key $saved
        }
        set after [state]
        if {$id eq {c3.delete}} {
            variable base
            for {set row 0} {$row < 8} {incr row} {
                if {[::scidb::db::get deleted? $row -1 $base Normal] != ($row == 7)} {
                    error {Delete changed a game other than the selected sorted row}
                }
            }
        }
        if {[string match c2.strip.* $id]} {
            set gameAfter [::scidb::game::toPGN modified]
            if {$gameBefore eq $gameAfter && $marksBefore eq [::scidb::game::query marks] && $infoBefore == [::scidb::game::count info]} { error "$id did not change the scratch game" }
            # Persist the modified scratch game; the protected control is never a sink.
            variable base
            ::scidb::game::save $base Normal [concat {*}[::scidb::game::tags]] WhiteElo BlackElo [namespace current]::nop {} -replace 1
            ::scidb::db::save $base [namespace current]::nop {}
            set changed 0
            dict for {path expected} $filesBefore { if {[bytes $path] ne $expected} { set changed 1 } }
            if {!$changed} { error "$id did not change the scratch copy" }
        }
        if {$id eq {c4.maintenance.compact} && [::scidb::db::count games $::scidb::test::objects::base Normal] != 7} { error {compact did not remove exactly the deleted scratch game} }
        if {$before eq $after && $::scidb::test::reachability::seen eq {} && !($id eq "c3.games_like" && [string match {*candidate games:*} $reply])} {
            error "$id: no observable effect (reply: $reply)"
        }
        if {$id in {c4.save_changes c4.maintenance.compact c12.save.replace c12.save.replace_moves c12.save.new}} {
            set changed 0
            dict for {path expected} $filesBefore { if {[bytes $path] ne $expected} { set changed 1 } }
            if {!$changed} { error "$id did not persist a change to the scratch copy" }
        }
        dict for {path expected} $control {
            if {[bytes $path.control] ne $expected} { error "$id changed control $path" }
        }
        return 1
    }
    proc cleanup {} {
        set ::scidb::test::reachability::nativeAccept 0
        puts {OBJECT CLEANUP begin}; flush stdout
        variable dir
        catch {::application::media::Stop}
        foreach n [::application::assistant::RunningPanes] {
            catch {::engine::resume $n}
            catch {::engine::stopAnalysis $n}
            after 100 [list set [namespace current]::drained 1]
            vwait [namespace current]::drained
            catch {::application::analysis::stopEngine $n}
        }
        after 100 [list set [namespace current]::drained 1]
        vwait [namespace current]::drained
        update
        variable slot
        variable base
        set pos 0
        foreach entry [::game::gameList] {
            if {[lindex $entry 0] ne {}} { catch {::application::pgn::release $pos}; catch {::game::release $pos} }
            incr pos
        }
        foreach opened [$::application::database::Vars(switcher) bases] {
            if {$opened ne $::scidb::clipbaseName} { catch {::application::database::closeBase .application $opened} }
        }
        file delete -force $dir
        puts {OBJECT CLEANUP finished}; flush stdout
    }
}
::scidb::test::reachability::ready
if {[info exists ::env(SCIDB_REACHABILITY_CASE)]} {
    lassign $::env(SCIDB_REACHABILITY_CASE) id argv kind
    tcltest::test objects-probe {real object action has an effect and preserves control} -setup {
        ::scidb::test::objects::setup $id $kind
    } -body {
        ::scidb::test::objects::run $id $kind
    } -cleanup { ::scidb::test::objects::cleanup } -result 1
} else {
    tcltest::test objects-inventory {enumerate actionable context leaves} -body {
        proc ::scidb::test::objects::leaves {rows} {
            set out {}
            foreach row $rows {
                if {[lindex $row 0] eq {cascade}} { lappend out {*}[leaves [lindex $row 2]] } elseif {$row ni {- ask} && [llength $row] == 1} { lappend out $row }
            }
            return $out
        }
        set ids {}
        dict for {cid menu} $::context::Menus {
            if {[lindex $menu 0] eq {list}} { lappend ids {*}[::scidb::test::objects::leaves [lindex $menu 1]] } else {
                dict for {key rows} [lindex $menu 1] { lappend ids {*}[::scidb::test::objects::leaves $rows] }
            }
        }
        set covered {}
        foreach case [::scidb::test::objects::cases] { lappend covered [lindex $case 0] }
        set bad {}
        foreach id [lsort -unique $ids] {
            if {$id ni $covered && ![dict exists $::scidb::test::objects::skips $id]} { lappend bad $id }
        }
        puts "OBJECT leaves: [llength [lsort -unique $ids]], cases: [llength $covered], explicit skips: [dict size $::scidb::test::objects::skips]"
        if {[llength $bad]} { error "context leaves without probe or reason: $bad" }
        return 1
    } -result 1
    tcltest::test objects-isolated {data-dependent dispatch in independent scratch databases} -body {
        set cases [::scidb::test::objects::cases]
        set mediaRoot [file join $::scidb::test::objects::root tests tmp-app media-test]
        if {![file isfile [file join $mediaRoot MediaTest.sci]] || ![file isdirectory [file join $mediaRoot MediaTest.media]]} {
            set available {}
            foreach case $cases {
                if {[lindex $case 2] eq {media}} {
                    puts "OBJECT SKIP [lindex $case 0]: optional local MediaTest SCI/media fixture is absent"
                } else { lappend available $case }
            }
            set cases $available
        }
        dict for {id reason} $::scidb::test::objects::skips { puts "OBJECT SKIP $id: $reason" }
        if {[info exists ::env(SCIDB_OBJECT_MATCH)]} {
            set selected {}
            foreach case $cases { if {[string match $::env(SCIDB_OBJECT_MATCH) [lindex $case 0]]} { lappend selected $case } }
            set cases $selected
        }
        puts "OBJECT isolated cases: [llength $cases]"
        set ::scidb::test::reachability::file [file normalize [info script]]
        ::scidb::test::reachability::runCases $cases
    } -result {}
}
tcltest::cleanupTests
