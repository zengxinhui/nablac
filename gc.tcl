#!/bin/expect -f

# Get configuration and save to disk
# Also extract IP info from configuration and save it to database
#
# Usage:
#   gc.tcl [dev_id[,dev_id[,dev_id[,...]]]]

source "util.tcl"

proc parse_run {id hostname} {
    NABLAC_DB eval {select dev_id,ip from devices where dev_id=:id} {
        set filename "configs/$hostname $ip"
    }
    parse_ip $filename $dev_id
}

proc detect_device_type {prompt} {
    global ASA_commands IOS_commands NEXUS_commands PIX_commands
    
    set type "IOS"
    set commands $IOS_commands
    
    send "show line\r"
    expect {
        "ERROR" {
            set type "ASA"
            set commands $ASA_commands
        }
        "available" {
            set type "PIX"
            set commands $PIX_commands 
        }
        "line Console:" {
            set type "NEXUS"
            set commands $NEXUS_commands
        }
        "CTY"
    }
    expect $prompt
    color_puts $type
    return [list $type $commands]
}

proc backup_nexus {hostname prompt commands logfile} {
    set zVDC {}
    send "sh vdc\r"
    while {1} {
        expect {
            -re {[\r\n]\d\s+(\S+)}	 {lappend zVDC $expect_out(1,string)}
            $prompt			         {break}
        }
    }
    if {[llength $zVDC] > 0} {
        foreach _VDC $zVDC {
            log_file
            log_file -noappend "stats/$hostname $_VDC"
            sendexpect "switchto vdc $_VDC" "#"
            set prompt1 [lindex [init] 1]
            foreach cmd $commands {
                sendexpect $cmd $prompt1
            }
            sendexpect "switchback" $prompt
        }
    } else {
        foreach cmd $commands {
            sendexpect $cmd $prompt
        }
    }
    log_file
    log_file -noappend "configs/$logfile"
    send "sh run vdc-all\r"
    expect {
        "nvalid" {
            sendexpect "sh run" $prompt
        }
        $prompt
    }
}

proc backup_standard {hostname prompt commands logfile} {
    foreach cmd $commands {
        sendexpect $cmd $prompt
    }
    log_file
    log_file -noappend "configs/$logfile"
    sendexpect "sh run" $prompt
}

proc set_file_permissions {logfile} {
    if {[file exists "stats/$logfile"]} {
        file attributes "stats/$logfile" -permissions 00600
    }
    if {[file exists "configs/$logfile"]} {
        file attributes "configs/$logfile" -permissions 00600
    }
}

proc getconfig {hostip} {
    lassign [init] hostname prompt
    set logfile "$hostname $hostip"
    log_file -noappend "stats/$logfile"
    
    lassign [detect_device_type $prompt] type commands

    if {$type eq "NEXUS"} {
        backup_nexus $hostname $prompt $commands $logfile
    } elseif {[lsearch "IOS ASA PIX" $type] >= 0} {
        backup_standard $hostname $prompt $commands $logfile
    }
    
    logout
    wait -nowait
    log_file
    set_file_permissions $logfile
    return $hostname
}

proc main {argv} {
    global timeout spawn_id
    set timeout 1800
    set rows {}

    if {[llength $argv] == 0} {
        NABLAC_DB eval {select dev_id,username,password,enable,hostname,ip,last_check from cred,devices\
                        where cred.cred_id=devices.cred_id and last_check>=0\
                        order by last_check\
                        limit (select count(*)/30 from devices where last_check>=0)} {
            lappend rows [list $dev_id $username $password $enable $hostname $ip $last_check]
        }
    } else {
        NABLAC_DB eval "select dev_id,username,password,enable,hostname,ip,last_check from cred,devices\
                        where cred.cred_id=devices.cred_id and dev_id in ($argv)" {
            lappend rows [list $dev_id $username $password $enable $hostname $ip $last_check]
        }
    }

    foreach row $rows {
        lassign $row id username password enable hostname hostip last_check
        color_puts "id: $id hostname: $hostname ip: $hostip\n"
        
        lassign [login $hostip 22 $username $password $enable] status spawn_id
        
        if {$status == 0} {
            # Success
            parse_run $id [getconfig $hostip]
            set last_check [clock seconds]
            NABLAC_DB eval {update devices set last_check=:last_check where dev_id=:id}
        } else {
            # Failure
            set last_check [clock seconds]
            set last_check [clock format $last_check -format -%Y%m%d]
            NABLAC_DB eval {update devices set last_check=:last_check where dev_id=:id}
            color_puts "failed $hostip $username (status: $status)"
        }
    }
    return 0
}

exit [main $argv]
