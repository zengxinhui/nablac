#!/bin/expect -f
#
# Usage:
#   fp.tcl <hostname/ip> [ro?]
# Options:
#     hostname/ip    hostname or IP address
#     ro?            readonly? defaults to no and will update db
#
# Exit code: 255 connection failed
#            254 password failed
#            253 enable failed
#            252 device is in db and skipped
#            251 not supported
#            1   SSH host key changed
#            0   login info found

source "util.tcl"

proc check_skip_list {host} {
    global SKIPPED
    if {[lsearch $SKIPPED $host] > -1} {
        puts "SKIPPED $host"
        return 1
    }
    return 0
}

proc find_device_in_db {host} {
    set hostx "%$host%"
    set found 0
    set dev_id ""
    NABLAC_DB eval {select hostname,cred_id,ip,dev_id,last_check from devices where ip=$host or hostname like $hostx
                    union
                    select d.hostname,d.cred_id,d.ip,d.dev_id,last_check from devices as d,ip where d.dev_id=ip.dev_id and ip.ip=$host} {
        if {$last_check >= 0} {
            send_user [format "use: %4s %2s %15s %s for %s\n" $dev_id $cred_id $ip $hostname $host]
        } else {
            color_send 31 [format "zzzz disabled since %s: %4s %2s %15s %s for %s with cred %s\n" $last_check $dev_id $cred_id $ip $hostname $host $cred_id]
        }
        set found 1
    }
    return [list $found $dev_id]
}

proc get_credentials {} {
    set creds {}
    NABLAC_DB eval {select cred_id,freq,username,password,enable from cred where freq>=0 order by freq desc} {
        lappend creds [list $cred_id $freq $username $password $enable]
    }
    return $creds
}

proc try_login {host creds} {
    foreach cred $creds {
        lassign $cred cred_id freq user pass enable
        send_user "\nuser: $user  pass: $pass  enable: $enable\n"
        
        lassign [login $host 22 $user $pass $enable] status spawn_id
        
        if {$status == 0} {
            return [list 0 $spawn_id $cred_id]
        } elseif {$status == 1} {
            return [list 1 "" ""]
        }
    }
    return [list $status "" ""]
}

proc update_db_after_success {host hostname cred_id dev_id findonly} {
    if {$findonly eq ""} {
        set freq 0
        NABLAC_DB eval {select freq from cred where cred_id=$cred_id} {}
        incr freq
        set last_check [expr [clock seconds] - 8640000]
        NABLAC_DB transaction {
            NABLAC_DB eval {update cred set freq=$freq where cred_id=$cred_id}
            NABLAC_DB eval {insert into devices (hostname,ip,cred_id,last_check) values ($hostname, $host, $cred_id, $last_check)}
        }
    } else {
        set last_check [expr [clock seconds] - 8640000]
        send_user "\ninsert into devices (hostname,ip,cred_id) values (\"$hostname\", \"$host\", $cred_id);"
        if {$dev_id ne ""} {
            send_user "\nupdate devices set cred_id=$cred_id                        where dev_id=$dev_id;"
            send_user "\nupdate devices set hostname=\"$hostname\"                  where dev_id=$dev_id;"
            send_user "\nupdate devices set ip=\"$host\"                            where dev_id=$dev_id;"
            send_user "\nupdate devices set cred_id=$cred_id,last_check=$last_check where dev_id=$dev_id;\n"
        }
    }
}

proc main {argv} {
    global SKIPPED spawn_id
    
    lassign $argv host findonly

    if {[check_skip_list $host]} {
        return 251
    }

    lassign [find_device_in_db $host] found dev_id

    if {$found && $findonly eq ""} {
        return 252
    }

    set creds [get_credentials]
    lassign [try_login $host $creds] exit_code spawn_id cred_id

    if {$exit_code == 0} {
        sendexpect "" "#"
        send "\r"
        expect {
            -re {[\n\r]([&\w/\.-]+)#} {}
            -re {@(\S+)\(.*}          {}
            -re {@(\S+)>}             {}
        }
        set prompt [string toupper $expect_out(1,string)]
        set hostname $prompt
        regsub      {/ACTNOFAILOVER}  $hostname "" hostname
        regsub      {/ACT}            $hostname "" hostname
        regsub      {/STBY}           $hostname "" hostname
        regsub -all {/}               $hostname "." hostname
        
        update_db_after_success $host $hostname $cred_id $dev_id $findonly
    }

    return $exit_code
}

exit [main $argv]
