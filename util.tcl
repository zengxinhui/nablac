namespace import tcl::mathop::**

# Utility helpers and constants for device collection scripts.
# These lists define which commands to run against each device type.

# IPs to be skipped (e.g. windows, linux)
set SKIPPED ""

# Database
package require sqlite3
set NABLAC_DB_NAME "net.db"
sqlite3 NABLAC_DB $NABLAC_DB_NAME

set PIX_commands {
    "sh route"
    "sh int"
    "sh arp"
    "sh ver"
    "sh fail"
    "sh conn"
    "sh clock"
}

set ASA_commands {
    "sh route | i ^C"
    "sh route | i ^S"
    "sh int"
    "sh inven"
    "sh arp"
    "sh ver"
    "sh fail"
    "show cryp ca cer"
    "sh conn"
    "sh xlate"
    "dir"
    "sh clock"
}

set IOS_commands {
    "sh ip ro con | i ^C"
    "sh ip ro sta | i ^S"
    "sh ip ro"
    "sh ip ro vrf *"
    "sh ip arp"
    "sh ip int b"
    "sh int"
    "sh mac add dyn"
    "sh mac- add dyn"
    "sh mac- dyn"
    "sh ip ospf nei"
    "sh ip ospf int b"
    "sh ip eig nei"
    "sh ip bgp sum"
    "sh ip bgp vpnv4 all sum"
    "sh ver"
    "sh inven"
    "dir"
    "sh cdp nei det"
    "sh power"
    "sh ip nat trans"
    "sh clock"
}

set NEXUS_commands {
    "sh ip ro vrf all dir"
    "sh ip ro vrf all sta"
    "sh ip ro vrf all"
    "sh ip arp vrf all"
    "sh ip int b vrf all"
    "sh int"
    "sh mac add"
    "sh ip ospf nei vrf all"
    "sh ip ospf int b vrf all"
    "sh ip eig nei vrf all"
    "sh ip bgp sum vrf all"
    "sh ver"
    "sh inven"
    "dir"
    "sh cdp nei det"
    "sh cdp nei"
    "sh module"
    "sh env power"
    "sh clock"
}

# Generate subnet masks programmatically
for {set i 0} {$i <= 32} {incr i} {
    set mask [expr {0xffffffff << (32 - $i) & 0xffffffff}]
    set ip1 [expr {($mask >> 24) & 0xff}]
    set ip2 [expr {($mask >> 16) & 0xff}]
    set ip3 [expr {($mask >> 8) & 0xff}]
    set ip4 [expr {$mask & 0xff}]
    set dotted "$ip1.$ip2.$ip3.$ip4"
    set subnetmask($dotted) [list [expr {1 << (32 - $i)}] $i]
}

proc sendexpect {s r} {
    # Send `s` followed by CR and wait for `r` pattern from expect
    send "$s\r"
    expect $r
}

proc logout {} {
    # Gracefully close remote session
    send "exit\r"
    expect {
        eof {}
        ">" {
            send "exit\r"
            expect eof
        }
    }
}

proc init {} {
    # Initialize session: detect prompt and set terminal options
    sendexpect "" "#"
    send "\r"

    expect {
        -re {[\n\r]([&\w/\.-]+)#} {
            set prompt $expect_out(1,string)
            set hostname [string toupper $prompt]
            set prompt "$prompt#"

            # Normalize hostname: remove common postfixes and slashes
            regsub {/ACTNOFAILOVER} $hostname "" hostname
            regsub {/ACT}           $hostname "" hostname
            regsub {/STBY}          $hostname "" hostname
            regsub -all {/}         $hostname "." hostname

            # Set terminal options to avoid pagers and length limits
            sendexpect "term len 0"   $prompt
            sendexpect "term wid 500" $prompt
            sendexpect "term pager 0" $prompt
            sendexpect "no pager"     $prompt
        }

        -re {[\n\r](\[.*\])} {
            # Alternate prompt style: [user@host:...]
            set prompt $expect_out(1,string)
            set hostname [string toupper $prompt]
            regsub {\[.*@} $hostname "" hostname
            regsub {:.*}   $hostname "" hostname
        }
    }

    return "$hostname $prompt"
}

proc login {hostip port user password enable} {
    # Returns:
    #   {0 spawn_id}   - Success
    #   {255 -1}       - Connection failed
    #   {254 -1}       - Password failed
    #   {253 -1}       - Enable failed

    # Attempt SSH first; fall back to telnet if SSH fails to spawn
    spawn ssh -p $port -l $user $hostip

    # Common pre-response handling: paging and interactive prompts
    expect_before {
        "continue connecting (yes/no" {
            send "yes\r"
            exp_continue
        }

        "you sure you want to continue" {
            send "yes\r"
            exp_continue
        }

        "<--- More --->" {
            send " "
            exp_continue
        }

        -nocase "Press X" {
            send "x\r"
            exp_continue
        }

        "REMOTE HOST IDENTIFICATION HAS CHANGED" {
            exec ssh-keygen -R $hostip
            return {1 -1}
        }
    }

    expect {
        eof {
            # SSH spawn failed; try telnet
            spawn telnet $hostip
            expect {
                eof { return {255 -1} }
                -re "sername:|ogin:" { send "$user\r" }
                -notransfer "assword:" {}
            }
        }

        -notransfer "assword:" {}
    }

    # Provide password when prompted
    expect "assword:"
    send "$password\r"
    expect {
        "#" {}

        "Authentication failed" {
            return {254 -1}
        }

        "Last failed login:" { exp_continue }

        "Failed logins"      { exp_continue }

        ">" {
            # Enter enable/privileged mode if available
            send "en\r"
            expect {
                "assword:" {
                    send "$enable\r"
                    expect {
                        "#" {}
                        ">" { return {253 -1} }
                        "assword:" { return {253 -1} }
                    }
                }
                "#" {}
                "incorrect" { return {253 -1} }
            }
        }

        -re "assword:|incorrect|failed|invalid|sername" { return {254 -1} }

        eof { return {254 -1} }
    }

    expect_before
    return [list 0 $spawn_id]
}

proc ip->int {ip} {
    # Convert dotted-decimal IP to 32-bit integer
    lassign [split $ip "."] ip1 ip2 ip3 ip4
    return [expr ((($ip1 * 256 + $ip2) * 256 + $ip3) * 256 + $ip4)]
}

proc parse_ip {filename devid} {
    # Parse IP address lines from device config/output and write
    # to database directly using sqlite3 package.
    global subnetmask

    if {![file exists $filename]} {
        color_puts "Error: Config file $filename not found."
        return
    }

    NABLAC_DB transaction {
        NABLAC_DB eval {delete from ip where dev_id=$devid}
        
        set fp [open $filename r]
        while {[gets $fp line] >= 0} {
            set ip ""
            set mask ""
            set is_host 0

            if {[regexp {ip address ([\d\.]+) ([\d\.]+)} $line _ ip mask]} {
                # Standard IP Mask
            } elseif {[regexp {ip address ([\d\.]+)/([\d\.]+)} $line _ ip mask]} {
                # CIDR
            } elseif {[regexp {ip address \w+ ([\d\.]+) ([\d\.]+)} $line _ ip mask]} {
                # Secondary/Other
            } elseif {[regexp {standby \d+ ip ([\.\d]+)} $line _ ip]} {
                set mask 32
                set is_host 1
            } elseif {[regexp {^\s+ip ([\d\.]+)} $line _ ip]} {
                set mask 32
                set is_host 1
            }

            if {$ip ne ""} {
                if {$is_host} {
                    set ips [ip->int $ip]
                    NABLAC_DB eval {insert into ip (dev_id, ip_start, ip, mask) values ($devid, $ips, $ip, 32)}
                } else {
                    # Handle mask conversion if needed
                    if {[string first "." $mask] != -1} {
                        # Dotted mask
                        if {[info exists subnetmask($mask)]} {
                            lassign $subnetmask($mask) ip0 mask_bits
                            set ips [ip->int $ip]
                            set ips [expr {$ips - ($ips % $ip0)}]
                            NABLAC_DB eval {insert into ip (dev_id, ip_start, ip, mask) values ($devid, $ips, $ip, $mask_bits)}
                        }
                    } else {
                        # CIDR mask
                        set mask_bits $mask
                        set ip0 [expr {1 << (32 - $mask_bits)}]
                        set ips [ip->int $ip]
                        set ips [expr {$ips - ($ips % $ip0)}]
                        NABLAC_DB eval {insert into ip (dev_id, ip_start, ip, mask) values ($devid, $ips, $ip, $mask_bits)}
                    }
                }
            }
        }
        close $fp
    }
}

proc color_send {color msg} {
    # Print colored text to the user (using ANSI escape codes)
    send_user "\033\[1;${color}m${msg}\033\[0m"
}

proc color_puts {msg} {
    # Error-style red output
    send_error "\033\[1;31m${msg}\033\[0m"
}
