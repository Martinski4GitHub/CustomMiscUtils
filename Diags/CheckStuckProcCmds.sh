#!/bin/sh
######################################################################
# CheckStuckProcCmds.sh
#
# To monitor & check if any 'nvram' or 'wl' commands are running
# and see if there's a hang during execution of such commands.
# When such a "stuck" command is found, this script also kills
# the process after a short wait (~10 secs) & logs the event.
#
# EXAMPLE CALLS:
# ./CheckStuckProcCmds.sh
# ./CheckStuckProcCmds.sh -help
# ./CheckStuckProcCmds.sh -setcronjob
# ./CheckStuckProcCmds.sh -setcronjob=3
# ./CheckStuckProcCmds.sh -delcronjob
# ./CheckStuckProcCmds.sh -checkupdate
#---------------------------------------------------------------------
# Creation Date: 2022-Jun-12 [Martinski W.]
# Last Modified: 2026-May-02 [Martinski W.]
#
readonly SCRIPT_VERSION="0.7.14"
readonly SCRIPT_VERSTAG="26050205"
######################################################################
set -u 

#--------------------------------------------#
# START CUSTOMIZABLE PARAMETERS SECTION.
#--------------------------------------------#
# Cron Job default frequency in minutes #
CRON_Mins=6   #[Mins >= 2 && Mins <= 60]#

# Modify these variables as necessary for your environment #
TheLOGdir="/opt/var/log"          # LOG directory #
TheTRCdir="/opt/var/log/Trace"    # TRACE directory #
#--------------------------------------------#
# END CUSTOMIZABLE PARAMETERS SECTION.
#--------------------------------------------#

export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

ScriptFName1="${0##*/}"
ScriptFName2="${ScriptFName1%.*}"
ScriptFolder="$(/usr/bin/dirname "$0")"
readonly thePID="$(printf "%05d" "$$")"

readonly SCRIPT_FNAME="CheckStuckProcCmds.sh"
readonly SCRIPT_BRANCH="master"
readonly SCRIPT_URL_GH="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${SCRIPT_BRANCH}/Diags"

DoMyLogger=1
ShowDebugMsgs=0
ShowMyDbgMsgs=0

CRON_Set=0
readonly UseKillCmd=1
readonly doDelaySecs=8
readonly MaxDiffSecs=5
readonly MaxTraceIndex=99999
readonly CRON_Tag="CheckStuckCmds"
readonly CRU_Cmd="/usr/sbin/cru"

if [ "$ScriptFolder" != "." ]
then
   ScriptFPath="$0"
else
   ShowDebugMsgs=1
   ScriptFolder="$(pwd)"
   ScriptFPath="$(pwd)/$ScriptFName1"
fi

readonly NOct="\e[0m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly YLWct="\e[1;33m"
readonly MGNTct="\e[1;35m"

readonly echoCMD=/bin/echo
readonly _25KBytes=25600
readonly MaxLogSize=$_25KBytes

TheLOGtag=""
TheBKPtag="_BKP"
SetBKPLogFile=1
readonly DEF_LOG_Dir="/tmp/var/tmp"
readonly DEF_TRC_Dir="/tmp/var/tmp"

[ ! -d "$TheLOGdir" ] && mkdir "$TheLOGdir" 2>/dev/null
[ ! -d "$TheTRCdir" ] && mkdir "$TheTRCdir" 2>/dev/null

[ ! -d "$TheLOGdir" ] && TheLOGdir="$DEF_LOG_Dir"
[ ! -d "$TheTRCdir" ] && TheTRCdir="$DEF_TRC_Dir"
[ ! -d "$TheTRCdir" ] && mkdir "$TheTRCdir" 2>/dev/null

readonly TheLogName="${ScriptFName2}${TheLOGtag}"
readonly BkpLogName="${TheLogName}${TheBKPtag}"

readonly TheLogFile="${TheLOGdir}/${TheLogName}.LOG"
readonly BkpLogFile="${TheLOGdir}/${BkpLogName}.LOG"

readonly ScriptNDXname="${ScriptFName2}.INDX.txt"
readonly StuckCmdsNDXfile="${TheTRCdir}/${ScriptNDXname}"

## File to store LAST known process cmds possibly "stuck" ##
readonly StuckCmdsLOGname="StuckProcCmds"
readonly StuckCmdsLOGfile="${TheLOGdir}/${StuckCmdsLOGname}.LOG.txt"

## 24-hour format (e.g. "2020-03-01 15:19:14") ##
readonly SysLogTimeFormat="%Y-%m-%d %H:%M:%S"

## 12-hour format (e.g. "2020-Mar-01 03:19:14 PM") ##
readonly MyLogTimeFormat="%Y-%b-%d %I:%M:%S %p"

readonly CronMins0RegExp="([0-9]|[1-5][0-9])"
readonly CronMins1RegExp="[2-6]|10|11|12|15|20|30|60"
readonly CronMins2RegExp="${CronMins0RegExp}(,${CronMins0RegExp})+"
readonly CronMins3RegExp="${CronMins0RegExp}-${CronMins0RegExp}/${CronMins0RegExp}"
readonly CronMinsXRegExp="(${CronMins1RegExp}|${CronMins2RegExp}|${CronMins3RegExp})"

# The "delete mark" #
readonly DelMark="**=OK=**"

##################################################################
_ShowUsage_()
{
   printf "\nVersion: ${GRNct}${SCRIPT_VERSION}_${SCRIPT_VERSTAG}${NOct}\n"
   cat <<EOF
-----------------------------------------------
SYNTAX:

./$ScriptFName1 [ help | vers | -setcronjob | -setcronjob=N | -delcronjob | -checkupdate ]

Where 'N' is the CRON Job run frequency in minutes.
[Minutes >= 2 && Minutes <= 60]

Current location of log files: [$TheLOGdir]
Current location of trace files: [$TheTRCdir]

You can set new directory locations by modifying the
variables "TheLOGdir" & "TheTRCdir" found at the top
of the script file (CUSTOMIZABLE PARAMETERS SECTION).

EXAMPLE CALLS:

To run & check for any "stuck" 'nvram' or 'wl' commands:
   ./$ScriptFName1

To get this usage & syntax description:
   ./$ScriptFName1 help

To show current script version:
   ./$ScriptFName1 vers

To create a CRON Job to run every 6 minutes [DEFAULT]:
   ./$ScriptFName1 -setcronjob

To create a CRON Job to run every 3 minutes [new interval]:
   ./$ScriptFName1 -setcronjob=3

To delete any existing CRON Job:
   ./$ScriptFName1 -delcronjob

To check for and install the latest script version update:
   ./$ScriptFName1 -checkupdate
-----------------------------------------------
EOF
}

#################################################################
_ShowVersion_()
{ printf "\nVersion: ${GRNct}${SCRIPT_VERSION}${NOct}\n\n" ; }

#################################################################
_GetFileSize_()
{
   local theFileSize=0
   if [ $# -eq 1 ] && [ -n "$1" ] && [ -f "$1" ]
   then
      theFileSize="$(ls -AlF "$1" | awk -F ' ' '{print $5}')"
   fi
   echo "$theFileSize"
}

################################################################
_CheckMyLogFileSize_()
{
   [ ! -s "$TheLogFile" ] && return 1

   local TheFileSize=0
   TheFileSize="$(_GetFileSize_ "$TheLogFile")"

   if [ "$TheFileSize" -gt "$MaxLogSize" ]
   then
      if [ "$SetBKPLogFile" -eq 1 ]
      then
         cp -fp "$TheLogFile" "$BkpLogFile"
      fi
      rm -f "$TheLogFile"

      LogMsg="Deleted $TheLogFile [$TheFileSize]"
      _ShowDebugMsg_ "INFO: $LogMsg"
   fi
}

################################################################
_DoInitMyLogFile_()
{
   [ "$DoMyLogger" -eq 0 ] && return 1
   _CheckMyLogFileSize_
   [ ! -f "$TheLogFile" ] && touch "$TheLogFile"
}

################################################################
_ShowMyDGBMsg_()
{
   [ "$ShowMyDbgMsgs" -eq 0 ] && return 1

   if [ $# -eq 0 ]
   then echo ""
   elif [ $# -eq 1 ]
   then echo "$1"
   else echo "${1}:" "$2"
   fi
}

##################################################################
_ShowDebugMsg_()
{
   [ "$ShowDebugMsgs" -eq 0 ] && return 1

   if [ $# -eq 0 ]
   then echo ""
   elif [ $# -eq 1 ]
   then echo "$1"
   else echo "${1}:" "$2"
   fi
}

################################################################
_GetLastLineFromFile_()
{
   local theFileSize  theLastLine=""

   if [ $# -eq 1 ] && [ -n "$1" ] && [ -s "$1" ]
   then
      theFileSize="$(_GetFileSize_ "$1")"
      if [ "$theFileSize" -gt 0 ]
      then theLastLine="$(tail -n 1 "$1")"
      fi
   fi
   echo "$theLastLine"
}

################################################################
_LastLogFileLineEmpty_()
{
   local theLastLine=""
   theLastLine="$(_GetLastLineFromFile_ "$TheLogFile")"
   if [ -z "$theLastLine" ]
   then return 0
   else return 1
   fi
}

################################################################
_EscapeChars_()
{ printf "%s\n" "$1" | sed 's/[]{}[\/$.*^&+-]/\\&/g' ; }

################################################################
_DeleteLastLogFileLineMarked_()
{
   local markedLine=0  theLastLine

   theLastLine="$(_GetLastLineFromFile_ "$TheLogFile")"
   [ -z "$theLastLine" ] && return 1

   markedLine="$($echoCMD "$theLastLine" | grep -c "$(_EscapeChars_ "$DelMark")$")"

   if [ "$markedLine" -gt 0 ]
   then sed -i '$d' "$TheLogFile"
   fi
}

##################################################################
_AddMsgsToMyLog_()
{
   [ "$DoMyLogger" -eq 0 ] && return 1

   local TimeNow  HourMinsNow

   HourMinsNow="$(date +"%I:%M %p")"
   TimeNow="$(date +"$MyLogTimeFormat")"

   if [ $# -eq 0 ]
   then
       echo "" >> "$TheLogFile"
   elif \
      [ $# -eq 1 ]
   then
       echo "$TimeNow $1" >> "$TheLogFile"
   elif \
      [ "$1" = "_NOTIME_" ]
   then
       ## Output *WITHOUT* a TimeStamp ##
       echo "$2" >> "$TheLogFile"
   elif \
      [ "$1" = "_ADDnoMARK_" ] || [ "$1" = "_ADDwithMARK_" ]
   then
       local LogMsg="${TimeNow} ${2}"
       _DeleteLastLogFileLineMarked_

       if [ "$1" = "_ADDnoMARK_" ] || \
          { [ "$HourMinsNow" = "12:00 PM" ] || \
            [ "$HourMinsNow" = "12:07 PM" ] ; }
       then
           ## Output msg WITHOUT being "marked" ##
           echo "$LogMsg" >> "$TheLogFile"
       elif \
          [ "$1" = "_ADDwithMARK_" ]
       then
           ## Output "MARKED" msg (to be deleted later) ##
           $echoCMD "$LogMsg $DelMark" >> "$TheLogFile"
       fi
   else
       echo "$TimeNow ${1}: $2" >> "$TheLogFile"
   fi
}

################################################################
_AddMsgToMyLogNoTime_()
{
   _ShowDebugMsg_ "$1"
   _AddMsgsToMyLog_ "_NOTIME_" "$1"
}

################################################################
_AddMsgsToLogs_()
{
   if [ $# -eq 0 ]
   then
       _AddMsgsToMyLog_
   elif [ $# -eq 1 ]
   then
       _AddMsgsToMyLog_ "$1"
   elif [ $# -eq 2 ]
   then
       _AddMsgsToMyLog_ "$1" "$2"
   fi
}

################################################################
_AddDebugLogMsgs_()
{
   if [ $# -eq 0 ]
   then
       _ShowDebugMsg_
       _AddMsgsToMyLog_
   elif [ $# -eq 1 ]
   then
       _ShowDebugMsg_ "$1"
       _AddMsgsToMyLog_ "$1"
   elif [ $# -eq 2 ]
   then
       _ShowDebugMsg_ "$1" "$2"
       _AddMsgsToMyLog_ "$1" "$2"
   fi
}

#################################################################
_ValidCronJobMinutes_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then return 1
   fi
   local retCode=1

   case "$1" in
       [3-6]|10|11|12|15|20|30|60)
          retCode=0 ;;
       *)
          echo "*ERROR*: INVALID number of minutes [$1] for cron job."
          retCode=1 ;;
   esac
   return "$retCode"
}

#################################################################
# To avoid using the "cru l" cmd which calls the "nvram" cmd
# which may hang in some cases.
#################################################################
_GetCronJobList_()
{
   local cronJobListFile  cronJobListStr=""
   local cronTabsDirPath="/var/spool/cron/crontabs"

   if [ ! -d "$cronTabsDirPath" ]
   then echo ; return 1
   fi

   cronJobListFile="$(ls -1 "$cronTabsDirPath" | grep -vE "cron.[*]*|.*.new$")"
   if [ -n "$cronJobListFile" ]
   then
      cronJobListStr="$(cat "${cronTabsDirPath}/$cronJobListFile")"
   fi

   echo "$cronJobListStr"
   return 0
}

##################################################################
_CheckForCronJobSetup_()
{
   [ "$CRON_Set" -eq 0 ] && return 1

   local theCronMins="*/10"
   local cronMin=""  cronTag=""  jobPath=""  jobStr=""
   local CRU_Tag="#${CRON_Tag}#"  setCRONjob=false

   if [ "$CRON_Mins" = "60" ]
   then theCronMins=0
   elif echo "$CRON_Mins" | grep -qE "^(${CronMins1RegExp})$"
   then theCronMins="*/$CRON_Mins"
   else theCronMins="$CRON_Mins"
   fi

   jobStr="$(_GetCronJobList_ | grep " $ScriptFPath ")"
   if [ -n "$jobStr" ]
   then
      cronMin="$(echo "$jobStr" | awk -F ' ' '{print $1}')"
      jobPath="$(echo "$jobStr" | awk -F ' ' '{print $6}')"
      cronTag="$(echo "$jobStr" | awk -F ' ' '{print $7}')"

      if [ "$cronTag" != "$CRU_Tag" ]    || \
         [ "$cronMin" != "$theCronMins" ] || \
         [ "$jobPath" != "$ScriptFPath" ]
      then
         cronTag="$(echo "$cronTag" | sed "s/#//g")"
         $CRU_Cmd d "$cronTag" ; sleep 2
         jobStr="$(_GetCronJobList_ | grep " $ScriptFPath ")"
         if [ -z "$jobStr" ]
         then
             setCRONjob=true
             LogMsg="Previous CRON Job [#${cronTag}#] was DELETED."
             _AddDebugLogMsgs_ "INFO: $LogMsg"
         else
             printf "CRON Job [#${cronTag}#] was NOT deleted."
         fi
      else
         LogMsg="The CRON Job [#${cronTag}#] is already FOUND."
         _AddDebugLogMsgs_ "INFO: $LogMsg"
         _AddMsgToMyLogNoTime_ "CRON: [$jobStr]"
      fi
   fi

   if [ -z "$jobStr" ] || "$setCRONjob"
   then
      $CRU_Cmd a $CRON_Tag "$theCronMins  *  *  *  *  $ScriptFPath"
      if [ $? -eq 0 ]
      then
         sleep 1
         jobStr="$(_GetCronJobList_ | grep " $ScriptFPath ")"

         LogMsg="New CRON Job [$CRU_Tag] was CREATED."
         _AddDebugLogMsgs_ "INFO: $LogMsg"
         _AddMsgToMyLogNoTime_ "CRON: [$jobStr]"
      else
         LogMsg="CANNOT create new CRON Job [$CRU_Tag]"
         _AddDebugLogMsgs_ "CRON_ERROR: $LogMsg"
      fi
   fi
}

##################################################################
_ParseCronJobParameter()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then return 1
   fi
   local argVal  minsVal

   argVal="$(echo "$1" | awk -F '=' '{print $2}')"
   if [ -z "$argVal" ]
   then
       :  #DEFAULT VALUE#
   else
       minsVal="$(echo "$argVal" | grep -E "^${CronMinsXRegExp}$")"
       if [ -n "$minsVal" ]
       then
           CRON_Mins="$minsVal"
       else
           printf "\n*ERROR*: INVALID minutes parameter [$argVal] for CRON job."
           printf "\nSetting default of [$CRON_Mins] minutes.\n\n"
       fi
   fi

   CRON_Set=1
   _CheckForCronJobSetup_
}

#################################################################
_DeleteCronJob_()
{
   local jobStrX  jobStrY  cronTag="N/A"

   jobStrX="$(_GetCronJobList_ | grep " $ScriptFPath ")"
   jobStrY="$(_GetCronJobList_ | grep " #${CRON_Tag}#$")"
   if [ -z "$jobStrX" ] && [ -z "$jobStrY" ]
   then
       printf "\nNo CRON Job was found.\n"
       return 0
   fi
   if [ -n "$jobStrX" ]
   then
       cronTag="$(echo "$jobStrX" | awk -F ' ' '{print $7}')"
       cronTag="$(echo "$cronTag" | sed "s/#//g")"
       [ -n "$cronTag" ] && $CRU_Cmd d "$cronTag"
   fi
   if [ -n "$jobStrY" ] && [ "$CRON_Tag" != "$cronTag" ]
   then $CRU_Cmd d "$CRON_Tag"
   fi
   sleep 2

   jobStrX="$(_GetCronJobList_ | grep " $ScriptFPath ")"
   jobStrY="$(_GetCronJobList_ | grep " #${CRON_Tag}#$")"
   if [ -z "$jobStrX" ] && [ -z "$jobStrY" ]
   then
       LogMsg="CRON Job was DELETED."
       _AddDebugLogMsgs_ "INFO: $LogMsg"
   else
       printf "CRON Job was NOT deleted."
   fi
   return 0
}

##################################################################
_CheckScriptUpdate_()
{
   local dlVersionStr  dlVersTagStr  scriptMD5  dlTempMD5
   local scriptFPath="${ScriptFolder}/$SCRIPT_FNAME"
   local theTempFile="${DEF_LOG_Dir}/${SCRIPT_FNAME}.TMP"

   curl -LSs --retry 4 --retry-delay 5 --retry-connrefused \
   "${SCRIPT_URL_GH}/$SCRIPT_FNAME" -o "$theTempFile"

   if [ ! -s "$theTempFile" ] || \
      grep -Eiq "^404: Not Found" "$theTempFile"
   then
       [ -s "$theTempFile" ] && cat "$theTempFile"
       printf "\n${REDct}**ERROR**${NOct}: Could NOT download the latest script file.\n"
       rm -f "$theTempFile"
       return 1
   fi

   chmod 755 "$theTempFile"
   dlVersionStr="$(grep -E '^readonly SCRIPT_VERSION=' "$theTempFile")"
   dlVersTagStr="$(grep -E '^readonly SCRIPT_VERSTAG=' "$theTempFile")"
   if [ -z "$dlVersionStr" ] || [ -z "$dlVersTagStr" ]
   then
       printf "\n${REDct}**ERROR**${NOct}: Could NOT find the VERSION string.\n"
       rm -f "$theTempFile"
       return 1
   fi

   dlTempMD5="$(md5sum "$theTempFile" 2>/dev/null | awk -F' ' '{print $1}')"
   scriptMD5="$(md5sum "$scriptFPath" 2>/dev/null | awk -F' ' '{print $1}')"
   dlVersionStr="$(echo "$dlVersionStr" | tr -d '"' | cut -d'=' -f2)"
   dlVersTagStr="$(echo "$dlVersTagStr" | tr -d '"' | cut -d'=' -f2)"

   if [ "$scriptMD5" = "$dlTempMD5" ] && \
      [ "$dlVersionStr" = "$SCRIPT_VERSION" ] && \
      [ "$dlVersTagStr" = "$SCRIPT_VERSTAG" ]
   then
       printf "\nYou have the latest script version [${GRNct}${SCRIPT_VERSION}_${SCRIPT_VERSTAG}${NOct}] available.\n\n"
       return 0
   fi

   printf "\nLatest script version update [${MGNTct}${dlVersionStr}_${dlVersTagStr}${NOct}] available.\n"
   mv -f "$theTempFile" "$scriptFPath"
   chmod 755 "$scriptFPath"
   printf "Script has been updated to the latest version [${GRNct}${dlVersionStr}_${dlVersTagStr}${NOct}].\n\n"
   return 0
}

if [ $# -gt 0 ] && [ -n "$1" ]
then
    case "$1" in
        -setdelay) sleep $doDelaySecs ;;
        help|-help) _ShowUsage_ ; exit 0 ;;
        vers|-vers) _ShowVersion_ ; exit 0 ;;
        -delcronjob) _DeleteCronJob_ ; exit 0 ;;
        -checkupdate) _CheckScriptUpdate_ ; exit 0 ;;
        -setcronjob|-setcronjob=[1-9]*) ;; #CONTINUE#
        *) printf "\n*ERROR*: Unknown Parameter(s): [$*]\n\n"
           exit 1 ;;
    esac
fi

_DoInitMyLogFile_

if [ $# -gt 0 ] && [ -n "$1" ] && \
   echo "$1" | grep -qE "^-setcronjob(=.*)?"
then _ParseCronJobParameter "$1"
fi

ProcCount=0
RecheckStuckCmds=false

ProcList=""
ProcEntry1=""
ProcEntryN=""

## Look for 'nvram' or 'wl' commands ##
readonly grepExcept0="grep -E"
readonly grepSearch0="grep -E '\b(nvram|wl)\b[[:blank:]]+'"

## Sort PIDs in descending order (from high to low) ##
readonly SortPIDs="sort -n -r -t ' ' -k 1"
readonly FindProcs="top -b -n1 | $grepSearch0"

##################################################################
_GetTraceFileIndexNumber_()
{
   local traceIndex  nextTraceIndex

   if [ ! -s "$StuckCmdsNDXfile" ]
   then echo "TraceIndex=1" > "$StuckCmdsNDXfile"
   fi

   traceIndex="$(grep "^TraceIndex=" "$StuckCmdsNDXfile" | awk -F '=' '{print $2}')"

   if [ -z "$traceIndex" ] || [ "$traceIndex" -lt 1 ]
   then traceIndex=1
   fi

   nextTraceIndex="$((traceIndex + 1))"
   if [ "$nextTraceIndex" -gt "$MaxTraceIndex" ]
   then nextTraceIndex=1
   fi

   echo "## Next Trace File Index ##" > "$StuckCmdsNDXfile"
   echo "TraceIndex=$nextTraceIndex" >> "$StuckCmdsNDXfile"

   traceIndex="$(printf "%05d" "$traceIndex")"

   echo "$traceIndex"
}

##################################################################
_GetTraceFilePath_()
{
   local traceFName  traceIndex
   traceIndex="$(_GetTraceFileIndexNumber_)"
   traceFName="${StuckCmdsLOGname}_${traceIndex}_${thePID}.TRC.txt"
   echo "${TheTRCdir}/${traceFName}"
}

##################################################################
_ResetStuckProcessCmdsFile_()
{
   if [ -f "$StuckCmdsLOGfile" ]
   then
      local traceFilePath=""
      traceFilePath="$(_GetTraceFilePath_)"
      cp -fp "$StuckCmdsLOGfile" "$traceFilePath"
      rm -f "$StuckCmdsLOGfile"
   fi
}

##################################################################
_ShowParentProcEntry_()
{
   local ProcEntry  ProcCPID  ProcPPID
   local CPID_List=""  PPID_List=""  PPIDfind

   while read -r ProcEntry
   do
      ProcCPID="$(echo $ProcEntry | awk -F ' ' '{print $1}')"
      ProcPPID="$(echo $ProcEntry | awk -F ' ' '{print $2}')"

      if [ -z "$CPID_List"  ]
      then CPID_List="$ProcCPID"
      else CPID_List="$CPID_List $ProcCPID"
      fi

      if [ -z "$PPID_List"  ]
      then PPID_List="$ProcPPID"
      else
         PPIDfind="$(echo "$PPID_List" | grep -cw "$ProcPPID")"
         if [ "$PPIDfind" -eq 0 ]
         then PPID_List="$PPID_List $ProcPPID"
         fi
      fi
   done <<EOT
$(echo "$1")
EOT

   local NumCnt=1  ProcEntryX=""  MaxCnt=0
   MaxCnt="$(echo "$PPID_List" | wc -w)"

   while [ "$NumCnt" -le "$MaxCnt" ]
   do
      ProcPPID="$(echo "$PPID_List" | cut -d ' ' -f $NumCnt)"
      PPIDfind="$(echo "$CPID_List" | grep -cw "$ProcPPID")"

      if [ "$ProcPPID" -gt 1 ] && [ "$PPIDfind" -eq 0 ]
      then
         ProcEntry="$(top -b -n1 | grep -w "^[ ]*$ProcPPID")"

         if [ -n "$ProcEntry" ]
         then
            _AddMsgToMyLogNoTime_ "$ProcEntry"

            if [ -z "$ProcEntryX" ]
            then ProcEntryX="$ProcEntry"
            else ProcEntryX="$(printf "%s\n%s\n" "$ProcEntryX" "$ProcEntry")"
            fi
         fi
      fi
      NumCnt="$((NumCnt + 1))"
   done

   if [ -n "$ProcEntryX" ]
   then
      ProcList="$(printf "%s\n%s\n" "$ProcList" "$ProcEntryX")"
      _ShowParentProcEntry_ "$ProcEntryX"
   fi
}

##################################################################
_InsertListOfPIDs_()
{
   local ProcEntry  NumCnt=1
   while IFS= read -r ProcEntry
   do
      sed -i "$NumCnt i $1 $ProcEntry" "$StuckCmdsLOGfile"
      NumCnt="$((NumCnt + 1))"
   done <<EOT
$(echo "$2")
EOT
}

##################################################################
_DoNotCareCPUs_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then echo ; return 1
   fi
   local cmdStrY
   local cpuNumr="$(echo "$1" | awk -F' ' '{print $7}')"
   local cpuPerc="$(echo "$1" | awk -F' ' '{print $8}')"
   local cmdStrX="$(echo "$1" | awk -F' ' '{print $9}')"
   cmdStrX="$(_EscapeChars_ "$cmdStrX")"
   cmdStrY="$(_EscapeChars_ "$cmdStrX")"

   echo "$1" | sed -E "s/([[:blank:]]+)(${cpuNumr})([[:blank:]]+)(${cpuPerc})([[:blank:]]+)(${cmdStrX})/\1\[0-9\]\+\3\[0-9\]\+\[\.\]\[0-9\]\+\5${cmdStrY}/"
}

##################################################################
_StuckProcessCmdsRunning_()
{
   ProcCount="$(eval $FindProcs | grep -cv "$grepExcept0")"

   if [ "$ProcCount" -gt 0 ] && [ $# -eq 0 ]
   then
      sleep 4   ## Let's wait some time to double check ##
      ProcCount="$(eval $FindProcs | grep -cv "$grepExcept0")"
   fi

   if [ "$ProcCount" -eq 0 ]
   then LogMsg="FOUND: [$ProcCount]"
   else LogMsg="FOUND_${thePID}: [$ProcCount]"
   fi
   _ShowDebugMsg_ "$LogMsg"

   if [ $# -gt 0 ] && echo "$1" | grep -qE "^-ShowMsg"
   then
       if [ "$ProcCount" -gt 0 ]
       then
           if [ "$1" = "-ShowMsgStart" ]
           then
               _DeleteLastLogFileLineMarked_
               if ! _LastLogFileLineEmpty_
               then echo >> "$TheLogFile"
               fi
               _AddDebugLogMsgs_ "START_$thePID" "[$0]"
               [ -n "$theLogMsgARGS" ] && \
               _AddDebugLogMsgs_ "$theLogMsgARGS"
           fi
           _AddMsgsToMyLog_ "_ADDnoMARK_" "$LogMsg"
       fi
   elif [ "$ProcCount" -eq 0 ]
   then
       _AddMsgsToMyLog_ "_ADDwithMARK_" "$LogMsg"
   fi

   if [ "$ProcCount" -gt 0 ]
   then return 0
   else return 1
   fi
}

##################################################################
_GetStuckProcessCmds_()
{
   local ProcState="XX"
   ProcEntry1=""  ProcEntryN=""  ProcList=""
   ProcCount="$(eval $FindProcs | grep -cv "$grepExcept0")"

   if [ "$ProcCount" -gt 0 ]
   then
      ProcEntry1="$(eval $FindProcs | eval $SortPIDs | \
                    grep -m 1 -v "$grepExcept0")"

      ProcEntryN="$(eval $FindProcs | eval $SortPIDs | \
                    grep -m $ProcCount -v "$grepExcept0")"

      ProcState="$(echo "$ProcEntry1" | awk -F ' ' '{print $4}')"
      if ! echo "$ProcState" | grep -qE "^(R|S|Z)$"
      then ProcEntry1=""
      fi
   fi

   if [ "$ProcCount" -eq 0 ] || [ -z "$ProcEntry1" ]
   then
      LogMsg="FOUND_${thePID}: [$ProcCount][$ProcState]"
      _AddMsgsToMyLog_ "_ADDnoMARK_" "$LogMsg"
   fi
}

##################################################################
_SaveStuckProcessCmds_()
{
   local ProcXPID  ProcPPID  ProcFound  KillEntryLog
   local NowTimeSecs  LastTimeSecs  TimeDiffSecs  LastTime
   local ProcStrX  ProcStrN  cmdState  cpuPrcnt  cpuPerNum
   local nvramLockFile="/var/nvram.lock"  procKilled

   _GetStuckProcessCmds_

   if [ -n "$ProcEntry1" ] && [ -n "$ProcEntryN" ]
   then
      ProcList="$ProcEntryN"
      NowTime="$(date +"$SysLogTimeFormat")"

      _AddMsgToMyLogNoTime_ "$ProcEntryN"
      _ShowParentProcEntry_ "$ProcEntryN"

      if [ ! -f "$StuckCmdsLOGfile" ]
      then printf " " > "$StuckCmdsLOGfile"
      fi

      # Make CPUnum & CPUpercent "don't cares" #
      ProcStrX="$(_DoNotCareCPUs_ "$ProcEntry1")"
      ProcFound="$(grep -c -E "${ProcStrX}$" "$StuckCmdsLOGfile")"

      LogMsg="FOUND_${thePID}: [$ProcFound][$ProcEntry1]"
      _AddDebugLogMsgs_ "$LogMsg"

      if [ "$ProcFound" -eq 0 ]
      then
          _InsertListOfPIDs_ "$NowTime" "$ProcList"
          RecheckStuckCmds=false
      fi
      LastTime=""; ProcXPID=""; ProcPPID=""; cmdState=""; cpuPrcnt=""

      if [ "$ProcFound" -gt 0 ] && [ "$UseKillCmd" -eq 1 ]
      then
         ProcStrN="$(grep -m1 -E "${ProcStrX}$" "$StuckCmdsLOGfile")"
         if [ -n "$ProcStrN" ]
         then
            LastTime="$(echo "$ProcStrN" | awk -F ' ' '{print $1,$2}')"
            ProcXPID="$(echo "$ProcStrN" | awk -F ' ' '{print $3}')"
            ProcPPID="$(echo "$ProcStrN" | awk -F ' ' '{print $4}')"
            cmdState="$(echo "$ProcStrN" | awk -F ' ' '{print $6}')"
            cpuPrcnt="$(echo "$ProcStrN" | awk -F ' ' '{print $10}')"
         fi
         if [ -n "$ProcXPID" ] && [ -n "$ProcPPID" ] && \
            [ -n "$LastTime" ] && [ -n "$cmdState" ] && [ -n "$cpuPrcnt" ]
         then
            NowTimeSecs="$(date +%s -d "${NowTime}")"
            LastTimeSecs="$(date +%s -d "${LastTime}")"
            TimeDiffSecs="$((NowTimeSecs - LastTimeSecs))"
            KillEntryLog="$NowTime ${ProcEntry1} [KILLED]"

            if [ "$TimeDiffSecs" -ge "$MaxDiffSecs" ]
            then
               LogMsg="PID_${thePID}: [$ProcXPID][$ProcPPID], [$TimeDiffSecs >= $MaxDiffSecs] secs."
               _AddDebugLogMsgs_ "$LogMsg"
               procKilled=false ; LogMsg=""

               if [ -n "$ProcXPID" ] && [ -n "$ProcPPID" ] && \
                  echo "$cmdState" | grep -qE "^(R|S|Z)$"
               then
                  if [ "$cmdState" = "Z" ] && [ "$ProcPPID" -gt 2 ]
                  then  #Kill Parent#
                     kill -9 $ProcPPID
                     LogMsg="[kill -9 $ProcPPID][$?]"
                     procKilled=true
                  elif [ "$cmdState" = "R" ]
                  then
                      if echo "$cpuPrcnt" | grep -qE '^[0-9]+([.][0-9]+)?$'
                      then
                          cpuPerNum="$(echo "$cpuPrcnt" | awk -F' ' '{print ($1 * 10)}')"
                          if [ "$cpuPerNum" -gt 70 ]
                          then
                              kill -9 $ProcXPID
                              LogMsg="[kill -9 $ProcXPID][$?]"
                              procKilled=true
                          fi
                      fi
                  else
                     kill -9 $ProcXPID
                     LogMsg="[kill -9 $ProcXPID][$?]"
                     procKilled=true
                  fi
                  if "$procKilled" && [ -n "$LogMsg" ]
                  then
                      [ -f "$nvramLockFile" ] && rm -f "$nvramLockFile"
                      _AddDebugLogMsgs_ "CMD_${thePID}: $LogMsg"
                      sed -i "1 i $KillEntryLog" "$StuckCmdsLOGfile"
                      sleep 2
                  else
                      LogMsg="SKIP_${thePID}: [$ProcFound][$ProcEntry1]"
                      _AddDebugLogMsgs_ "$LogMsg"
                  fi
                  RecheckStuckCmds=true
               fi
            else
               LogMsg="PID_${thePID}: [$ProcXPID], [$TimeDiffSecs < $MaxDiffSecs] secs."
               _AddDebugLogMsgs_ "$LogMsg"
            fi
         fi
      fi
      return 0
   fi
   return 1
}

theLogMsgARGS=""

#################################
# Initial Quick Check & Exit.
#-------------------------------#
if ! _StuckProcessCmdsRunning_
then
   _ResetStuckProcessCmdsFile_
   exit 0
fi

if [ -n "$*" ]
then theLogMsgARGS="ARGs_${thePID}: [$*]"
fi

############################################
# Check for Stuck Processes (nvram & wl)
#------------------------------------------#
if _StuckProcessCmdsRunning_ "-ShowMsgStart"
then
   _SaveStuckProcessCmds_

   if _StuckProcessCmdsRunning_ "-ShowMsg" && \
      { [ "$ProcCount" -lt 4 ] && \
        [ "$(pidof "$ScriptFName1" | wc -w)" -lt 3 ] ; }
   then $ScriptFPath -setdelay &
   fi

   if "$RecheckStuckCmds" && \
      ! _StuckProcessCmdsRunning_ "-ShowMsg"
   then _ResetStuckProcessCmdsFile_
   fi

   _AddDebugLogMsgs_ "EXIT_$thePID"
   _AddDebugLogMsgs_
else
   _ResetStuckProcessCmdsFile_
fi

exit 0

#EOF#
