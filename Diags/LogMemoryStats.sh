#!/bin/sh
#####################################################################
# LogMemoryStats.sh
#
# To log a snapshot of current RAM usage stats, including the
# "tmpfs" filesystem (i.e. a virtual drive that uses RAM).
#
# It also takes snapshots of file/directory usage in JFFS,
# and the current top 10 processes based on "VSZ" size for
# context and to capture any correlation between the stats.
#
# EXAMPLE CALL:
#   LogMemoryStats.sh  [kb|KB|mb|MB]
#
# The *OPTIONAL* parameter indicates whether to keep track of
# file/directory sizes in KBytes or MBytes. Since we're usually
# looking for unexpected large files, we filter out < 750KBytes.
# If no parameter is given the default is the "Human Readable"
# format.
#
# The script can also send email notifications when specific
# pre-defined thresholds are reached for the CPU temperature,
# JFFS usage and "tmpfs" usage. This works ONLY *IF* the
# AMTM email configuration file has been previously set up
# already.
#
# Call to check for script version updates:
#   LogMemoryStats.sh  -updateCheck [-quiet]
#
# FOR DIAGNOSTICS PURPOSES:
# -------------------------
# Set up a cron job to periodically monitor and log RAM usage
# stats every 1 or 2 hours to check for any "trends" in unusual
# increases in RAM usage, especially if unexpected large files
# are being created/stored in "tmpfs" (or "jffs") filesystem.
#
# EXAMPLE:
# cru a LogMemStats "0 */2 * * * /jffs/scripts/LogMemoryStats.sh"
#--------------------------------------------------------------------
# Creation Date: 2021-Apr-03 [Martinski W.]
# Last Modified: 2024-Apr-12 [Martinski W.]
#####################################################################
set -u

readonly LMS_VERSION="0.6.3"
readonly LMS_VERFILE="lmsVersion.txt"

readonly LMS_SCRIPT_TAG="master"
readonly LMS_SCRIPT_URL="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${LMS_SCRIPT_TAG}/Diags"

readonly scriptFileName="${0##*/}"
readonly scriptFileNTag="${scriptFileName%.*}"
readonly scriptLogFName="${scriptFileNTag}.LOG"
readonly backupLogFName="${scriptFileNTag}.BKP.LOG"
readonly tempLogFPath="/tmp/var/tmp/${scriptFileNTag}.TMP.LOG"
readonly duFilterSizeKB=750   #Filter for "du" output#
readonly CPU_TempProcDMU=/proc/dmu/temperature
readonly CPU_TempThermal=/sys/devices/virtual/thermal/thermal_zone0/temp

#-----------------------------------------------------
# Default maximum log file size in KByte units.
# 1.0MByte should be enough to save at least 5 days
# worth of log entries, assuming you run the script
# no more frequent than every 20 minutes.
#-----------------------------------------------------
readonly MIN_LogFileSizeKB=100    #100KB#
readonly DEF_LogFileSizeKB=1024   #1.0MB#
readonly MAX_LogFileSizeKB=8192   #8.0MB#

#-----------------------------------------------------
# Make sure to set the log directory to a location
# that survives a reboot so logs are not deleted.
#-----------------------------------------------------
readonly defLogDirectoryPath="/opt/var/log"
readonly altLogDirectoryPath="/jffs/scripts/logs"

maxLogFileSizeKB="$DEF_LogFileSizeKB"
userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"
userLogDirectoryPath="$defLogDirectoryPath"

readonly CEM_LIB_TAG="master"
readonly CEM_LIB_URL="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${CEM_LIB_TAG}/EMail"

readonly CUSTOM_EMAIL_LIBDir="/jffs/addons/shared-libs"
readonly CUSTOM_EMAIL_LIBName="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIBFile="${CUSTOM_EMAIL_LIBDir}/$CUSTOM_EMAIL_LIBName"

scriptDirPath="$(/usr/bin/dirname "$0")"
[ "$scriptDirPath" = "." ] && scriptDirPath="$(pwd)"

readonly logMemStatsCFGdir="/jffs/configs"
readonly logMemStatsCFGname="LogMemStatsConfig.txt"
readonly logMemStatsCFGfile="${logMemStatsCFGdir}/$logMemStatsCFGname"
readonly tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

routerMODEL_ID="UNKNOWN"
scriptLogFPath="${userLogDirectoryPath}/$scriptLogFName"
backupLogFPath="${userLogDirectoryPath}/$backupLogFName"

isInteractive=false
if [ -t 0 ] && ! tty | grep -qwi "not"
then isInteractive=true ; fi

if [ $# -eq 0 ] || [ -z "$1" ] || \
   ! echo "$1" | grep -qE '^(kb|KB|mb|MB)$'
then units="HR"
else units="$1"
fi

#-----------------------------------------------------------------------#
_PrintMsg_()
{
   ! "$isInteractive" && return 0
   printf "${1}"
}

#-----------------------------------------------------------------------#
_WaitForEnterKey_()
{
   ! "$isInteractive" && return 0
   printf "\nPress <Enter> key to continue..."
   read -r EnterKEY ; echo
}

#-----------------------------------------------------------#
_CheckForScriptUpdates_()
{
   _VersionStrToNum_()
   {
      if [ $# -eq 0 ] || [ -z "$1" ] ; then echo 0 ; return 1 ; fi
      local verNum  verStr

      verStr="$(echo "$1" | sed "s/['\"]//g")"
      verNum="$(echo "$verStr" | awk -F '.' '{printf ("%d%02d%02d\n", $1,$2,$3);}')"
      verNum="$(echo "$verNum" | sed 's/^0*//')"
      echo "$verNum" ; return 0
   }
   if [ $# -eq 0 ] || [ -z "$1" ]
   then
       _PrintMsg_ "\n**ERROR**: NO parameter given for directory path.\n"
       return 1
   fi
   if [ ! -d "$1" ]
   then
       _PrintMsg_ "\n**ERROR**: Directory Path [$1] *NOT* FOUND.\n"
       return 1
   fi
   local theVersTextFile="${1}/$LMS_VERFILE"
   local scriptVerNum  dlFileVerNum  dlFileVerStr
   local isVerboseMode  retCode

   if [ $# -gt 1 ] && [ "$2" = "-quiet" ]
   then isVerboseMode=false ; else isVerboseMode=true ; fi

   "$isVerboseMode" && \
   _PrintMsg_ "\nChecking for script updates..."

   curl -kLSs --retry 4 --retry-delay 5 --retry-connrefused \
   "${LMS_SCRIPT_URL}/$LMS_VERFILE" -o "$theVersTextFile"

   if [ ! -s "$theVersTextFile" ] || grep -iq "404: Not Found" "$theVersTextFile"
   then
       rm -f "$theVersTextFile"
       _PrintMsg_ "\n**ERROR**: Could not download the version file [$LMS_VERFILE]\n"
       return 1
   fi
   chmod 666 "$theVersTextFile"
   dlFileVerStr="$(cat "$theVersTextFile")"

   dlFileVerNum="$(_VersionStrToNum_ "$dlFileVerStr")"
   scriptVerNum="$(_VersionStrToNum_ "$LMS_VERSION")"

   if [ "$dlFileVerNum" -le "$scriptVerNum" ]
   then
       retCode=1
       "$isVerboseMode" && _PrintMsg_ "\nDone.\n"
   else
       retCode=0
       "$isVerboseMode" && \
       _PrintMsg_ "\nNew script version update [$dlFileVerStr] available.\n"
   fi

   rm -f "$theVersTextFile"
   return "$retCode"
}

#-----------------------------------------------------------------------#
_ValidateLogDirPath_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then
       _PrintMsg_ "\n**ERROR**: Log Directory path was *NOT* provided.\n"
       _PrintMsg_ "\nExiting now.\n\n"
       exit 1
   fi

   [ ! -d "$1" ] && mkdir -m 755 "$1" 2>/dev/null
   if [ -d "$1" ]
   then
       scriptLogFPath="${1}/$scriptLogFName"
       backupLogFPath="${1}/$backupLogFName"
       return 0
   fi
   _PrintMsg_ "\n**ERROR**: Log Directory [$1] *NOT* FOUND.\n"
   _WaitForEnterKey_

   if [ $# -gt 1 ] && [ -n "$2" ]
   then
       _PrintMsg_ "**INFO**: Trying again with directory [$2].\n"
       _WaitForEnterKey_
       shift ; _ValidateLogDirPath_ "$@"
   else
       _PrintMsg_ "\nExiting now.\n\n"
       exit 2
   fi
}

#-----------------------------------------------------------------------#
_CheckLogFileSize_()
{
   [ ! -f "$scriptLogFPath" ] && return 1

   local theFileSize=0
   theFileSize="$(ls -l "$scriptLogFPath" | awk -F ' ' '{print $5}')"
   if [ "$theFileSize" -gt "$userMaxLogFileSize" ]
   then
       cp -fp "$scriptLogFPath" "$backupLogFPath"
       rm -f "$scriptLogFPath"
       _PrintMsg_ "\nDeleted $scriptLogFPath [$theFileSize > $userMaxLogFileSize]\n\n"
   fi
}

#-----------------------------------------------------------#
_DownloadLibraryFile_CEM_()
{
   local msgStr  retCode
   case "$1" in
        update) msgStr="Updating" ;;
       install) msgStr="Installing" ;;
             *) return 1 ;;
   esac
   _PrintMsg_ "\n${msgStr} the shared library script file to support email notifications...\n"

   mkdir -m 755 -p "$CUSTOM_EMAIL_LIBDir"
   curl -kLSs --retry 3 --retry-delay 5 --retry-connrefused \
   "${CEM_LIB_URL}/$CUSTOM_EMAIL_LIBName" -o "$CUSTOM_EMAIL_LIBFile"
   curlCode="$?"

   if [ "$curlCode" -eq 0 ] && [ -s "$CUSTOM_EMAIL_LIBFile" ]
   then
       retCode=0
       chmod 755 "$CUSTOM_EMAIL_LIBFile"
       . "$CUSTOM_EMAIL_LIBFile"
       _PrintMsg_ "\nDone.\n"
   else
       retCode=1
       _PrintMsg_ "\n**ERROR**: Unable to download the shared library script file [$CUSTOM_EMAIL_LIBName].\n"
   fi
   return "$retCode"
}

#-----------------------------------------------------------------------#
_CreateConfigurationFile_()
{
   [ -f "$logMemStatsCFGfile" ] && return 0
   [ ! -d "$logMemStatsCFGdir" ] && \
   mkdir -m 755 "$logMemStatsCFGdir" 2>/dev/null
   [ ! -d "$logMemStatsCFGdir" ] && return 1

   {
     echo "maxLogFileSizeKB=$DEF_LogFileSizeKB"
     echo "userLogDirectoryPath=\"${defLogDirectoryPath}\""
     echo "prefLogDirectoryPath=\"${defLogDirectoryPath}\""
     echo "cpuLastEmailNotificationTime=0_INIT"
     echo "jffsLastEmailNotificationTime=0_INIT"
     echo "tmpfsLastEmailNotificationTime=0_INIT"
     echo "isSendEmailNotificationsEnabled=false"
   } > "$logMemStatsCFGfile"

   _PrintMsg_ "\nConfiguration file [$logMemStatsCFGfile] was created.\n"
   _WaitForEnterKey_

   return 0
}

#-----------------------------------------------------------------------#
_ValidateConfigurationFile_()
{
   [ ! -f "$logMemStatsCFGfile" ] && return 1

   if ! grep -q "^maxLogFileSizeKB=" "$logMemStatsCFGfile"
   then
       sed -i "1 i maxLogFileSizeKB=$DEF_LogFileSizeKB" "$logMemStatsCFGfile"
   fi
   if ! grep -q "^userLogDirectoryPath=" "$logMemStatsCFGfile"
   then
       sed -i "2 i userLogDirectoryPath=\"${defLogDirectoryPath}\"" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^prefLogDirectoryPath=" "$logMemStatsCFGfile"
   then
       sed -i "3 i prefLogDirectoryPath=\"${defLogDirectoryPath}\"" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^cpuLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "4 i cpuLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^jffsLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "5 i jffsLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^tmpfsLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "6 i tmpfsLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^isSendEmailNotificationsEnabled=" "$logMemStatsCFGfile"
   then
       sed -i "7 i isSendEmailNotificationsEnabled=false" "$logMemStatsCFGfile"
       retCode=1
   fi
}

#-----------------------------------------------------------------------#
_GetConfigurationOption_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      [ ! -f "$logMemStatsCFGfile" ] || \
      ! grep -q "^${1}=" "$logMemStatsCFGfile"
   then echo "" ; return 1 ; fi
   local keyValue

   keyValue="$(grep "^${1}=" "$logMemStatsCFGfile" | awk -F '=' '{print $2}')"
   echo "$keyValue" ; return 0
}

#-----------------------------------------------------------------------#
_SetConfigurationOption_()
{
   if [ ! -f "$logMemStatsCFGfile" ] || \
      [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1; fi
   local keyName  keyValue  fixedVal  dateTimeStr

   case "$1" in
       maxLogFileSizeKB)
            maxLogFileSizeKB="$2"
            userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"
            ;;
       userLogDirectoryPath)
            userLogDirectoryPath="$2"
            scriptLogFPath="${2}/$scriptLogFName"
            backupLogFPath="${2}/$backupLogFName"
            ;;
       prefLogDirectoryPath)
            prefLogDirectoryPath="$2"
            ;;
       isSendEmailNotificationsEnabled)
            isSendEmailNotificationsEnabled="$2"
            ;;
   esac

   keyName="$1"
   if ! grep -q "^${keyName}=" "$logMemStatsCFGfile"
   then
       echo "${keyName}=$2" >> "$logMemStatsCFGfile"
       return 0
   fi

   keyValue="$(grep "^${keyName}=" "$logMemStatsCFGfile" | awk -F '=' '{print $2}')"
   if [ -z "$keyValue" ] || [ "$keyValue" != "$2" ]
   then
       fixedVal="$(echo "$2" | sed 's/[\/.*-]/\\&/g')"
       sed -i "s/${keyName}=.*/${keyName}=${fixedVal}/" "$logMemStatsCFGfile"
   fi

   if echo "$keyName" | grep -qE "^(cpu|jffs|tmpfs)LastEmailNotificationTime$"
   then
       dateTimeStr="## $(date +'%Y-%b-%d, %I:%M:%S %p %Z') ##"
       if ! grep -qE "^## [0-9]+[-].* ##$" "$logMemStatsCFGfile"
       then sed -i "1 i $dateTimeStr" "$logMemStatsCFGfile"
       else sed -i "s/^## [0-9]\+[-].*/$dateTimeStr/" "$logMemStatsCFGfile"
       fi
   fi
}

#-----------------------------------------------------------------------#
_InitConfigurationSettings_()
{
   [ ! -f "$logMemStatsCFGfile" ] && return 1
   . "$logMemStatsCFGfile"

   if [ "$maxLogFileSizeKB" -lt "$MIN_LogFileSizeKB" ] || \
      [ "$maxLogFileSizeKB" -gt "$MAX_LogFileSizeKB" ]
   then
       _SetConfigurationOption_ maxLogFileSizeKB "$DEF_LogFileSizeKB"
   fi
   userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"

   if [ "$isSendEmailNotificationsEnabled" != "true" ] && \
      [ "$isSendEmailNotificationsEnabled" != "false" ]
   then
       _SetConfigurationOption_ isSendEmailNotificationsEnabled true
   fi
}

#-----------------------------------------------------------------------#
_CheckConfigurationFile_()
{
   _CreateConfigurationFile_
   _ValidateConfigurationFile_
   _InitConfigurationSettings_
}

#-----------------------------------------------------------------------#
# CPU Temperature Thresholds [Celsius]
# >> 92 = Red Alert Level 2 [2 hrs].
# >> 88 = Red Alert Level 1 [12 hrs].
# >> 86 = Yellow Warning Level 1 [24 hrs].
# <= 86 = Green OK.
#-----------------------------------------------------------------------#
cpuTemperatureCelsius=""
cpuTempThresholdTestOnly=false
readonly cpuThermalThresholdTestOnly=10
readonly cpuThermalThresholdWarning1=86   ##OK=86, DEBUG:66##
readonly cpuThermalThresholdRedAlert1=88  ##OK=88, DEBUG:70##
readonly cpuThermalThresholdRedAlert2=92  ##OK=92, DEBUG:72##

#-----------------------------------------------------------------------#
# JFFS Filesystem Usage Thresholds [Percentage]
# >> 80% Used = Red Alert Level 3 [2 hrs].
# >> 75% Used = Red Alert Level 2 [6 hrs].
# >> 70% Used = Red Alert Level 1 [12 hrs].
# >> 60% Used = Yellow Warning Level 2 [24 hrs].
# >> 50% Used = Yellow Warning Level 1 [48 hrs].
# <= 50% Used = Green OK.
#-----------------------------------------------------------------------#
jffsUsageThresholdTestOnly=false
readonly jffsUsedThresholdTestOnly=1
readonly jffsUsedThresholdWarning1=50
readonly jffsUsedThresholdWarning2=60
readonly jffsUsedThresholdRedAlert1=70
readonly jffsUsedThresholdRedAlert2=75
readonly jffsUsedThresholdRedAlert3=80

#-----------------------------------------------------------------------#
# "tmpfs" Filesystem Usage Thresholds [Percentage]
# More than 90% Used = Red Alert Level 3 [2 hrs].
# More than 85% Used = Red Alert Level 2 [6 hrs].
# More than 80% Used = Red Alert Level 1 [12 hrs].
# More than 75% Used = Yellow Warning Level 2 [24 hrs].
# More than 70% Used = Yellow Warning Level 1 [48 hrs].
# Less than 70% Used = Green OK.
#-----------------------------------------------------------------------#
tmpfsUsageThresholdTestOnly=false
readonly tmpfsUsedThresholdTestOnly=0
readonly tmpfsUsedThresholdWarning1=70
readonly tmpfsUsedThresholdWarning2=75
readonly tmpfsUsedThresholdRedAlert1=80
readonly tmpfsUsedThresholdRedAlert2=85
readonly tmpfsUsedThresholdRedAlert3=90

#------------------------------
# To send email notifications
#------------------------------
onehrSecs=3600
cpuLastEmailNotificationTime="0_INIT"
jffsLastEmailNotificationTime="0_INIT"
tmpfsLastEmailNotificationTime="0_INIT"
isSendEmailNotificationsEnabled=false

#-----------------------------------------------------------------------#
_CreateEMailContent_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1 ; fi

   local prevTimeStampSec  prevTimeStampTag  prevTimeStampStr
   local nextTimeStampSec  nextTimeStampTag  nextTimeStampStr
   local curTimeDiffSecs  minTimeDiffSecs
   local doConfigUpdate  timeStampID  theOptionID  retCode

   rm -f "$tmpEMailBodyFile"

   case "$1" in
       CPU_TEMP_TestOnly)
           timeStampID=cpu
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router CPU Temperature [TESTING]"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "This notification is for <b>*TESTING*</b> purposes ONLY.\n\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdTestOnly}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       CPU_TEMP_Warning1)
           timeStampID=cpu
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=YLW1
           emailSubject="Router CPU Temperature WARNING"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdWarning1}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       CPU_TEMP_RedAlert1)
           timeStampID=cpu
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED1
           emailSubject="Router CPU Temperature ALERT"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdRedAlert1}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       CPU_TEMP_RedAlert2)
           timeStampID=cpu
           minTimeDiffSecs="$((onehrSecs * 2))"
           nextTimeStampTag=RED2
           emailSubject="Router CPU Temperature ALERT"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdRedAlert2}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_TestOnly)
           timeStampID=jffs
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router JFFS Usage [TESTING]"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "This notification is for <b>*TESTING*</b> purposes ONLY.\n\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdTestOnly}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_Warning1)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 48))"
           nextTimeStampTag=YLW1
           emailSubject="Router JFFS Usage WARNING"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdWarning1}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_Warning2)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=YLW2
           emailSubject="Router JFFS Usage WARNING"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdWarning2}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert1)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED1
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert1}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert2)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 6))"
           nextTimeStampTag=RED2
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert2}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert3)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 2))"
           nextTimeStampTag=RED3
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert3}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_TestOnly)
           timeStampID=tmpfs
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router TMPFS Usage [TESTING]"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "This notification is for <b>*TESTING*</b> purposes ONLY.\n\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdTestOnly}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_Warning1)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 48))"
           nextTimeStampTag=YLW1
           emailSubject="Router TMPFS Usage WARNING"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdWarning1}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_Warning2)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=YLW2
           emailSubject="Router TMPFS Usage WARNING"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdWarning2}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert1)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED1
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert1}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert2)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 6))"
           nextTimeStampTag=RED2
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert2}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert3)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 2))"
           nextTimeStampTag=RED3
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert3}%%</b>."
             printf "\n\n%s" "$(df -hT | grep -E "^Filesystem[[:blank:]]+")"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       *) _PrintMsg_ "\n**ERROR**: UNKNOWN email parameter ID [$1]\n"
           return 1
           ;;
   esac

   printf "\nRouter Model: <b>${routerMODEL_ID}</b>\n" >> "$tmpEMailBodyFile"

   retCode=1
   doConfigUpdate=false
   nextTimeStampSec="$(date +%s)"
   nextTimeStampStr="${nextTimeStampSec}_$nextTimeStampTag"
   theOptionID="${timeStampID}LastEmailNotificationTime"

   prevTimeStampStr="$(_GetConfigurationOption_ "$theOptionID")"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   [ "$nextTimeStampTag" = "TEST" ] && retCode=0

   if [ -z "$prevTimeStampTag" ] || \
      { [ "$nextTimeStampTag" != "TEST" ] && \
        [ "$nextTimeStampTag" != "$prevTimeStampTag" ] ; }
   then
       retCode=0
       doConfigUpdate=true
   #
   elif echo "$nextTimeStampTag" | grep -qE "^(YLW[1-3]|RED[1-3])$"
   then
       curTimeDiffSecs="$((nextTimeStampSec - prevTimeStampSec))"
       if [ "$curTimeDiffSecs" -gt "$minTimeDiffSecs" ]
       then
           retCode=0
           doConfigUpdate=true
       fi
   fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ "$theOptionID" "$nextTimeStampStr"

   return "$retCode"
}

#-----------------------------------------------------------------------#
_SendEMailNotification_()
{
   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       logTag="**ERROR**_${scriptFileName}_$$"
       logMsg="Email library script [$CUSTOM_EMAIL_LIBFile] *NOT* FOUND."
       /usr/bin/logger -t "$logTag" "$logMsg"
       _PrintMsg_ "\n%s: %s\n\n" "$logTag" "$logMsg"
       return 1
   fi

   if [ $# -eq 0 ] || [ -z "$1" ] || [ -z "$2" ]
   then
       _PrintMsg_ "\n**ERROR**: INSUFFICIENT email parameters\n"
       return 1
   fi
   local retCode  emailSubject=""  emailBodyTitle=""

   ! _CreateEMailContent_ "$@" && return 1

   _PrintMsg_ "\nSending email notification [$1].\nPlease wait..."
   cemIsVerboseMode=false

   _SendEMailNotification_CEM_ "$emailSubject" "-F=$tmpEMailBodyFile" "$emailBodyTitle"
   retCode="$?"

   if [ "$retCode" -eq 0 ]
   then
       logTag="INFO:"
       logMsg="The email notification was sent successfully [$1]."
   else
       logTag="**ERROR**:"
       logMsg="Failure to send email notification [Error Code: $retCode][$1]."
   fi
   _PrintMsg_ "\n${logTag} ${logMsg}\n"

   [ -f "$tmpEMailBodyFile" ] && rm -f "$tmpEMailBodyFile"
   return "$retCode"
}

#-----------------------------------------------------------------------#
_ProcMemInfo_()
{
   printf "/proc/meminfo\n-------------\n"
   grep -E '^Mem[TFA].*:[[:blank:]]+.*' /proc/meminfo
   grep -E '^(Buffers|Cached):[[:blank:]]+.*' /proc/meminfo
   grep -E '^Swap[TFC].*:[[:blank:]]+.*' /proc/meminfo
   grep -E '^(Active|Inactive)(\([af].*\))?:[[:blank:]]+.*' /proc/meminfo
   grep -E '^(Dirty|Writeback|AnonPages|Unevictable):[[:blank:]]+.*' /proc/meminfo
}

duMinKB="$duFilterSizeKB"
#-----------------------------------------------------------------------#
_InfoKBdu_()
{ du -axk "$1" | sort -nr -t ' ' -k 1 | awk -v minKB="$duMinKB" -F ' ' '{if ($1 > minKB) print $0}' | head -n "$2" ; }

#-----------------------------------------------------------------------#
_InfoMBdu_()
{
  tmpStr="$(du -axh "$1" | sort -nr -t ' ' -k 1 | grep -Ev '^([0-9]{1,3}([.][0-9]+K)?[[:blank:]]+)')"
  echo "$tmpStr" | grep -E '^([0-9]+[.][0-9]+M[[:blank:]]+)' | head -n "$2"
  echo "$tmpStr" | grep -E '^([0-9]+[.][0-9]+K[[:blank:]]+)' | head -n "$2"
}

#-----------------------------------------------------------------------#
_InfoHRdu_()
{
  tmpStr="$(du -axh "$1" | sort -nr -t ' ' -k 1 | grep -Ev '^([0-9]{1,3}[[:blank:]]+|([0-9]{1,2}[.][0-9]+K[[:blank:]]+))')"
  echo "$tmpStr" | grep -E '^([0-9]+[.][0-9]+M[[:blank:]]+)' | head -n "$2"
  echo "$tmpStr" | grep -E '^([0-9]+[.][0-9]+K[[:blank:]]+)' | awk -v minKB="$duMinKB" -F '.' '{if ($1 > minKB) print $0}' | head -n "$2"
}

#-----------------------------------------------------------------------#
_CheckUsageThresholdsJFFS_()
{
   local jffsInfo  percentNum  doConfigUpdate
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   jffsInfo="$(df -hT /jffs | grep -E '^/dev/.* [[:blank:]]+jffs.*[[:blank:]]+/jffs$')"
   [ -n "$jffsInfo" ] && \
   percentNum="$(echo "$jffsInfo" | awk -F ' ' '{print $6}')"
   percentNum="$(echo "$percentNum" | awk -F '%' '{print $1}')"

   if "$jffsUsageThresholdTestOnly" && \
      [ "$percentNum" -gt "$jffsUsedThresholdTestOnly" ]
   then
       _SendEMailNotification_ JFFS_USED_TestOnly "$percentNum" "$jffsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert3" ]
   then
       _SendEMailNotification_ JFFS_USED_RedAlert3 "$percentNum" "$jffsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert2" ]
   then
       _SendEMailNotification_ JFFS_USED_RedAlert2 "$percentNum" "$jffsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert1" ]
   then
       _SendEMailNotification_ JFFS_USED_RedAlert1 "$percentNum" "$jffsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdWarning2" ]
   then
       _SendEMailNotification_ JFFS_USED_Warning2 "$percentNum" "$jffsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdWarning1" ]
   then
       _SendEMailNotification_ JFFS_USED_Warning1 "$percentNum" "$jffsInfo"
       return 0
   fi

   doConfigUpdate=false
   prevTimeStampStr="$(_GetConfigurationOption_ jffsLastEmailNotificationTime)"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   if [ -z "$prevTimeStampTag" ] || [ "$prevTimeStampTag" != "GRN" ]
   then doConfigUpdate=true ; fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ jffsLastEmailNotificationTime "${percentNum}_GRN"
}

#-----------------------------------------------------------------------#
_CheckUsageThresholdsTMPFS_()
{
   local tmpfsInfo  percentNum  doConfigUpdate
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   tmpfsInfo="$(df -hT | grep -E '^tmpfs[[:blank:]]+tmpfs .*[[:blank:]]+/tmp$')"
   [ -n "$tmpfsInfo" ] && \
   percentNum="$(echo "$tmpfsInfo" | awk -F ' ' '{print $6}')"
   percentNum="$(echo "$percentNum" | awk -F '%' '{print $1}')"

   if "$tmpfsUsageThresholdTestOnly" && \
      [ "$percentNum" -gt "$tmpfsUsedThresholdTestOnly" ]
   then
       _SendEMailNotification_ TMPFS_USED_TestOnly "$percentNum" "$tmpfsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert3" ]
   then
       _SendEMailNotification_ TMPFS_USED_RedAlert3 "$percentNum" "$tmpfsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert2" ]
   then
       _SendEMailNotification_ TMPFS_USED_RedAlert2 "$percentNum" "$tmpfsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert1" ]
   then
       _SendEMailNotification_ TMPFS_USED_RedAlert1 "$percentNum" "$tmpfsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdWarning2" ]
   then
       _SendEMailNotification_ TMPFS_USED_Warning2 "$percentNum" "$tmpfsInfo"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdWarning1" ]
   then
       _SendEMailNotification_ TMPFS_USED_Warning1 "$percentNum" "$tmpfsInfo"
       return 0
   fi

   doConfigUpdate=false
   prevTimeStampStr="$(_GetConfigurationOption_ tmpfsLastEmailNotificationTime)"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   if [ -z "$prevTimeStampTag" ] || [ "$prevTimeStampTag" != "GRN" ]
   then doConfigUpdate=true ; fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ tmpfsLastEmailNotificationTime "${percentNum}_GRN"
}

#-----------------------------------------------------------------------#
_CheckTemperatureThresholdsCPU_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE '^[1-9]+[.]?[0-9]+$'
   then return 1 ; fi

   _TempInteger_()
   {
       local tmpNum="$(echo "$1" | awk "{print $1}")"
       printf "%.0f" "$tmpNum"
   }

   local doConfigUpdate  tempIntgr  tempFloat
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   tempIntgr="$(_TempInteger_ "($1 * 10)")"
   tempFloat="$(printf "%.1f" "$1")"

   if "$cpuTempThresholdTestOnly" && \
      [ "$tempIntgr" -gt "${cpuThermalThresholdTestOnly}9" ]
   then
       _SendEMailNotification_ CPU_TEMP_TestOnly "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdRedAlert2}9" ]
   then
       _SendEMailNotification_ CPU_TEMP_RedAlert2 "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdRedAlert1}9" ]
   then
       _SendEMailNotification_ CPU_TEMP_RedAlert1 "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdWarning1}9" ]
   then
       _SendEMailNotification_ CPU_TEMP_Warning1 "$tempFloat"
       return 0
   fi

   doConfigUpdate=false
   prevTimeStampStr="$(_GetConfigurationOption_ cpuLastEmailNotificationTime)"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   if [ -z "$prevTimeStampTag" ] || [ "$prevTimeStampTag" != "GRN" ]
   then doConfigUpdate=true ; fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ cpuLastEmailNotificationTime "${tempIntgr}_GRN"
}

#-----------------------------------------------------------------------#
_Get_CPU_Temp_DMU_()
{
   local rawTemp  charPos3  cpuTemp
   rawTemp="$(awk -F ' ' '{print $4}' "$CPU_TempProcDMU")"

   ## To check for a possible 3-digit value ##
   charPos3="${rawTemp:2:1}"
   if echo "$charPos3" | grep -qE '[0-9]'
   then cpuTemp="${rawTemp:0:3}.0"
   else cpuTemp="${rawTemp:0:2}.0"
   fi
   cpuTemperatureCelsius="$cpuTemp"
   printf "CPU Temperature: ${cpuTemp}°C\n"
}

#-----------------------------------------------------------------------#
_Get_CPU_Temp_Thermal_()
{
   local rawTemp  cpuTemp
   rawTemp="$(cat "$CPU_TempThermal")"
   cpuTemp="$((rawTemp / 1000)).$(printf "%03d" "$((rawTemp % 1000))")"
   cpuTemperatureCelsius="$cpuTemp"
   printf "CPU Temperature: ${cpuTemp}°C\n"
}

#-----------------------------------------------------------------------#
_CPU_Temperature_()
{
   cpuTemperatureCelsius=""
   if [ -f "$CPU_TempProcDMU" ]
   then _Get_CPU_Temp_DMU_ ; return 0
   fi
   if [ -f "$CPU_TempThermal" ]
   then _Get_CPU_Temp_Thermal_ ; return 0
   fi
   printf "\n**ERROR**: CPU Temperature file was *NOT* found.\n"
   return 1
}

if [ $# -gt 0 ] && [ "$1" = "-updateCheck" ]
then
    shift
    _CheckForScriptUpdates_ "$(pwd)" "$@"
    exit $?
fi

_CheckConfigurationFile_
_ValidateLogDirPath_ "$userLogDirectoryPath" "$prefLogDirectoryPath" "$altLogDirectoryPath"
_CheckLogFileSize_

if [ -f "$CUSTOM_EMAIL_LIBFile" ]
then
   . "$CUSTOM_EMAIL_LIBFile"

   if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
       _CheckLibraryUpdates_CEM_ "$CUSTOM_EMAIL_LIBDir" -quiet
   then
       _DownloadLibraryFile_CEM_ "update"
   fi
else
    _DownloadLibraryFile_CEM_ "install"
fi

[ -n "${amtmIsEMailConfigFileEnabled:+xSETx}" ] && \
routerMODEL_ID="$(_GetRouterModelID_CEM_)"

##-------------------------------------##
## FOR TESTING/DEBUGGING PURPOSES ONLY ##
##-------------------------------------##
if [ $# -gt 0 ] && [ -n "$1" ]
then
    case "$1" in
        -cputest) cpuTempThresholdTestOnly=true ;;
       -jffstest) jffsUsageThresholdTestOnly=true ;;
      -tmpfstest) tmpfsUsageThresholdTestOnly=true ;;
    esac
fi

{
   echo "=================================="
   date +"%Y-%b-%d, %I:%M:%S %p %Z (%a)"
   printf "Uptime\n------\n" ; uptime ; echo
   _CPU_Temperature_ ; echo
   printf "free:\n" ; free ; echo
   _ProcMemInfo_ ; echo
   df -hT | grep -E '(^Filesystem|/jffs$|/tmp$|/var$)' | sort -d -t ' ' -k 1
   echo
   case "$units" in
       kb|KB) printf "KBytes [du /tmp/]\n-----------------\n"
              _InfoKBdu_ "/tmp" 15
              echo
              printf "KBytes [du /jffs]\n-----------------\n"
              _InfoKBdu_ "/jffs" 15
              ;;
       mb|MB) printf "MBytes [du /tmp/]\n-----------------\n"
              _InfoMBdu_ "/tmp" 15
              echo
              printf "MBytes [du /jffs]\n-----------------\n"
              _InfoMBdu_ "/jffs" 15
              ;;
       hr|HR) printf "[du /tmp/]\n----------\n"
              _InfoHRdu_ "/tmp" 15
              echo
              printf "[du /jffs]\n----------\n"
              _InfoHRdu_ "/jffs" 15
             ;;
   esac
   echo
   top -b -n1 | head -n 14
} > "$tempLogFPath"

"$isInteractive" && cat "$tempLogFPath"
cat "$tempLogFPath" >> "$scriptLogFPath"
rm -f "$tempLogFPath"
_PrintMsg_ "\nLog entry was added to:\n${scriptLogFPath}\n\n"

if "$isSendEmailNotificationsEnabled"
then
   _CheckUsageThresholdsJFFS_
   _CheckUsageThresholdsTMPFS_
   _CheckTemperatureThresholdsCPU_ "$cpuTemperatureCelsius"
fi

exit 0

#EOF#
