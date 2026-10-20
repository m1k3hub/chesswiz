# Directly selectable product probes: -match real-action-<name>.
# There are deliberately no blanket error allowances or timeout-as-pass rules.
# The probe logs the last boundary reached before a timeout (startup, args,
# or handler); dialog/network exceptions must be reviewed from that evidence.

# These synchronous product dialogs need user input. Their mapped window
# and grab were verified in Part C's modal probes; a timeout is not a pass.
set modalSkips {
    compact_database {Real compaction confirmation waits for Yes/No.}
    convert_database {Real format confirmation and destination chooser wait for user input.}
    install_chessbase_fonts {Real font-directory chooser waits for user input.}
    save_working_set {Real working-set name prompt waits for user input.}
}
::tcltest::testConstraint partcNonModal 0
foreach name [dict keys $::application::assistant::Actions] {
    set constraints {}
    if {[dict exists $modalSkips $name]} {
        set constraints partcNonModal
        foreach pattern [::tcltest::configure -match] {
            if {[string match $pattern real-action-$name]} {
                puts "ACTION-SKIP $name: [dict get $modalSkips $name]"
                break
            }
        }
    }
    tcltest::test real-action-$name {isolated product handler probe} -constraints $constraints -setup {
        set savedClasses $::ai::annotate::Settings(classes)
        set savedConfirm $::application::assistant::Priv(confirm)
        set savedReqConfirm $::application::assistant::Priv(reqconfirm)
        set savedProvider $::application::ai::Config(provider)
        set savedProviderConfig [array get ::ai::provider::Config]
        set runningBefore [::application::analysis::Running]
        set savedBulkHook $::action::BulkHook
        set savedRootChildren [winfo children .]
        set savedAppChildren [winfo children .application]
        ::scidb::test::actions::unstubDownload
    } -body [list apply {{name} {
        puts "PROBE startup $name"; flush stdout
        ::scidb::test::actions::ready
        puts "PROBE args $name"; flush stdout
        set args [::scidb::test::actions::sampleArgs $name]
        # The probe owns this process and only generated fixtures. Confirm
        # assistant-level prompts; product dialogs remain real.
        set ::application::assistant::Priv(confirm) ::scidb::test::actions::yes
        set ::application::assistant::Priv(reqconfirm) {}
        # Bulk actions would otherwise open the product confirmation dialog,
        # which needs a user; the assistant-level gate is covered by the
        # registry tests. Keep every probe order-independent.
        set ::action::BulkHook ::scidb::test::actions::yes
        set ::application::ai::Config(provider) stub
        ::ai::provider::configure -name stub -chatResponses {}
        set args [::scidb::test::actions::prepareReal $name $args]
        if {$name in {download_games update_player_data}} {
            ::scidb::test::actions::stubDownload
        }
        puts "PROBE handler $name $args"; flush stdout
        set reply [::application::assistant::runTool $name $args]
        puts "PROBE reply $name $reply"; flush stdout
        if {[dict get [::action::get $name] ai] eq "debug"} {
            if {![string match "error:*only available in debug mode*" $reply]} { error $reply }
        } elseif {[dict exists $::scidb::test::actions::RealGates $name]} {
            set expected [dict get $::scidb::test::actions::RealGates $name]
            if {$reply ne $expected} { error "$name: expected '$expected', got '$reply'" }
            puts "PROBE asserted prerequisite gate $name"
        } elseif {[string match "error:*" $reply]} {
            error $reply
        }
        ::scidb::test::actions::assertReal $name
        return 1
    }} $name] -cleanup {
        foreach number [::application::analysis::Running] {
            if {$number ni $runningBefore} { ::application::analysis::stopEngine $number }
        }
        # Handlers like discover_databases, correspondence_games and
        # open_search leave real toplevels mapped; they would cover later
        # tests and collide with their own windows. Destroy what this probe
        # created.
        foreach w [winfo children .] {
            if {$w ni $savedRootChildren} { catch { destroy $w } }
        }
        foreach w [winfo children .application] {
            if {$w ni $savedAppChildren} { catch { destroy $w } }
        }
        set ::ai::annotate::Settings(classes) $savedClasses
        set ::application::assistant::Priv(confirm) $savedConfirm
        set ::application::assistant::Priv(reqconfirm) $savedReqConfirm
        set ::action::BulkHook $savedBulkHook
        set ::application::ai::Config(provider) $savedProvider
        array unset ::ai::provider::Config
        array set ::ai::provider::Config $savedProviderConfig
        ::scidb::test::actions::unstubDownload
        ::scidb::test::actions::cleanup
    } -result 1
}

