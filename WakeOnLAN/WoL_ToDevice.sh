#!/bin/sh
######################################################################
# WoL_ToDevice.sh
#
# To send Wake-on-LAN (WoL) "magic packet" to specific LAN devices.
# This assumes that a DHCP IP address reservation has previously
# been made for and assigned to the specific device MAC address.
#
# ARG1: Device Hostname ID
#
# Creation Date: 2022-Jan-16 [Martinski W.]
# Last Modified: 2022-Nov-04 [Martinski W.]
######################################################################
set -u

readonly SCRIPT_VERSION=0.1.5
readonly scriptFilePath="$0"
readonly scriptFileName="${0##*/}"
readonly scriptFNameTag="${scriptFileName%%.*}"
readonly logTagStr="${scriptFNameTag}_[$$]"
readonly pLogERROR=3
readonly WoL_ScriptFPath="/jffs/scripts/SendWakeOnLAN.sh"

doExit=false

if [ $# -eq 0 ] || [ -z "$1" ]
then
    doExit=true
    LOG_MSG="**ERROR**: Device Hostname ID *NOT* provided."
    logger -st "$logTagStr" -p "$pLogERROR" "$LOG_MSG"
fi

if [ ! -s "$WoL_ScriptFPath" ]
then
    doExit=true
    LOG_MSG="**ERROR**: WoL script file [$WoL_ScriptFPath] *NOT* found."
    logger -st "$logTagStr" -p "$pLogERROR" "$LOG_MSG"
fi

if "$doExit"
then
    printf "\nExiting...\n\n"
    exit 1
fi

# Modify these IF needed in the case statement for each specific device #
IFaceIDx=br0
wolWaitSecs=40

#-------------------------------------------------------------#
# The value for 'wolWaitSecs' must be >= 30 and <= 240 secs.
# It's the maximum number of seconds to wait for the device 
# to "wake up" after the WoL command has been sent.
#-------------------------------------------------------------#

#-------------------------------------------------------------#
# The case statements below are just a TEMPLATE. You *MUST*
# set the actual values based on your specific LAN devices.
#-------------------------------------------------------------#

case "$1" in
    devHostnameID1)
        MACxAddr="AA:BB:CC:DD:EE:F1"
        IPv4Addr="192.168.200.100"
        ;;
    devHostnameID2)
        MACxAddr="AA:BB:CC:DD:EE:F2"
        IPv4Addr="192.168.200.102"
        wolWaitSecs=60
        ;;
    devHostnameID3)
        MACxAddr="AA:BB:CC:DD:EE:F3"
        IPv4Addr="192.168.200.104"
        wolWaitSecs=90
        ;;
    *)
       LOG_MSG="**ERROR**: Device Hostname ID [$1] is UNKNOWN."
       logger -st "$logTagStr" -p "$pLogERROR" "$LOG_MSG"
       exit 1
       ;;
esac

if [ ! -x "$WoL_ScriptFPath" ]
then chmod 755 "$WoL_ScriptFPath"
fi

$WoL_ScriptFPath "$MACxAddr" "$IPv4Addr" "$IFaceIDx" "$wolWaitSecs"
exit $?

#EOF#
