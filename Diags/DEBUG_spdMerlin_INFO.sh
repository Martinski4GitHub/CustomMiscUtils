#!/bin/sh
###########################################################
# DEBUG_spdMerlin_INFO.sh
# Last Modified: 2025-Jul-19 [Martinski W.]
#----------------------------------------------------------
set -u
readonly VERSION="0.6.2"
readonly VERSTAG=25071922
readonly DEBUGTAG="${VERSION}_${VERSTAG}"

_GetDebugInfo_()
{
   date +'%Y-%b-%d %I:%M:%S %p %Z'
   echo "DEBUG_TAG: $DEBUGTAG"
   echo "$(nvram get firmver).$(nvram get buildno).$(nvram get extendno)"
   nvram show 2>/dev/null | grep -E 'wan[0-1]_(primary=1|ifname=e.*)'
   grep "^readonly SCRIPT_VERSION=" /jffs/scripts/spdmerlin
   spdMerlinDIR="spdmerlin.d"
   for dirPATH in /jffs/addons /opt/share
   do
       if [ -d "$dirPATH/$spdMerlinDIR" ]
       then
           echo "========================================"
           printf "${dirPATH}/\n---------------\n"
           ls -1lA "$dirPATH/$spdMerlinDIR"
           if [ ! -f "$dirPATH/$spdMerlinDIR/config" ]
           then continue
           fi
           for theFile in config .interfaces .interfaces_user
           do
               if [ -f "$dirPATH/$spdMerlinDIR/$theFile" ]
               then
                   echo "================="
                   printf "${theFile}:\n-----------------\n"
                   ls -1l "$dirPATH/$spdMerlinDIR/$theFile"
                   echo "------------------------------"
                   cat "$dirPATH/$spdMerlinDIR/$theFile"
                   echo "------------------------------"
               fi
           done
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

logFILE="$HOME/spdMerlin_${theTAG:0:5}_$(date +'%Y%m%d_%H%M%S').LOG"
_GetDebugInfo_ > "$logFILE"
printf "\nDebug file '$logFILE' was created.\n\n"

#EOF#
