#!/bin/sh
####################################################################
# SendWakeOnLAN.sh
#
# To send Wake-on-LAN (WoL) "magic packet" to specific clients.
# This assumes that a DHCP IP address reservation has previously
# been made for and assigned to the specific device MAC address.
#
# ARG1: Client MAC address.
# ARG2: Client Private IPv4 address.
# ARG3: Interface to which client is connected.
# ARG4: Number of seconds to wait for client to wake up.
#
# Creation Date: 2022-Jan-16 [Martinski W.]
# Last Modified: 2024-Apr-23 [Martinski W.]
####################################################################
set -u

readonly SCRIPT_VERSION=0.2.7
readonly scriptFilePath="$0"
readonly scriptFileName="${0##*/}"
readonly scriptFNameTag="${scriptFileName%%.*}"
readonly logTagStr="${scriptFNameTag}_[$$]"

readonly pLogALERT=1
readonly pLogCRITC=2
readonly pLogERROR=3
readonly pLogWARNG=4
readonly pLogNOTIC=5
readonly pLogINFOR=6

readonly CLEARct="\e[0m"
readonly REDct="\e[1;31m"
readonly GREENct="\e[1;32m"
readonly YELLWct="\e[1;33m"
readonly MAGNTct="\e[1;35m"
readonly ERRORct="$REDct"
readonly WARNGct="$YELLWct"

readonly MAX_WOLcount=3
readonly MAX_PingCount=4
readonly INIT_Wait2ExitSecs=5
readonly MAX_Wait2ExitSecs=10

#-------------------------------------------------------#
# Allow sufficient time for client devices to "wake up" #
# 4 minutes should be more than enough for slow clients #
#-------------------------------------------------------#
readonly MIN_Wait2WakeUpSecs=30
readonly MAX_Wait2WakeUpSecs=240
readonly wait2WakeUpSecs1=10
readonly wait2WakeUpSecs2=20

# To check MAC address syntax #
readonly MACaddrs_RegEx="([a-fA-F0-9]{2}\:){5}([a-fA-F0-9]{2})"

# To check IPv4 address syntax #
readonly IPv4octet_RegEx="([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])"
readonly IPv4addrs_RegEx="((${IPv4octet_RegEx}\.){3}${IPv4octet_RegEx})"
readonly IPv4privt_RegEx="((^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.))"

#------------------------------------------------------------#
# This is an optional parameter. Often, it's not needed, but
# in some enviroments it is, so modify it IF required here.
#------------------------------------------------------------#
readonly doWoLBroadcastPacket=false
if ! "$doWoLBroadcastPacket"
then readonly bWoLopt=""
else readonly bWoLopt="-b"
fi

readonly WoLcmd="$(which ether-wake)"
readonly pingRegExp="[0-9]+ packets transmitted, [0-9]+ packets received, [0-9]+[%] packet loss"

if [ -t 0 ] && ! tty | grep -qwi "NOT"
then readonly isInteractive=true
else readonly isInteractive=false
fi

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

#--------------------------------------------------#
_LogMsg_()
{
   if [ $# -lt 1 ] || [ -z "$1" ]
   then return 1
   fi
   if [ $# -lt 2 ] || [ -z "$2" ] || \
      ! echo "$2" | grep -qE "^[1-6]$"
   then logPrioNum="$pLogNOTIC"
   else logPrioNum="$2"
   fi
   if "$isInteractive" && \
      { [ $# -lt 3 ] || [ "$3" != "NOECHO" ] ; }
   then
       if [ "$logPrioNum" -gt "$pLogWARNG" ]
       then printf "${1}\n"
       elif [ "$logPrioNum" -eq "$pLogWARNG" ]
       then printf "${WARNGct}${1}${CLEARct}\n"
       else printf "${ERRORct}${1}${CLEARct}\n"
       fi
   fi
   if [ $# -lt 3 ] || [ "$3" != "NOLOG" ]
   then
       logger -t "$logTagStr" -p "$logPrioNum" "$1"
   fi
}

#--------------------------------------------------#
_DoExit_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then exit 0
   fi
   local exitCode=0  exitMsg="$1"

   if [ $# -gt 1 ] && [ -n "$2" ]
   then
       exitMsg="${1}: Code $2"
       exitCode="$2"
   fi

   _LogMsg_ "$exitMsg"
   exit "$exitCode"
}

#--------------------------------------------------#
_Validate_MACaddr_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE "^${MACaddrs_RegEx}$"
   then return 1
   else return 0
   fi
}

#--------------------------------------------------#
_Validate_PrivateIPv4addr_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE "^${IPv4addrs_RegEx}$" || \
      ! echo "$1" | grep -qE "^${IPv4privt_RegEx}"
   then return 1
   else return 0
   fi
}

#--------------------------------------------------#
_Validate_IPv4addr_OnInterface_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1
   fi

   netIPinfo="$(ip route show | grep -E "dev[[:blank:]]+${2}[[:blank:]]+proto kernel")"

   [ -z "$netIPinfo" ] && return 1
   netIPaddr="$(echo "$netIPinfo" | awk -F ' ' '{print $1}')"

   [ "${1%.*}." = "${netIPaddr%.*}." ] && return 0 || return 1
}

#----------------------------------------------------------------#
_Send_WoL_Packet_()
{
   if [ $# -lt 4 ] || \
      [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] 
   then
       LOG_MSG="NO arguments were given."
       _LogMsg_ "$LOG_MSG" "$pLogERROR" NOLOG
       return 1
   fi
   local errorFound=false

   if ! _Validate_MACaddr_ "$1"
   then
       errorFound=true
       LOG_MSG="MAC address [$1] is NOT valid."
       _LogMsg_ "$LOG_MSG" "$pLogERROR"
   fi

   if ! _Validate_PrivateIPv4addr_ "$2"
   then
       errorFound=true
       LOG_MSG="IPv4 address [$2] is NOT valid or private."
       _LogMsg_ "$LOG_MSG" "$pLogERROR"
   fi

   if ! _Validate_IPv4addr_OnInterface_ "$2" "$3"
   then
       errorFound=true
       LOG_MSG="IPv4 address [$2] is NOT in the subnet for [$3] interface."
       _LogMsg_ "$LOG_MSG" "$pLogERROR"
   fi
   "$errorFound" && return 1

   local wolCount=0  pingStats  pingStatsOK=false  pingWait2ExitSecs
   local wait2WakeUpCountSecs=0  wait2WakeUpPhase=false  wait2WakeUpSecs
   local maxWait2WakeUpSecs isFirstTime=false  retCode=0

   local MACxAddr="$1"
   local IPv4Addr="$2"
   local IFaceIDx="$3"

   if echo "$4" | grep -qE "^[1-9][0-9]+$" && \
      [ "$4" -ge "$MIN_Wait2WakeUpSecs" ] && \
      [ "$4" -le "$MAX_Wait2WakeUpSecs" ]
   then maxWait2WakeUpSecs="$4"
   else maxWait2WakeUpSecs="$MAX_Wait2WakeUpSecs"
   fi

   _AllowTime2WakeUp_()
   {
      if [ $# -eq 0 ] || [ -z "$1" ]
      then
          isFirstTime=false
          wait2WakeUpSecs="$wait2WakeUpSecs1"
      else
          isFirstTime=true
          wait2WakeUpSecs="$wait2WakeUpSecs2"
      fi
      sleep "$wait2WakeUpSecs"
      wait2WakeUpCountSecs="$((wait2WakeUpCountSecs + wait2WakeUpSecs))"
   }

   while true
   do
       if [ "$wolCount" -eq 0 ] && \
          [ "$wait2WakeUpCountSecs" -eq 0 ]
       then pingWait2ExitSecs="$INIT_Wait2ExitSecs"
       else pingWait2ExitSecs="$MAX_Wait2ExitSecs"
       fi

       pingStats="$(ping -c "$MAX_PingCount" -w "$pingWait2ExitSecs" "$IPv4Addr" | grep -E "$pingRegExp")"
       if [ -n "$pingStats" ]
       then
           tempPingStats="$(echo "$pingStats" | sed 's/%/%%/g')"
           _LogMsg_ "Ping Stats: [$tempPingStats][$wait2WakeUpCountSecs]" "$pLogINFOR" NOLOG
       fi

       if [ "$wolCount" -ge "$MAX_WOLcount" ] && \
          [ "$wait2WakeUpCountSecs" -ge "$maxWait2WakeUpSecs" ]
       then break
       fi

       if echo "$pingStats" | grep -q " 0% packet loss"
       then
           pingStatsOK=true
           LOG_MSG="Successful pings to [$IPv4Addr --> $MACxAddr][${wolCount}/${MAX_WOLcount}]"
           _LogMsg_ "$LOG_MSG" "$pLogNOTIC"
           break
       fi

       if "$wait2WakeUpPhase" && \
          [ "$wait2WakeUpCountSecs" -lt "$maxWait2WakeUpSecs" ]
       then
           "$isFirstTime" && \
           printf "WoL wait count: %s seconds\n" "${wait2WakeUpCountSecs}/${maxWait2WakeUpSecs}" 2>&1
           _AllowTime2WakeUp_
           printf "WoL wait count: %s seconds\n" "${wait2WakeUpCountSecs}/${maxWait2WakeUpSecs}" 2>&1
           continue
       fi

       wolCount="$((wolCount + 1))"
       LOG_MSG="Sending WoL packet to client [$IPv4Addr --> $MACxAddr][${wolCount}/${MAX_WOLcount}]"
       _LogMsg_ "$LOG_MSG" "$pLogWARNG"

       $WoLcmd $bWoLopt -i "$IFaceIDx" "$MACxAddr"

       wait2WakeUpPhase=true
       wait2WakeUpCountSecs=0
       _AllowTime2WakeUp_ 2
   done

   if "$pingStatsOK" && [ "$wolCount" -le "$MAX_WOLcount" ]
   then
       retCode=0
       logType="$pLogNOTIC"
       LOG_MSG="Client [$IPv4Addr $MACxAddr $IFaceIDx] is awake & responding."
   else
       retCode=1
       logType="$pLogERROR"
       LOG_MSG="WoL to client [$IPv4Addr $MACxAddr $IFaceIDx] was *NOT* successful."
   fi

   _LogMsg_ "$LOG_MSG" "$logType"
   return "$retCode"
}

if [ -n "$*" ]
then
    printf "\n$logTagStr ARGs: [$*]\n"
fi

if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
then
    _LogMsg_ "NO arguments were given." "$pLogERROR"
    _DoExit_ "ERROR" 1
fi

if [ $# -gt 3 ] && [ -n "$4" ]
then maxWaitSecs="$4"
else maxWaitSecs="$MAX_Wait2WakeUpSecs"
fi

# ARGS: "MAC_Address" "IPv4_Address" "InterfaceID" "MaxWaitSecs" #
_Send_WoL_Packet_ "$1" "$2" "$3" "$maxWaitSecs"

_DoExit_ "EXIT" "$?"

#EOF#
