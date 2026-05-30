set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set build_dir [file join $repo_root "build" "xsim"]
set sim_data_dir [file join $build_dir "tb" "data"]

if {[info exists ::env(XSIM_XVLOG)]} {
    set xvlog_cmd $::env(XSIM_XVLOG)
} else {
    set xvlog_cmd "xvlog"
}

if {[info exists ::env(XSIM_XELAB)]} {
    set xelab_cmd $::env(XSIM_XELAB)
} else {
    set xelab_cmd "xelab"
}

if {[info exists ::env(XSIM_XSIM)]} {
    set xsim_cmd $::env(XSIM_XSIM)
} else {
    set xsim_cmd "xsim"
}

proc require_file {path} {
    if {![file exists $path]} {
        puts stderr "[format {ERROR: Required file not found: %s} $path]"
        exit 1
    }
}

proc run_cmd {argv} {
    if {[catch {exec {*}$argv} result options]} {
        puts stderr $result
        return -options $options $result
    }
    if {$result ne ""} {
        puts $result
    }
}

puts "[format {INFO: Repo root = %s} $repo_root]"

set required_data_files [list \
    [file join $repo_root "tb" "data" "memA.hex"] \
    [file join $repo_root "tb" "data" "memB.hex"] \
    [file join $repo_root "tb" "data" "memI.hex"] \
    [file join $repo_root "tb" "data" "golden_O.hex"] \
]

foreach f $required_data_files {
    require_file $f
}

file mkdir $build_dir
file mkdir $sim_data_dir

foreach name [list "memA.hex" "memB.hex" "memI.hex" "golden_O.hex" "summary.txt"] {
    set src [file join $repo_root "tb" "data" $name]
    if {[file exists $src]} {
        file copy -force $src [file join $sim_data_dir $name]
    }
}

cd $build_dir

puts "INFO: Running xvlog..."
run_cmd [list $xvlog_cmd --sv [file join $repo_root "rtl" "top.sv"]]
run_cmd [list $xvlog_cmd --sv [file join $repo_root "rtl" "controller.sv"]]
run_cmd [list $xvlog_cmd --sv [file join $repo_root "rtl" "systolic_array.sv"]]
run_cmd [list $xvlog_cmd --sv [file join $repo_root "rtl" "pe.sv"]]
run_cmd [list $xvlog_cmd --sv [file join $repo_root "tb" "tb_top.sv"]]

puts "INFO: Running xelab..."
run_cmd [list $xelab_cmd tb_top -debug typical -s tb_top_sim]

puts "INFO: Running xsim..."
run_cmd [list $xsim_cmd tb_top_sim -runall]
