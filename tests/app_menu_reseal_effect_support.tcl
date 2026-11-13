namespace eval ::reg5effect {}
proc ::reg5effect::postInvoke {id} {
 catch {destroy .reg5effect}
 menu .reg5effect -tearoff 0
 ::menu::BuildDropdown .reg5effect
 .reg5effect post 20 20
 set found [findRow .reg5effect $id]
 if {![llength $found]} {error "Native dropdown did not post $id"}
 lassign $found m i
 if {[$m entrycget $i -state] ne "normal"} {error "Posted $id is disabled"}
 set command [$m entrycget $i -command]
 if {[lrange $command 0 1] ne [list ::action::run $id]} {error "Unregistered posted row: $command"}
 set result [$m invoke $i]
 catch {::tk::MenuUnpost .reg5effect};catch {destroy .reg5effect}
 update
 puts [list POSTED_EFFECT $id result $result title $::application::report::Priv(title)]
 return $result
}
proc ::reg5effect::findRow {m id} {
 set last [$m index end]
 if {$last eq "none"} {return {}}
 for {set i 0} {$i <= $last} {incr i} {
  if {[$m type $i] eq "cascade"} {
   $m postcascade $i;update
   set result [findRow [$m entrycget $i -menu] $id]
   if {[llength $result]} {return $result}
  } elseif {[$m type $i] in {command radiobutton checkbutton} && [lindex [$m entrycget $i -command] 1] eq $id} {return [list $m $i]}
 }
 return {}
}
proc ::reg5effect::reportContains {text} {
 update
 set w $::application::report::Priv(html).sub.html
 expr {[winfo exists $w] && [winfo ismapped $w] && [string first $text [$w text text]] >= 0}
}

proc ::reg5effect::postContext {cid id {object {}}} {
 catch {destroy .reg5context}
 menu .reg5context -tearoff 0
 if {![dict size $object]} {set object [::context::CurrentObject $cid]}
 if {![::context::Build $cid .reg5context $object]} {error "No native $cid context for $id"}
 .reg5context post 30 30
 set row [findRow .reg5context $id]
 if {![llength $row]} {error "Native $cid context did not post $id"}
 lassign $row m i
 set command [$m entrycget $i -command]
 if {[lrange $command 0 1] ne [list ::action::run $id]} {error "Raw context command $command"}
 set result [$m invoke $i]
 catch {::tk::MenuUnpost .reg5context}
 update
 puts [list CONTEXT_POSTED_EFFECT $cid $id result $result]
 return $result
}

proc ::reg5effect::findDialog {w title} {
 if {[winfo toplevel $w] eq $w && [wm title $w] eq $title && [winfo ismapped $w]} {return $w}
 foreach child [winfo children $w] {
  set found [findDialog $child $title]
  if {$found ne ""} {return $found}
 }
 return ""
}
proc ::reg5effect::widgetText {w} {
 set result ""
 catch {append result " " [$w cget -text]}
 foreach child [winfo children $w] {append result [widgetText $child]}
 return $result
}
proc ::reg5effect::observeClassification {} {
 # Informational messages normally render as real non-modal notice cards.
 if {[info exists ::dialog::notice::Cards]} {
  foreach card $::dialog::notice::Cards {
   lassign $card id kind message count
   set widget $::dialog::notice::Holder.$id
   if {[string first [::ai::comment::Name plan] $message] >= 0 && [winfo exists $widget] && [winfo ismapped $widget]} {
    set ::reg5effect::classification [list [winfo ismapped $widget] [widgetText $widget]]
    return
   }
  }
 }
 set dialog [findDialog . $::comment::mc::ClassifyComment]
 if {$dialog ne ""} {
  set ::reg5effect::classification [list [winfo ismapped $dialog] [widgetText $dialog]]
  destroy $dialog
  return
 }
 set ::reg5effect::classTimer [after 20 ::reg5effect::observeClassification]
}
