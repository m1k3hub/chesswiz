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
}
::tcltest::testConstraint partcNonModal 0
foreach name [::action::list] {
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
    } -body [list apply {{name} {
        puts "PROBE startup $name"; flush stdout
        ::scidb::test::actions::ready
        puts "PROBE args $name"; flush stdout
        set args [::scidb::test::actions::sampleArgs $name]
        # The probe owns this process and only generated fixtures. Confirm
        # assistant-level prompts; product dialogs remain real.
        set ::application::assistant::Priv(confirm) ::scidb::test::actions::yes
        set ::application::assistant::Priv(reqconfirm) {}
        set ::application::ai::Config(provider) stub
        ::ai::provider::configure -name stub -chatResponses {}
        set args [::scidb::test::actions::prepareReal $name $args]
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
        set ::ai::annotate::Settings(classes) $savedClasses
        set ::application::assistant::Priv(confirm) $savedConfirm
        set ::application::assistant::Priv(reqconfirm) $savedReqConfirm
        set ::application::ai::Config(provider) $savedProvider
        array unset ::ai::provider::Config
        array set ::ai::provider::Config $savedProviderConfig
        ::scidb::test::actions::cleanup
    } -result 1
}

