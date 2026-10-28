# Typed native controls for secondary panes and windows.
namespace eval ::inventorycontrol {}
proc ::inventorycontrol::Register {} {
    foreach {id label doc spec handler} {
        game.explain {Explain this game}
        {Explain the current game's opening, character of play and result in the Report pane, using the same checked generation as the game-bar command. Uses the loaded game's PGN; this does not annotate or modify the game.}
        {} ExplainGame
        layout.group {Set pane grouping}
        {Set an existing pane's container to notebook tabs or multiple windows, using the native layout grouping operation. Pane is its uid in the current layout. Explicit mode is idempotent.}
        {{pane {type string required 1}} {mode {type enum required 1 enum {notebook multiwindow}}}} LayoutGroup
        layout.align_lines {Align pane to whole lines}
        {Resize a text pane in the board layout to a whole number of lines, using its native line-height calculation. Pane is a uid that advertises line alignment, such as editor. No effect when already aligned.}
        {{pane {type string required 1}}} AlignLines
        database.clear_clipbase {Empty clipboard database}
        {Clear all games of the current variant from the clipboard database after confirmation. Unsaved modified clipboard games must first be saved or closed; they return an error rather than opening another dialog. Other databases are unchanged.}
        {} ClearClipbase
        board.start_preset {Choose starting-position preset}
        {Create a new game from a built-in starting-position preset, preserving the previous game. Preset is Normal, Chess960, Symm960, Shuffle, or a built-in numeric position identifier. Target setup instead changes the existing board-setup form without applying it to the game.}
        {{preset {type string required 1}} {target {type enum default game enum {game setup}}}} StartPreset
        board.piece_preview {Choose piece-design preview}
        {Select the preview piece or background layout in an existing piece-design configuration window. Piece is k, q, r, b, n or p; layout is ll, ld, dd, dl, ldld or dldl. Omit fields to inspect. No configuration window is opened.}
        {{piece {type enum required 0 enum {k q r b n p}}} {layout {type enum required 0 enum {ll ld dd dl ldld dldl}}}} PiecePreview
        save.tags {Edit save-form tags}
        {List, set or remove extra tags in an existing save-game form without opening an inline editor. Omit dialog to list active forms. Set requires a tag name and value; remove rejects mandatory locked tags. This edits the pending form, without saving the database.}
        {{dialog {type string default {}}} {operation {type enum default list enum {list set remove}}} {name {type string default {}}} {value {type string required 0}}} SaveTags
        save.match_fields {Select save-form match fields}
        {Set which matched player or event fields the save-game form applies. Field must be an existing selectable field (for example player:fideID or event:country). Explicit enabled is idempotent and uses the native checkbutton variable. Omit field to list current selections.}
        {{field {type string default {}}} {enabled {type boolean required 0}}} MatchFields
        move.choice {Choose pending move operation}
        {Resolve the currently open move-insertion choice: replace, variation, mainline, trial, exchange, append or cancel. Only choices offered by the native menu are accepted; no pending menu returns an error.}
        {{action {type enum required 1 enum {replace variation mainline trial exchange append cancel}}}} MoveChoice
        move.promotion {Choose pending promotion}
        {Choose a piece for the currently open promotion menu. Only pieces legal for that native variant menu are accepted. No pending promotion returns an error.}
        {{piece {type enum required 1 enum {q r b n k}}}} Promotion
        database.copy_choice {Choose pending database copy}
        {Resolve the currently open database drag-copy menu by copying all games of the variant, the current filter, all variants, or canceling. Only enabled native choices are accepted. Parent identifies the database switcher containing the pending menu.}
        {{parent {type string required 1}} {action {type enum required 1 enum {all filter complete cancel}}}} CopyChoice
        files.drop_choice {Choose pending file drop}
        {Resolve an existing file picker's pending drop menu with copy, move, link, restore or cancel. The menu's native operation performs the file changes after the choice; unsupported choices and absent menus return errors.}
        {{widget {type string required 1}} {action {type enum required 1 enum {copy move link restore cancel}}}} DropChoice
        playercard.trace {Set player card trace}
        {Show or hide the HTML or log trace for an existing player card. Omit key to list open card keys. Supplied enabled is idempotent.}
        {{key {type string default {}}} {kind {type enum default html enum {html log}}} {enabled {type boolean default 1}}} PlayerTrace
        board.game_source {Set game navigation source}
        {Choose whether board game-navigation buttons navigate the game list or the database. Explicit values are idempotent.}
        {{source {type enum required 1 enum {list base}}}} GameSource
        board.navigate {Navigate board moves}
        {Move through the current game's main line or variations using the board toolbar's native navigation.}
        {{step {type enum required 1 enum {start end +1 -1 +10 -10 up down}}}} Navigate
        database.variant {Switch database variant}
        {Switch the current database view to a supported chess variant.}
        {{variant {type string required 1}}} Variant
        database.games_view {Configure game list view}
        {Scroll the native database game list to a page or selection, navigate to a game number, or set its scrollbar layout. Table identifies a live game-list table.}
        {{table {type string required 1}} {operation {type enum required 1 enum {start end back forward selection number layout}}} {number {type integer default 1 range {1 100000000}}} {layout {type enum default right enum {right bottom}}}} GamesView
        engine.dictionary_sort {Sort engine dictionary}
        {Sort the installed engine dictionary by name, Elo or rating. Opens its local dictionary window if needed; no network request is made.}
        {{field {type enum required 1 enum {name elo rating}}}} EngineSort
        overview.rotate {Rotate overview boards}
        {Rotate every board in an open game overview. Notebook is the overview notebook widget path.}
        {{notebook {type string required 1}}} OverviewRotate
        table.find_object {Find named table object}
        {Find a player, event or site by name prefix in its existing table, activating and scrolling to the match. Widget identifies the native table's parent for players, or the table for events/sites.}
        {{kind {type enum required 1 enum {player event site}}} {widget {type string required 1}} {name {type string required 1}} {next {type boolean default 0}}} FindObject
        table.player_source {Set player dictionary source}
        {Enable or disable the player database for an existing player table and refresh its native rows.}
        {{widget {type string required 1}} {enabled {type boolean required 1}}} PlayerSource
        analysis.info {Set analysis information detail}
        {Show more or less information in an existing analysis tree toolbar. Tree is the native analysis widget path.}
        {{tree {type string required 1}} {detail {type enum required 1 enum {more less}}}} AnalysisInfo
    } {
        if {[dict exists $::action::Registry $id]} {continue}
        ::action::register $id [dict create label $label what $label doc $doc object {} ai 0 operator 1 confirm [expr {$id eq "database.clear_clipbase"}] args $spec handler ::inventorycontrol::$handler]
    }
}
proc ::inventorycontrol::LayoutGroup {arguments} {
    set twm [::menu::CurrentTWM]
    set uid [dict get $arguments pane]
    set frame [$twm leaf $uid]
    if {$frame eq "" || ![winfo exists $frame]} {error "unknown pane '$uid'"}
    set container [$twm parent $frame]
    if {!([$twm ismultiwindow $container] || [$twm isnotebook $container])} {error "pane has no switchable group"}
    set multi [expr {[dict get $arguments mode] eq "multiwindow"}]
    if {[$twm ismultiwindow $container] != $multi} {$twm togglenotebook $container}
    return [dict get $arguments mode]
}
proc ::inventorycontrol::AlignLines {arguments} {
    set twm [::menu::CurrentTWM]
    set uid [dict get $arguments pane]
    set id $::application::Vars($twm:id)
    if {$id ne "board" || ![info exists ::application::Vars(align:$id:$uid)] || !$::application::Vars(align:$id:$uid)} {error "pane does not support line alignment"}
    set height [::application::twm::ComputeAlignedHeight $twm $uid]
    if {$height > 0} {::application::twm::AlignToLine $twm $uid $height}
    return $height
}
proc ::inventorycontrol::ClearClipbase {arguments} {
    set variant $::application::database::Vars(variant)
    foreach entry $::game::List {
        lassign $entry time modified locked frozen database
        lassign $database base unused number gameVariant
        if {$base eq $::scidb::clipbaseName && $gameVariant eq $variant && $modified} {error "save or close modified clipboard games before emptying the clipboard database"}
    }
    ::application::database::EmptyClipbase .application
    return [::scidb::db::count games $::scidb::clipbaseName $variant]
}
proc ::inventorycontrol::StartPreset {arguments} {
    set preset [dict get $arguments preset]
    if {$preset ni {Normal Chess960 Symm960 Shuffle 4015 4000 4001 4002 4004 4010 4003 4013 4009 4014 4005 4006 4007 4008 4011 4012}} {error "unknown starting-position preset '$preset'"}
    if {[dict get $arguments target] eq "setup"} {
        if {![info exists ::setup::board::Vars(board)] || ![winfo exists $::setup::board::Vars(board)]} {error "no active board-setup form"}
        ::setup::board::Shuffle $preset
        return $::setup::board::Vars(fen)
    }
    set idn $preset
    if {![string is integer -strict $idn]} {set idn [::setup::shuffle $preset]}
    lassign [::scidb::board::idnToFen $idn xfen] fen
    set result [::knowledge::RunAction set_position [list fen $fen]]
    if {[string match error:* $result]} {error $result}
    return [::scidb::pos::fen]
}
proc ::inventorycontrol::PiecePreview {arguments} {
    if {![info exists ::board::piece::Widget(dialog)] || ![winfo exists $::board::piece::Widget(dialog)]} {error "no active piece-design configuration"}
    if {[dict exists $arguments piece]} {::board::piece::SetPiece [dict get $arguments piece]}
    if {[dict exists $arguments layout]} {::board::piece::MakeSquare [dict get $arguments layout]}
    return [dict create piece $::board::piece::Piece layout $::board::piece::Layout]
}
proc ::inventorycontrol::MatchFields {arguments} {
    set field [dict get $arguments field]
    if {$field eq ""} {return [lsort [array get ::dialog::save::Selection]]}
    if {![info exists ::dialog::save::Selection($field)]} {error "unknown selectable match field '$field'"}
    if {[dict exists $arguments enabled]} {set ::dialog::save::Selection($field) [dict get $arguments enabled]}
    return $::dialog::save::Selection($field)
}
proc ::inventorycontrol::SaveTags {arguments} {
    set forms {}
    foreach dlg [winfo children .application] {
        if {[info exists ::${dlg}::Priv(taglist)] && [winfo exists [set ::${dlg}::Priv(taglist)]] && [winfo viewable $dlg]} {lappend forms $dlg}
    }
    set dlg [dict get $arguments dialog]
    if {$dlg eq ""} {return $forms}
    if {$dlg ni $forms} {error "unknown active save form '$dlg'"}
    set t [set ::${dlg}::Priv(taglist)]
    set operation [dict get $arguments operation]
    set name [dict get $arguments name]
    if {$operation ne "list"} {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $name]} {error "invalid tag name '$name'"}
        if {$operation eq "remove"} {
            if {[info exists ::dialog::save::Item($name)] && ![$t item enabled $::dialog::save::Item($name)]} {error "mandatory tag cannot be removed"}
            ::dialog::save::RemoveTag $t $name
        } else {
            if {![dict exists $arguments value]} {error "set requires value"}
            ::dialog::save::UpdateTagList $t $name [dict get $arguments value]
        }
    }
    return [array get ::dialog::save::Lookup]
}
proc ::inventorycontrol::Choose {menu command} {
    if {![winfo exists $menu] || ![winfo ismapped $menu]} {error "no pending choice menu"}
    for {set i 0} {$i <= [$menu index end]} {incr i} {
        if {[$menu type $i] ne "command"} {continue}
        if {[$menu entrycget $i -command] eq $command && [$menu entrycget $i -state] ne "disabled"} {
            # Unpost first: the native drop/copy unpost binding defaults to
            # cancellation. The explicit selected command must win afterward.
            ::tk::MenuUnpost $menu
            $menu invoke $i
            return
        }
    }
    error "choice is not offered by the pending operation"
}
proc ::inventorycontrol::MoveChoice {arguments} {
    set menu $::application::board::board.popup_confirm
    set action [dict get $arguments action]
    if {$action eq "cancel"} {
        set command [namespace eval ::move [list namespace code [list set action_ cancel]]]
    } else {
        set command [list eval ::move::SetAction $action]
    }
    Choose $menu $command
    return $action
}
proc ::inventorycontrol::Promotion {arguments} {
    set piece [dict get $arguments piece]
    Choose $::application::board::board.popup_promotion [namespace eval ::move [list namespace code [list set _promoted $piece]]]
    return $piece
}
proc ::inventorycontrol::CopyChoice {arguments} {
    set action [dict get $arguments action]
    Choose [dict get $arguments parent].selection_ [list set ::database::switcher::trigger_ $action]
    return $action
}
proc ::inventorycontrol::DropChoice {arguments} {
    set action [dict get $arguments action]
    set choice $action
    if {$choice eq "cancel"} {set choice refuse_drop}
    Choose [dict get $arguments widget].askAboutAction [list set ::fsbox::action_ $choice]
    return $action
}
proc ::inventorycontrol::PlayerTrace {arguments} {
    set keys {}
    foreach key [array names ::playercard::Vars *:open] {
        set key [string range $key 0 end-5]
        if {[info exists ::playercard::Vars($key)] && [winfo exists $::playercard::Vars($key)]} {lappend keys $key}
    }
    set key [dict get $arguments key]
    if {$key eq ""} {return $keys}
    if {$key ni $keys} {error "unknown open player card '$key'"}
    set kind [dict get $arguments kind]
    set ::playercard::Options(debug:$kind) [dict get $arguments enabled]
    ::playercard::ToggleTrace $kind $key
    return [winfo exists $::playercard::Vars($key).$kind]
}
proc ::inventorycontrol::GameSource {arguments} {
    ::application::board::SwitchView [dict get $arguments source]
    return $::application::board::Vars(load:method)
}
proc ::inventorycontrol::Navigate {arguments} {
    ::application::board::Goto [dict get $arguments step]
    return [::scidb::game::position key]
}
proc ::inventorycontrol::Variant {arguments} {
    set variant [dict get $arguments variant]
    if {$variant ni $::application::database::Variants} {error "unknown chess variant '$variant'"}
    ::application::database::SwitchVariant $variant
    return $::application::database::Vars(variant)
}
proc ::inventorycontrol::GamesView {arguments} {
    set table [dict get $arguments table]
    if {![winfo exists $table] || ![info exists ::application::database::games::${table}::Vars(minsize)]} {error "unknown database game list '$table'"}
    set operation [dict get $arguments operation]
    switch $operation {
        layout {::application::database::games::ChangeLayout $table [dict get $arguments layout]}
        number {::application::database::games::Goto $table [dict get $arguments number]}
        default {
            if {$operation eq "selection"} {set operation stop}
            ::application::database::games::Control $table $operation
        }
    }
    return [list layout $::application::database::games::Options(layout) active [::scrolledtable::active $table]]
}
proc ::inventorycontrol::EngineSort {arguments} {
    ::engine::showEngineDictionary .application
    set ::engine::Priv(sort) [dict get $arguments field]
    ::engine::SortEngines .application.engineDict.top.list
    return $::engine::Priv(sort)
}
proc ::inventorycontrol::OverviewRotate {arguments} {
    set nb [dict get $arguments notebook]
    if {![winfo exists $nb] || ![info exists ::overview::${nb}::Vars(flip)]} {error "unknown overview notebook '$nb'"}
    ::overview::RotateBoard $nb
    return [set ::overview::${nb}::Vars(flip)]
}
proc ::inventorycontrol::FindObject {arguments} {
    set kind [dict get $arguments kind]
    set path [dict get $arguments widget]
    set ns ::${kind}table
    if {![winfo exists $path] || ![info exists ${ns}::${path}::Vars(viewcmd)]} {error "unknown $kind table '$path'"}
    set mode [expr {[dict get $arguments next] ? "next" : "first"}]
    ${ns}::Find $path $mode [dict get $arguments name]
    if {$kind eq "player"} {append path .table}
    return [::scrolledtable::active $path]
}
proc ::inventorycontrol::PlayerSource {arguments} {
    set path [dict get $arguments widget]
    if {![winfo exists $path] || ![info exists ::playertable::${path}::Options(use-player-base)]} {error "unknown player table '$path'"}
    set ::playertable::${path}::Options(use-player-base) [dict get $arguments enabled]
    ::playertable::Refresh $path
    return [set ::playertable::${path}::Options(use-player-base)]
}
proc ::inventorycontrol::AnalysisInfo {arguments} {
    set tree [dict get $arguments tree]
    if {![winfo exists $tree] || ![info exists ::application::analysis::${tree}::Vars(number)]} {error "unknown analysis tree '$tree'"}
    set number [set ::application::analysis::${tree}::Vars(number)]
    set ::application::analysis::${number}::Options(toolbar:info) [dict get $arguments detail]
    ::application::analysis::ConfigureInfo $tree
    return [set ::application::analysis::${number}::Options(toolbar:info)]
}

proc ::inventorycontrol::ExplainGame {arguments} {
    ::application::ai::explainSelection .application game {}
    return {Game explanation requested.}
}
