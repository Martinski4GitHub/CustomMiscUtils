#!/bin/sh
###########################################################
# DEBUG_ntpMerlin_INFO.sh
# Last Modified: 2025-Jul-29 [Martinski W.]
#----------------------------------------------------------
set -u
readonly VERSION="0.5.1"
readonly VERSTAG=25072920

_GetDebugDataNTPMerlin_()
{
   echo "-----------------------------------"
   date +'%Y-%b-%d %I:%M:%S %p %Z'
   theScriptPATH="/jffs/scripts/ntpmerlin"
   grep "^SCRIPT_BRANCH=" "$theScriptPATH"
   grep "^readonly SCRIPT_VERSION=" "$theScriptPATH"
   grep "^readonly SCRIPT_VERSTAG=" "$theScriptPATH"
   echo "F/W: $(nvram get firmver).$(nvram get buildno).$(nvram get extendno)"
   echo "-----------------------------------"
   printf "NTP Packages:\n-------------\n"
   opkg list-installed | grep -E "ntp|chrony"
   echo "-----------------------------------"
   ls -1l /opt/etc/init.d | grep -E "ntpd|chronyd"
   if [ -f /opt/etc/init.d/S77ntpd ]
   then
       echo "-----------------------------------"
       printf "NTPD:\n-----\n"
       cat /opt/etc/init.d/S77ntpd
       echo "-----------------------------------"
       printf "Check NTPD:\n-----------\n"
       /opt/etc/init.d/S77ntpd check ; echo
       top -b -n 1 | grep -E "ntpd|timeserverd" | grep -v grep
   fi
   if [ -f /opt/etc/init.d/S77chronyd ]
   then
       echo "-----------------------------------"
       printf "CHRONYD:\n--------\n"
       cat /opt/etc/init.d/S77chronyd
       echo "-----------------------------------"
       printf "Check CHRONYD:\n--------------\n"
       /opt/etc/init.d/S77chronyd check ; echo
       ls -l /opt/etc/passwd ; echo
       top -b -n 1 | grep -E "chronyd|timeserverd" | grep -v grep
   fi
   echo "-----------------------------------"
   theScriptDIR="ntpmerlin.d"
   for dirPATH in /jffs/addons /opt/share
   do
       if [ -d "$dirPATH/$theScriptDIR" ]
       then
           echo "========================================"
           printf "${dirPATH}/\n---------------\n"
           ls -1lA "$dirPATH/$theScriptDIR"
           if [ ! -f "$dirPATH/$theScriptDIR/config" ]
           then continue
           fi
           if [ -f "$dirPATH/$theScriptDIR/config" ]
           then
               echo "================="
               printf "CONFIG file:\n------------\n"
               ls -1l "$dirPATH/$theScriptDIR/config"
               echo "------------------------------"
               cat "$dirPATH/$theScriptDIR/config"
               echo "------------------------------"
           fi
       fi
   done
}

theTAG="DEBUG"
if [ $# -gt 0 ]
then
   if echo "$1" | grep -qE "^(before|after)$"
   then
       theTAG="$(echo "$1" | tr 'a-z' 'A-Z')"
   else
       printf "\nUNKNOWN Parameter [$*].\n"
       printf "Use either 'before' or 'after' parameter.\n"
       printf "Setting a 'DEBUG' tag for now.\n\n"
   fi
fi

logFILE="$HOME/ntpMerlin_${theTAG:0:5}_$(date +'%Y%m%d_%H%M%S').LOG"
_GetDebugDataNTPMerlin_ | tee "$logFILE"
printf "\nDebug file '$logFILE' was created.\n\n"

#EOF#
