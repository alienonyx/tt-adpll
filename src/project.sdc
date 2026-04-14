# SDC for tt_um_adpll
# - Reproduces the default OpenLane base.sdc behavior (virtual clock + IO delays).
# - Defines the DCO ring oscillator output as a real clock so OpenSTA treats the
#   combinational ring as a timing source instead of an unanalyzable loop
#   (without this, parasitic estimation in STAMidPNR segfaults).

# ---- Default TT clock_port / virtual clock -----------------------------------
set clock_port __VIRTUAL_CLK__
if { [info exists ::env(CLOCK_PORT)] } {
    set port_count [llength $::env(CLOCK_PORT)]
    if { $port_count > 0 } {
        set clock_port [lindex $::env(CLOCK_PORT) 0]
    }
}
set port_args [get_ports -quiet $clock_port]
puts "\[INFO] Using clock $clock_port…"
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

set input_delay_value  [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clk_input        [get_port -quiet $clock_port]
set clk_indx         [lsearch [all_inputs] $clk_input]
set all_inputs_wo_clk [lreplace [all_inputs] $clk_indx $clk_indx ""]
set all_inputs_wo_clk_rst $all_inputs_wo_clk
set clocks           [get_clocks $clock_port]

set_input_delay  $input_delay_value  -clock $clocks $all_inputs_wo_clk_rst
set_output_delay $output_delay_value -clock $clocks [all_outputs]

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin      [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    $all_inputs_wo_clk_rst
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin      [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    $clk_input

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
set_load $cap_load [all_outputs]

set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
set_clock_transition  $::env(CLOCK_TRANSITION_CONSTRAINT)  $clocks

set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late  [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

# ---- DCO ring oscillator clock -----------------------------------------------
# The DCO ring feedback is `fb` inside u_adpll.u_dco. After Yosys flattening the
# net name becomes `u_adpll.u_dco.fb` (dot-separated). Target 16.777 MHz (period
# ~59.6 ns). Creating a clock on the feedback driver pin breaks the logical
# combinational loop that confuses OpenROAD's parasitics estimator.
set rosc_name "dco_ring"
set rosc_period_ns 60.0

set rosc_candidates [get_nets -quiet {
    u_adpll.u_dco.fb
    u_adpll.u_dco.dco_clk
    u_adpll.dco_clk
    *u_dco*fb
    *u_dco*dco_clk
}]

if { [llength $rosc_candidates] > 0 } {
    set rosc_net [lindex $rosc_candidates 0]
    set rosc_pin [get_pins -quiet -of_objects $rosc_net -filter "direction==output"]
    if { [llength $rosc_pin] > 0 } {
        create_clock [lindex $rosc_pin 0] -name $rosc_name -period $rosc_period_ns
        puts "\[INFO] Created ring-oscillator clock '$rosc_name' on [lindex $rosc_pin 0] (period ${rosc_period_ns} ns)"

        if { [llength $clocks] > 0 } {
            set_clock_groups -asynchronous \
                -group [get_clocks $rosc_name] \
                -group $clocks
        }
    } else {
        puts "\[WARNING] No output-direction pin found for ring-oscillator net $rosc_net; skipping ring clock creation"
    }
} else {
    puts "\[WARNING] Could not locate ring-oscillator feedback net; skipping ring clock creation"
}
