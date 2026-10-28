# Typed operations for the secondary user surfaces in the historical inventory.
# Keep their schemas explicit: the operator must not need a pointer position,
# Tcl callback or modal form to perform an operation.
namespace eval ::inventoryaction {}

proc ::inventoryaction::Register {} {
    ::inventorycontrol::Register
    foreach {id label doc spec handler} {
        files.mutate {Change file-picker files}
        {Rename or duplicate a selected file, or create a folder in an existing file picker. Supply path to select the source, and name for the new basename; no chooser or inline name editor opens. Existing destinations are rejected. Native database companion-file callbacks are preserved.}
        {{widget {type string required 1}} {operation {type enum required 1 enum {rename duplicate mkdir}}} {path {type string default {}}} {name {type string required 1}}}
        FileMutate
        files.delete {Delete file-picker selection}
        {Delete a supplied file or folder using the file picker's native deletion/trash policy and companion-file callback. Requires confirmation. Widget identifies an existing picker; path selects the file explicitly.}
        {{widget {type string required 1}} {path {type string required 1}}}
        FileDelete
        files.bookmark {Manage file-picker bookmarks}
        {List, add, rename or remove persistent file-picker directory bookmarks by folder path. Add is idempotent. Name supplies the display name for add/rename. Existing open file pickers refresh immediately. No files are modified.}
        {{operation {type enum default list enum {list add rename remove}}} {folder {type string default {}}} {name {type string default {}}}}
        Bookmark
        files.picker {Operate file picker}
        {Navigate an existing file picker by directory, backward or forward history, set list/details layout or hidden-file visibility, or invoke its registered custom operation on a supplied file. Supply the picker widget path; no script arguments are accepted. Omit widget to list active pickers.}
        {{widget {type string default {}}} {operation {type enum default status enum {status directory back forward layout hidden custom}}} {path {type string default {}}} {layout {type enum default details enum {list details}}} {show {type boolean default 0}}}
        Picker
        database.description {Set database description}
        {Read or set an open database's description. Supply description to apply directly; omit it to read the current value. Empty base uses the current database. Read-only databases reject changes.}
        {{base {type string default {}}} {description {type string required 0}}}
        DatabaseDescription
        database.repertoire_type {Set database repertoire type}
        {Mark a writable native database as a repertoire for both colors, White or Black. Empty base uses the current database.}
        {{base {type string default {}}} {type {type enum required 1 enum {Openings OpeningsWhite OpeningsBlack}}}}
        DatabaseType
        database.recent_remove {Remove recent database}
        {Remove a database path from the recently used list without deleting or closing its database file.}
        {{path {type string required 1}}}
        RecentRemove
        gamebar.lock {Set game lock}
        {Lock or unlock an unmodified game slot in its game bar. Locked games are protected from automatic replacement. Omit gamebar to use the editor game bar.}
        {{gamebar {type string default {}}} {slot {type integer required 1 range {0 1000}}} {locked {type boolean required 1}}}
        GameLock
        toolbar.configure {Configure toolbar}
        {Inspect or configure a live toolbar by widget path. Set state (show, hide, flat, float), dock side, or icon size. Show preserves floating placement; supply side to dock it. Omit toolbar to list live toolbars. This uses the same native layout operations as the toolbar menu.}
        {{toolbar {type string default {}}} {state {type enum required 0 enum {show hide flat float}}} {side {type enum required 0 enum {top bottom left right}}} {icons {type enum required 0 enum {default small medium large}}}}
        Toolbar
        toolbar.frame {Configure toolbar frame}
        {Set alignment or expand the frame containing a live toolbar. Supply the toolbar's widget path. These operations use the native toolbar layout.}
        {{toolbar {type string required 1}} {alignment {type enum required 0 enum {left right center}}} {expand {type boolean default 0}}}
        ToolbarFrame
        browser.size {Resize browser board}
        {Resize an open game browser's board using the native increment or minimum/maximum size. Position is the browser game slot, not the editor slot.}
        {{position {type integer required 1 range {9 1000}}} {mode {type enum required 1 enum {+5 -5 min max}}}}
        BrowserSize
        browser.display {Configure browser notation}
        {Set the browser notation column style and move notation directly, without opening preferences. Omit fields to inspect the current settings.}
        {{position {type integer required 1 range {9 1000}}} {columns {type boolean required 0}} {notation {type string required 0}}}
        BrowserDisplay
        gamebar.display {Configure game bar}
        {Set game-bar alignment, separate header, active-game placement and player line layout. Omit gamebar to use the editor game bar. Fields are idempotent and applied without a dialog.}
        {{gamebar {type string default {}}} {alignment {type enum required 0 enum {left center}}} {separate_header {type boolean required 0}} {active_bottom {type boolean required 0}} {separate_lines {type boolean required 0}}}
        GamebarDisplay
        game.trial {Set trial mode}
        {Start or stop trial mode on the current game. Stopping discards trial moves and restores the original position; enabled is idempotent. Omit enabled to toggle.}
        {{enabled {type boolean required 0}}}
        Trial
        game.transpose {Transpose game}
        {Transpose the current game in a trial copy, using the native transpose operation. Stop trial mode to restore the original game.}
        {} Transpose
        game.variation_first {Make variation first}
        {Reorder the specified variation as the first variation. Number zero selects the current variation.}
        {{number {type integer default 0 range {0 10000}}}}
        FirstVariation
        board3d.camera {Set 3D camera}
        {Choose the White, Black, Side or Top camera preset for the 3D board without a dialog.}
        {{view {type enum required 1 enum {white black side top}}}}
        Camera
        board3d.theme {Set 3D theme}
        {Select a built-in 3D board theme by name. Omit name to list available themes.}
        {{name {type string default {}}}}
        Theme
        board3d.pieces {Set 3D pieces}
        {Choose the piece rendering style for the 3D board without a dialog.}
        {{style {type enum required 1 enum {realistic3d vector photos glyphs}}}}
        Pieces
        table.column_size {Size a table column}
        {Optimize, fit, shrink or expand a named column of an existing table. The table is a widget path; column is its column identifier.}
        {{table {type string required 1}} {column {type string required 1}} {operation {type enum required 1 enum {optimize fit shrink expand}}}}
        ColumnSize
        tournament.table {Operate tournament table}
        {Configure or refresh an open tournament table, reset its view, navigate events, save HTML, or narrate its event. Supply filename for export to avoid a file chooser; omit window to use the most recently opened table. Configure fields use the native display settings.}
        {{operation {type enum default configure enum {configure refresh reset previous next export narrate}}}
         {window {type string default {}}}
         {filename {type string default {}}}
         {overwrite {type boolean default 0}}
         {padding {type integer required 0 range {1 6}}}
         {spacing {type integer required 0 enum {0 1}}}
         {pyramid {type boolean required 0}}
         {rating {type boolean required 0}}
         {performance {type boolean required 0}}
         {tiebreak {type boolean required 0}}
         {winDrawLoss {type boolean required 0}}
         {opponent {type boolean required 0}}
         {trace_html {type boolean required 0}}
         {trace_log {type boolean required 0}}}
        Tournament
        board.display {Set board display options}
        {Set the sliding variation-pane position, annotation duration in milliseconds, or promoted-piece mark. All supplied fields apply directly to the current board without opening preferences.}
        {{sliding {type enum required 0 enum {hidden bottom top right left}}}
         {annotation_ms {type integer required 0 enum {0 1500 2000 2500 3000 3500 4000 4500 5000}}}
         {promoted {type enum required 0 enum {none bullet star disk}}}}
        BoardDisplay
        notation.display {Set notation display options}
        {Set column layout or move-information visibility explicitly on the live notation. Changes are idempotent and do not open preferences.}
        {{columns {type boolean required 0}} {moveinfo {type boolean required 0}}}
        NotationDisplay
        notation.language {Toggle notation language}
        {Show or hide a comment language in the notation. Use xx to toggle all languages; otherwise supply an installed language code.}
        {{language {type string required 1}}}
        NotationLanguage
        game.undo {Undo or redo notation edit}
        {Undo or redo the most recent edit in the current game notation, regardless of keyboard focus.}
        {{operation {type enum required 1 enum {undo redo}}}}
        Undo
        database.symbol_size {Set database symbol size}
        {Set the database switcher's icon size in pixels, using the same persistent setting as its symbol-size menu.}
        {{pixels {type integer required 1 enum {24 32 48}}}}
        SymbolSize
        help.viewer {Operate help viewer}
        {Navigate the local help viewer, expand or collapse its contents tree, show or hide the index, or set text alignment. Use topic to load a help page by its installed filename. The help viewer opens when needed.}
        {{operation {type enum required 1 enum {open load expand collapse previous next back forward alignment index}}}
         {topic {type string default {}}}
         {alignment {type enum default left enum {left justify}}}
         {show {type boolean required 0}}}
        Help
    } {
        if {[dict exists $::action::Registry $id]} { continue }
        set effectCommand {}
        if {$id in {database.description toolbar.configure browser.display gamebar.display board3d.theme board.display notation.display files.picker tournament.table}} {
            set effectCommand [list ::inventoryaction::ChangesState $id]
        }
        ::action::register $id [dict create label $label what $label doc $doc \
            object {} ai 0 operator 1 confirm [expr {$id eq "files.delete"}] args $spec \
            effect-command $effectCommand handler ::inventoryaction::$handler]
    }
}

proc ::inventoryaction::Trial {arguments} {
    set active [::game::trialMode?]
    if {[dict exists $arguments enabled]} {
        set wanted [dict get $arguments enabled]
    } else { set wanted [expr {!$active}] }
    if {$active != $wanted} { ::application::pgn::flipTrialMode }
    return [dict create enabled [::game::trialMode?]]
}

proc ::inventoryaction::Transpose {arguments} {
    ::application::pgn::TransposeGame
    return [dict create enabled [::game::trialMode?] fen [::scidb::pos::fen]]
}

proc ::inventoryaction::FirstVariation {arguments} {
    ::application::pgn::FirstVariation [dict get $arguments number]
    return [::scidb::game::position key]
}

proc ::inventoryaction::Camera {arguments} {
    ::board3d::viewerPreset [dict get $arguments view]
    return [list yaw $::board3d::State(yaw) pitch $::board3d::State(pitch)]
}

proc ::inventoryaction::Theme {arguments} {
    set name [dict get $arguments name]
    if {$name eq ""} { return [lsort [array names ::board3d::Themes]] }
    if {![info exists ::board3d::Themes($name)]} { error "unknown 3D board theme '$name'" }
    return [::board3d::setTheme $name]
}

proc ::inventoryaction::Pieces {arguments} {
    return [::board3d::setPieceStyle [dict get $arguments style]]
}

proc ::inventoryaction::ColumnSize {arguments} {
    set table [dict get $arguments table]
    set column [dict get $arguments column]
    if {![winfo exists $table] || ![info exists ::table::IdMap($table)]} { error "unknown table '$table'" }
    if {[$table.t column id $column] eq ""} { error "unknown table column '$column'" }
    ::table::ColumnOperation $table $column [dict get $arguments operation]
    return [$table.t column cget $column -width]
}

proc ::inventoryaction::Tournament {arguments} {
    set dlg [dict get $arguments window]
    if {$dlg eq ""} { set dlg $::crosstable::Reuse }
    if {$dlg eq "" || ![winfo exists $dlg] || ![info exists ::crosstable::${dlg}::Vars(html)]} {
        error "no open tournament table; open a tournament table first"
    }
    upvar #0 ::crosstable::${dlg}::Vars vars
    switch -- [dict get $arguments operation] {
        configure {
            foreach {field key} {
                padding fmt:padding spacing fmt:spacing pyramid fmt:pyramid
                rating show:rating performance show:performance tiebreak show:tiebreak
                winDrawLoss show:winDrawLoss opponent show:opponent
            } {
                if {[dict exists $arguments $field]} { set ::crosstable::Options($key) [dict get $arguments $field] }
            }
            ::crosstable::UpdateContent $dlg
            foreach field {html log} {
                if {[dict exists $arguments trace_$field]} {
                    set ::crosstable::Options(debug:$field) [dict get $arguments trace_$field]
                    ::crosstable::ToggleTrace $dlg $field
                }
            }
            return [array get ::crosstable::Options]
        }
        refresh { ::crosstable::Refresh $dlg }
        reset { ::crosstable::Reset $dlg }
        previous - next {
            set button $dlg.[dict get $arguments operation]
            if {![winfo exists $button] || [$button cget -state] eq "disabled"} { error "event navigation unavailable" }
            $button invoke
        }
        export {
            set filename [dict get $arguments filename]
            if {$filename ne "" && [file exists $filename] && ![dict get $arguments overwrite]} { error "file exists; supply overwrite true" }
            ::crosstable::SaveAsHTML $dlg $filename
            return $filename
        }
        narrate { return [::crosstable::NarrateEvent $dlg] }
    }
    return $dlg
}

proc ::inventoryaction::BoardDisplay {arguments} {
    if {[dict exists $arguments sliding]} { set ::variation::Options(slide:position) [dict get $arguments sliding] }
    if {[dict exists $arguments annotation_ms]} {
        set ::application::board::Options(annotation:timeout) [dict get $arguments annotation_ms]
        $::application::board::Vars(widget:frame) itemconfigure annotation -state hidden
    }
    if {[dict exists $arguments promoted]} {
        set mark [dict get $arguments promoted]
        set ::application::board::Options(promoted:mark) $mark
        ::board::diagram::setPromoSign $::application::board::board $mark
    }
    return [list sliding $::variation::Options(slide:position) \
        annotation_ms $::application::board::Options(annotation:timeout) \
        promoted $::application::board::Options(promoted:mark)]
}

proc ::inventoryaction::NotationDisplay {arguments} {
    foreach {field key} {columns style:column moveinfo show:moveinfo} {
        if {[dict exists $arguments $field]} {
            set ::pgn::editor::Options($key) [dict get $arguments $field]
            ::application::pgn::Refresh $key
        }
    }
    return [list columns $::pgn::editor::Options(style:column) moveinfo $::pgn::editor::Options(show:moveinfo)]
}

proc ::inventoryaction::NotationLanguage {arguments} {
    set lang [dict get $arguments language]
    if {$lang ne "xx" && ![info exists ::encoding::mc::Lang($lang)]} { error "unknown language '$lang'" }
    if {![info exists ::application::pgn::Vars(lang:active:$lang)]} { set ::application::pgn::Vars(lang:active:$lang) 0 }
    set ::application::pgn::Vars(lang:active:$lang) [expr {!$::application::pgn::Vars(lang:active:$lang)}]
    ::application::pgn::ToggleLanguage $lang
    return [dict create language $lang enabled $::application::pgn::Vars(lang:active:$lang)]
}

proc ::inventoryaction::Undo {arguments} {
    ::application::pgn::Undo [dict get $arguments operation]
    return [::scidb::pos::fen]
}

proc ::inventoryaction::SymbolSize {arguments} {
    set ::database::switcher::Options(iconsize) [dict get $arguments pixels]
    return $::database::switcher::Options(iconsize)
}

proc ::inventoryaction::Help {arguments} {
    set operation [dict get $arguments operation]
    if {$operation eq "open"} { return [::help::open .application [dict get $arguments topic]] }
    if {![info exists ::help::Priv(html)] || ![winfo exists $::help::Priv(html)]} { ::help::open .application }
    switch -- $operation {
        load {
            set topic [dict get $arguments topic]
            if {$topic eq ""} { error "topic is required for load" }
            if {[file extension $topic] eq ""} { append topic .html }
            set path [::help::FullPath $topic]
            if {![file readable $path]} { error "unknown help topic '$topic'" }
            ::help::Load $path
        }
        expand { ::help::ExpandAllItems }
        collapse { ::help::CollapseAllItems }
        previous - next - back - forward {
            set key [dict get {previous prev next next back back forward forward} $operation]
            set button $::help::Priv(button:$key)
            if {[$button cget -state] eq "disabled"} { error "help $operation unavailable" }
            $button invoke
        }
        alignment {
            set alignment [dict get $arguments alignment]
            set ::help::Options(textalign) $alignment
            $::help::Priv(html) configure -textalign $alignment -showhyphens [expr {$alignment eq "justify"}]
        }
        index {
            set control $::help::Priv(control)
            set pw [winfo parent $control]
            set visible [expr {$control in [$pw panes]}]
            if {![dict exists $arguments show] || [dict get $arguments show] != $visible} { ::help::ToggleIndex }
        }
    }
    return $::help::Priv(current:file)
}

proc ::inventoryaction::BrowserVars {position} {
    set name ::browser::${position}::Vars
    if {![info exists ${name}(board)] || ![winfo exists [set ${name}(board)]]} { error "browser position $position is not open" }
    return $name
}

proc ::inventoryaction::BrowserSize {arguments} {
    set position [dict get $arguments position]
    upvar #0 [BrowserVars $position] vars
    if {$vars(fullscreen)} { error "leave browser fullscreen before resizing" }
    ::browser::ChangeBoardSize $position $vars(board) [dict get $arguments mode]
    return $vars(board:size)
}

proc ::inventoryaction::BrowserDisplay {arguments} {
    set position [dict get $arguments position]
    BrowserVars $position
    if {[dict exists $arguments notation]} {
        set style [dict get $arguments notation]
        if {$style ni $::notation::moveStyles} { error "unknown move notation '$style'" }
        set ::pgn::browser::Options(style:move) $style
        ::browser::SetupStyle $position
    }
    if {[dict exists $arguments columns]} {
        set ::pgn::browser::Options(style:column) [dict get $arguments columns]
        ::browser::SetupStyle $position
    }
    return [list columns $::pgn::browser::Options(style:column) notation $::pgn::browser::Options(style:move)]
}

proc ::inventoryaction::GamebarDisplay {arguments} {
    set bar [dict get $arguments gamebar]
    if {$bar eq ""} { set bar [::application::pgn::gamebar] }
    if {![winfo exists $bar] || ![info exists ::gamebar::Specs(size:$bar)]} { error "unknown game bar '$bar'" }
    foreach {field key callback} {
        alignment alignment Layout
        separate_header separateColumn ShowSeparateColumn
        active_bottom selectedAtBottom ShowAtBottom
        separate_lines separateLines ShowAtSeparateLines
    } {
        if {[dict exists $arguments $field]} {
            set ::gamebar::Options($key) [dict get $arguments $field]
            ::gamebar::$callback $bar
        }
    }
    return [list alignment $::gamebar::Options(alignment) separate_header $::gamebar::Options(separateColumn) active_bottom $::gamebar::Options(selectedAtBottom) separate_lines $::gamebar::Options(separateLines)]
}

proc ::inventoryaction::ToolbarPath {toolbar} {
    if {![winfo exists $toolbar] || ![info exists ::toolbar::Specs(frame:$toolbar)]} { error "unknown toolbar '$toolbar'" }
    return $toolbar
}

proc ::inventoryaction::Toolbar {arguments} {
    set toolbar [dict get $arguments toolbar]
    if {$toolbar eq ""} {
        set paths {}
        foreach key [array names ::toolbar::Specs frame:*] {
            set path [string range $key 6 end]
            if {[winfo exists $path]} { lappend paths $path }
        }
        return [lsort -unique $paths]
    }
    ToolbarPath $toolbar
    if {[dict exists $arguments state]} {
        set requested [dict get $arguments state]
        if {$requested in {flat hide float} && !$::toolbar::Specs($requested:$toolbar)} { error "toolbar does not support $requested" }
    }
    if {[dict exists $arguments side] && [dict get $arguments side] ni $::toolbar::Specs(allow:$toolbar)} { error "toolbar does not support that dock side" }
    if {[dict exists $arguments icons]} {
        set ::toolbar::Specs(iconsize:$toolbar) [dict get $arguments icons]
        ::toolbar::ChangeIcons $toolbar
    }
    if {[dict exists $arguments side]} {
        ::toolbar::MoveCmd $toolbar [dict get $arguments side] $::toolbar::Specs(side:$toolbar)
    }
    if {[dict exists $arguments state]} {
        set state [dict get $arguments state]
        ::toolbar::ChangeState $toolbar $state
    }
    return [list state $::toolbar::Specs(state:$toolbar) side $::toolbar::Specs(side:$toolbar) icons $::toolbar::Specs(iconsize:$toolbar)]
}

proc ::inventoryaction::ToolbarFrame {arguments} {
    set toolbar [ToolbarPath [dict get $arguments toolbar]]
    set frame $::toolbar::Specs(frame:$toolbar)
    if {![info exists ::toolbar::Specs(alignment:$frame)]} { error "toolbar has no docked frame" }
    if {[dict exists $arguments alignment]} {
        set ::toolbar::Specs(alignment:$frame) [dict get $arguments alignment]
        ::toolbar::DoAlignment $frame
    }
    if {[dict get $arguments expand]} { ::toolbar::Expand $frame }
    return [list frame $frame alignment $::toolbar::Specs(alignment:$frame)]
}

proc ::inventoryaction::OpenBase {arguments {writable 0}} {
    set base [dict get $arguments base]
    if {$base eq ""} { set base [::menu::CurrentBase] }
    if {![::scidb::db::get open? $base]} { error "database is not open" }
    if {$writable && [::scidb::db::get readonly? $base]} { error "database is read-only" }
    return $base
}

proc ::inventoryaction::DatabaseDescription {arguments} {
    set base [OpenBase $arguments [dict exists $arguments description]]
    if {[dict exists $arguments description]} {
        set length [::scidb::db::set description $base [dict get $arguments description]]
        if {$length != 0} { error "description exceeds the database limit ($length)" }
        ::application::database::CheckSaveState $base
        ::application::database::RefreshSwitcher
    }
    return [::scidb::db::get description $base]
}

proc ::inventoryaction::DatabaseType {arguments} {
    set base [OpenBase $arguments 1]
    if {[file extension $base] ne ".sci"} { error "repertoire type requires a native database" }
    ::application::database::SetDatabaseType $base [dict get $arguments type]
    return [::scidb::db::get type $base]
}

proc ::inventoryaction::RecentRemove {arguments} {
    set path [dict get $arguments path]
    set before [::application::database::FindRecentFile $path]
    ::application::database::removeRecentFile $path
    return [list removed [expr {$before >= 0}] remaining [llength $::application::database::RecentFiles]]
}

proc ::inventoryaction::GameLock {arguments} {
    set bar [dict get $arguments gamebar]
    if {$bar eq ""} { set bar [::application::pgn::gamebar] }
    set slot [dict get $arguments slot]
    if {![winfo exists $bar] || ![info exists ::gamebar::Specs(locked:$slot:$bar)]} { error "game slot $slot is not in the game bar" }
    if {$::gamebar::Specs(modified:$slot:$bar) || $::gamebar::Specs(frozen:$slot:$bar) || $::gamebar::Specs(state:$slot:$bar) eq "modified"} { error "cannot change lock on a modified or frozen game" }
    set state [expr {[dict get $arguments locked] ? "locked" : "unlocked"}]
    ::gamebar::SetState $bar $slot $state
    return $::gamebar::Specs(locked:$slot:$bar)
}

proc ::inventoryaction::PickerPaths {} {
    set result {}
    foreach ns [namespace children ::fsbox] {
        if {[info exists ${ns}::Vars(widget:list:file)]} {
            set path [namespace tail $ns]
            if {[winfo exists $path]} { lappend result $path }
        }
    }
    return [lsort $result]
}

proc ::inventoryaction::Bookmark {arguments} {
    set operation [dict get $arguments operation]
    set entries $::fsbox::bookmarks::Bookmarks(user)
    if {$operation eq "list"} { return $entries }
    set folder [dict get $arguments folder]
    if {$folder eq ""} { error "folder is required" }
    set folder [file normalize $folder]
    set i [lsearch -exact -index 0 $entries $folder]
    set name [dict get $arguments name]
    switch $operation {
        add {
            if {![file isdirectory $folder]} { error "bookmark folder does not exist" }
            if {$name eq ""} { set name [file tail $folder] }
            if {$i < 0} { lappend entries [list $folder $name] } else { lset entries $i [list $folder $name] }
        }
        rename {
            if {$i < 0} { error "bookmark not found" }
            if {$name eq ""} { error "name is required" }
            lset entries $i [list $folder $name]
        }
        remove {
            if {$i >= 0} { set entries [lreplace $entries $i $i] }
        }
    }
    set ::fsbox::bookmarks::Bookmarks(user) [lsort -dictionary -index 1 $entries]
    foreach w [PickerPaths] {
        ::fsbox::bookmarks::LayoutBookmarks $w
        ::fsbox::bookmarks::UpdateButtons $w
    }
    return $::fsbox::bookmarks::Bookmarks(user)
}

proc ::inventoryaction::Picker {arguments} {
    set w [dict get $arguments widget]
    if {$w eq ""} { return [PickerPaths] }
    if {$w ni [PickerPaths]} { error "unknown file picker '$w'" }
    upvar #0 ::fsbox::${w}::Vars vars
    set path [dict get $arguments path]
    switch [dict get $arguments operation] {
        directory {
            if {![file isdirectory $path]} { error "directory does not exist" }
            ::fsbox::ChangeDir $w [file normalize $path]
        }
        back { ::fsbox::filelist::Undo $w }
        forward { ::fsbox::filelist::Redo $w }
        layout {
            if {[dict get $arguments layout] ne $::fsbox::Options(show:layout)} { ::fsbox::filelist::SwitchLayout $w }
        }
        hidden {
            set vars(showhidden) [dict get $arguments show]
            ::fsbox::filelist::SwitchHidden $w
        }
        custom {
            if {$path eq "" || ![file exists $path]} { error "an existing file path is required" }
            if {![llength $vars(customcommand)]} { error "this picker has no custom operation" }
            {*}$vars(customcommand) [winfo toplevel $w] [file normalize $path]
            ::fsbox::filelist::RefreshFileList $w
            ::fsbox::bookmarks::LayoutBookmarks $w
        }
    }
    return [list folder $vars(folder) hidden $vars(showhidden) layout $::fsbox::Options(show:layout)]
}

proc ::inventoryaction::SelectPickerFile {w path {checkUsed 0}} {
    if {$w ni [PickerPaths]} { error "unknown file picker '$w'" }
    upvar #0 ::fsbox::${w}::Vars vars
    set path [file normalize $path]
    if {[file dirname $path] ne $vars(folder)} { error "source must be in the picker's current directory" }
    set i [lsearch -exact $vars(list:folder) $path]
    if {$i < 0} {
        set i [lsearch -exact -index 0 $vars(list:file) $path]
        if {$i >= 0} { incr i [llength $vars(list:folder)] }
    }
    if {$i < 0 || ![file exists $path]} { error "source is not present in the picker" }
    if {$checkUsed && [llength $vars(isusedcommand)] && [{*}$vars(isusedcommand) $path]} { error "source is currently in use" }
    incr i
    set table $vars(widget:list:file)
    $table selection clear
    $table selection add $i
    $table activate $i
    return $path
}

proc ::inventoryaction::FileMutate {arguments} {
    set w [dict get $arguments widget]
    if {$w ni [PickerPaths]} { error "unknown file picker '$w'" }
    upvar #0 ::fsbox::${w}::Vars vars
    set name [string trim [dict get $arguments name]]
    if {$name eq "" || [file tail $name] ne $name || $name in {. ..} || ![::fsbox::validateCharacters $name]} { error "name must be a valid basename" }
    set destination [file join $vars(folder) $name]
    if {[file exists $destination]} { error "destination already exists" }
    set operation [dict get $arguments operation]
    if {$operation eq "mkdir"} {
        ::fsbox::filelist::NewFolder $w $name
    } else {
        set path [SelectPickerFile $w [dict get $arguments path] [expr {$operation eq "rename"}]]
        if {$operation eq "duplicate" && [file isdirectory $path]} { error "cannot duplicate a directory" }
        if {$operation eq "rename"} { ::fsbox::filelist::RenameFile $w $name } else { ::fsbox::filelist::DuplicateFile $w $name }
    }
    if {![file exists $destination]} { error "file operation did not create its destination" }
    return $destination
}

proc ::inventoryaction::FileDelete {arguments} {
    set w [dict get $arguments widget]
    set path [SelectPickerFile $w [dict get $arguments path] 1]
    ::fsbox::filelist::DeleteFile $w 1
    if {[file exists $path]} { error "file deletion did not complete" }
    return [list deleted $path]
}

# Exact setter fields of mixed inspection/configuration operations. These are
# metadata over the same typed arguments the handlers use, never prose guesses.
proc ::inventoryaction::ChangesState {id arguments} {
    switch -- $id {
        files.picker {return [expr {[dict get $arguments widget] ne ""}]}
        toolbar.configure {
            if {[dict get $arguments toolbar] eq ""} {return 0}
            set fields {state side icons}
        }
        board3d.theme {return [expr {[dict get $arguments name] ne ""}]}
        database.description {set fields {description}}
        browser.display {set fields {columns notation}}
        gamebar.display {set fields {alignment separate_header active_bottom separate_lines}}
        board.display {set fields {sliding annotation_ms promoted}}
        notation.display {set fields {columns moveinfo}}
        tournament.table {
            if {[dict get $arguments operation] ne "configure"} {return 1}
            set fields {padding spacing pyramid rating performance tiebreak winDrawLoss opponent trace_html trace_log}
        }
        default {error "no effect metadata for $id"}
    }
    foreach field $fields {if {[dict exists $arguments $field]} {return 1}}
    return 0
}
