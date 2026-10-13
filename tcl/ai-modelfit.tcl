# ======================================================================
# AI: model-fit recommendations (audit E2) -- by rules, no model involved
# ======================================================================
# Which of the language models listed for the "AI: Choose Model" dialog
# (tcl/app-ai-models.tcl) can this machine actually run? The answer is
# arithmetic, not inference: a quantised model of <params> billion
# parameters is about <params * bits / 8> GB, and loading it wants some
# 20% more on top (weights plus KV cache plus run-time overhead). The
# largest quant whose estimate fits in the video memory goes on the GPU,
# the largest that fits in the system RAM goes on the CPU, and a model
# that fits nowhere is reported as "none" -- a recommendation the dialog
# can show without asking any model anything first.
#
# Every measured value that cannot be found is 0, never an error: an
# unreadable /proc/meminfo, a missing or failing nvidia-smi and an
# unparsable answer all mean "no memory reported", and the fit then only
# says what the arithmetic allows.
#
#   ::ai::modelfit::memory ?-meminfo FILE? ?-gpu CMD?
#       -> {ram_mb N vram_mb M}; RAM from the MemTotal line (kB) of
#          <meminfo> (default /proc/meminfo), VRAM from <cmd>
#          (default "nvidia-smi --query-gpu=memory.total
#          --format=csv,noheader,nounits"; nvidia-smi may be absent or
#          fail -- that is 0), whole numbers read as MiB and summed
#          over the lines
#   ::ai::modelfit::recommend <memory> <candidates>
#       -> for each {name params_b} candidate the largest quant of
#          {q8_0 q6_K q4_K_M q3_K_M} whose estimated size (below) fits
#          in vram_mb (placement gpu) else in ram_mb (placement cpu)
#          else quant none (placement none); best-fitting model first
#          (largest params_b that fits, ties keep the given order)
#   ::ai::modelfit::text <recommendation> -> a deterministic report
#          block (one line per recommendation, "none" rows included)
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-modelfit
}
if {![namespace exists ::platform::sys]} {
	catch { source [file join [file dirname [file normalize [info script]]] sys-platform.tcl] }
}

package require Tcl 8.5

namespace eval ai {
namespace eval modelfit {

# bits per weight per quant label, largest first
variable Quants {q8_0 8.5 q6_K 6.6 q4_K_M 4.8 q3_K_M 3.9}
# head-room over the bare weight bytes: KV cache, activations, runtime
variable Overhead 1.2

} ;# namespace modelfit
} ;# namespace ai


# The chooser probes GPU memory through a nonblocking pipe. A wedged driver
# may time out, but must never hold the Tk event loop or the menu grab.
namespace eval ::ai::modelfit {
	variable ProbeSeq 0
	variable Probes
	array set Probes {}
}

proc ::ai::modelfit::memoryAsync {script args} {
	variable ProbeSeq
	variable Probes
	array set opts {-meminfo /proc/meminfo -timeoutMs 1500 \
		-gpu {nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits}}
	array set opts $args
	set id [incr ProbeSeq]
	set ram [memory -meminfo $opts(-meminfo) -gpu {}]
	set Probes($id) [dict create script $script memory $ram output {} chan {} timer {}]
	# Windows has no /dev/null: the open failed there, so no GPU was ever seen
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	if {![llength $opts(-gpu)] || [catch {
		set chan [open [concat [list |] $opts(-gpu) [list 2> $null]] r]
	}]} {
		dict set Probes($id) timer [after 0 [namespace code [list FinishMemory $id]]]
		return $id
	}
	fconfigure $chan -blocking 0 -encoding utf-8 -translation auto
	dict set Probes($id) chan $chan
	dict set Probes($id) timer [after $opts(-timeoutMs) [namespace code [list FinishMemory $id 1]]]
	fileevent $chan readable [namespace code [list ReadMemory $id]]
	return $id
}

proc ::ai::modelfit::ReadMemory {id} {
	variable Probes
	if {![info exists Probes($id)]} { return }
	set chan [dict get $Probes($id) chan]
	if {[catch {read $chan 8192} data]} { FinishMemory $id 1; return }
	dict append Probes($id) output $data
	if {[string length [dict get $Probes($id) output]] > 65536} {
		FinishMemory $id 1
	} elseif {[eof $chan]} {
		FinishMemory $id
	}
}

proc ::ai::modelfit::FinishMemory {id {failed 0} {deliver 1}} {
	variable Probes
	if {![info exists Probes($id)]} { return }
	set probe $Probes($id)
	unset Probes($id)
	after cancel [dict get $probe timer]
	set chan [dict get $probe chan]
	if {$chan ne {}} {
		fileevent $chan readable {}
		if {$failed} {
			catch {::platform::sys::kill [pid $chan] -TERM}
		}
		# Closing a nonblocking pipeline does not wait for child termination.
		catch {close $chan}
	}
	set memory [dict get $probe memory]
	if {!$failed} {
		set vram 0
		foreach token [regexp -all -inline {\S+} [string map {, " "} [dict get $probe output]]] {
			if {[string is integer -strict $token] && $token > 0} { incr vram $token }
		}
		dict set memory vram_mb $vram
	}
	if {$deliver} { {*}[dict get $probe script] $memory }
}

proc ::ai::modelfit::cancelMemory {id} {
	FinishMemory $id 1 0
}


# Memory, every failure a zero: the MemTotal line (in kB) of the given
# meminfo file, whole MiB numbers summed over the lines of the gpu
# command ("24576" on its own line, or "24576, 24576" for many GPUs).
proc ::ai::modelfit::memory {args} {
	array set opts {-meminfo /proc/meminfo \
		-gpu {nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits}}
	array set opts $args

	set ram 0
	set vram 0

	if {![catch { open $opts(-meminfo) r } chan]} {
		set text [::read $chan]
		close $chan
		foreach line [split $text "\n"] {
			if {[string compare -length 9 $line "MemTotal:"] != 0} { continue }
			# "MemTotal:       32768000 kB" -- the number is the second
			# word; a line without one means no memory reported
			set words [regexp -all -inline {\S+} $line]
			if {[llength $words] < 2
				|| [catch { expr { int([lindex $words 1]) } } kb]} { break }
			set ram [expr { $kb / 1024 }]
			break
		}
	}

	if {[llength $opts(-gpu)]} {
		set output ""
		if {[catch { exec {*}$opts(-gpu) } output]} { set output "" }
		foreach line [split [string trimright $output] "\n"] {
			foreach token [split [string trim $line] " ,\t"] {
				if {[catch { expr { int($token) } } value]} { continue }
				set vram [expr { $vram + $value }]
			}
		}
	}

	return [dict create ram_mb $ram vram_mb $vram]
}


# The estimated size of <params_b> billion weights at <bits> bits per
# weight, in MiB with the run-time head-room on top.
proc ::ai::modelfit::sizeOf {params_b bits} {
	variable Overhead
	return [expr { $params_b * $bits / 8 * $Overhead * 1024 }]
}


# Best-fitting first: the models that fit, largest params_b on top; a
# model that fits nowhere is last; ties keep the order they were given.
# The decorated items carry {key seq row}, so the comparison needs
# nothing from the caller's scope.
proc ::ai::modelfit::ByParamsId {a b} {
	set delta [expr { [lindex $a 0] - [lindex $b 0] }]
	if {$delta > 1e-9} { return -1 }
	if {$delta < -1e-9} { return 1 }
	return [expr { [lindex $a 1] > [lindex $b 1] ? 1 :
		([lindex $a 1] < [lindex $b 1] ? -1 : 0) }]
}


proc ::ai::modelfit::recommend {memory candidates} {
	variable Quants

	if {![catch { list [dict get $memory ram_mb] [dict get $memory vram_mb] } pair]} {
		lassign $pair ram vram
	} else {
		error "memory must be a {ram_mb .. vram_mb ..} dict"
	}

	set seq 0
	set rows {}
	foreach cand $candidates {
		set rows [dict merge $rows \
			[dict create \
				[incr seq] [dict create \
					name [dict get $cand name] \
					params_b [dict get $cand params_b]]]]
	}

	# for each candidate: the largest quant that fits the video memory
	# goes on the GPU, else the largest that fits the system RAM goes on
	# the CPU, and a model that fits nowhere keeps its "none" row
	foreach id [dict keys $rows] {
		set row [dict get $rows $id]
		set b [dict get $row params_b]
		set quant none
		set placement none
		set size_mb 0.0
		set cpu_quant none
		set cpu_placement none
		set cpu_size 0.0
		foreach {label bits} $Quants {
			set mb [sizeOf $b $bits]
			if {$mb + 1e-9 <= $vram} {
				set quant $label
				set placement gpu
				set size_mb $mb
				break
			}
			# the largest quant that fits the system RAM, should the
			# scan find no video memory for this model at all
			if {$cpu_quant eq "none" && $mb + 1e-9 <= $ram} {
				set cpu_quant $label
				set cpu_placement cpu
				set cpu_size $mb
			}
		}
		if {$quant eq "none" && $cpu_quant ne "none"} {
			set quant $cpu_quant
			set placement $cpu_placement
			set size_mb [expr { double($cpu_size) }]
		}
		dict set rows $id [dict merge $row [dict create \
			quant $quant placement $placement size_mb $size_mb]]
	}

	# decorate (fit key, given order), sort, strip
	set decorated {}
	foreach id [dict keys $rows] {
		set row [dict get $rows $id]
		lappend decorated [list \
			[expr { [dict get $row size_mb] > 0.0 \
				? [dict get $row params_b] : -1.0 }] \
			$id $row]
	}
	set out {}
	foreach item [lsort -command ::ai::modelfit::ByParamsId $decorated] {
		lappend out [lindex $item 2]
	}
	return $out
}


# The deterministic report block: one line per recommendation, in the
# order the recommendation carries (best-fitting model first).
proc ::ai::modelfit::text {recommendation} {
	set lines {}
	foreach row $recommendation {
		lappend lines [format "%s: %s (%s, %.1f MB)" \
			[dict get $row name] [dict get $row quant] \
			[dict get $row placement] [dict get $row size_mb]]
	}
	join $lines "\n"
}

# vi:set ts=3 sw=3:
