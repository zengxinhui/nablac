#!/bin/expect -f

source "util.tcl"

lassign $argv host
set timeout 1800

NABLAC_DB eval {select username,password,enable,hostname,ip from cred, devices as d where cred.cred_id=d.cred_id and ip=$host and dev_id>0} {
    set user   $username
    set pass   $password
    set enable $enable
    set host   $ip
}
lassign [login $host 22 $user $pass $enable] status spawn_id
lassign [init] hostname prompt

send "sh clock\r"
expect {
  "UTC"     { set TimeZone "UTC"     }
  "gmt"     { set TimeZone "UTC"     }
  "EDT"     { set TimeZone "EST5EDT" }
  "EST"     { set TimeZone "EST5EDT" }
  "MDT"     { set TimeZone "MST7MDT" }
  "MST"     { set TimeZone "MST7MDT" }
  "eastern" { set TimeZone "EST5EDT" }
  -notransfer $prompt
}
expect $prompt

set currentTime [clock seconds]
set formattedTime [clock format $currentTime -timezone $TimeZone -format "clock set %H:%M:%S %b %d %Y"]
sendexpect $formattedTime $prompt
sendexpect "sh clock"     $prompt
logout
