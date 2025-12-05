#!/bin/sh
#########################################################################
# LogMemoryStats.sh
#
# To view/log a snapshot of current memory usage, including
# the "TMPFS" filesystem (i.e. a virtual drive that uses RAM).
#
# It also takes snapshots of file/directory usage in JFFS,
# and the current top 15 processes based on "VSZ" size for
# context and to capture any correlation between the usage
# stats.
#
# EXAMPLE CALL:
# -------------
# LogMemoryStats.sh [kb | KB | mb | MB]
#
# The *OPTIONAL* parameter indicates whether to keep track of
# file/directory sizes in KBytes or MBytes. Since we're usually
# looking for unexpected large files, we filter out < 500KBytes.
# If no parameter is given the default is the "Human Readable"
# format.
#
# EMAIL NOTIFICATIONS:
# --------------------
# LogMemoryStats.sh -enableEmailNotification
# LogMemoryStats.sh -disableEmailNotification
#
# The above calls allow you to toggle sending email notifications.
# This feature requires having the AMTM email configuration option
# already set up prior to sending emails via this script.
#
# If enabled, script will send email notifications when specific
# pre-defined thresholds are reached for the CPU temperature,
# "JFFS" usage and "TMPFS" usage. Again, this works ONLY *IF*
# the AMTM email configuration option has been already set up.
#
# CHECK FOR SCRIPT UPDATES:
# -------------------------
# LogMemoryStats.sh -versioncheck [-verbose | -quiet | -veryquiet]
#
# FOR DIAGNOSTICS PURPOSES:
# -------------------------
# LogMemoryStats.sh -setcronjob
#                   (No argument: set DEFAULT schedule to every 20 minutes)
#
# LogMemoryStats.sh -setcronjob [Xmins | Yhour]
#                   VALID parameters are:
#    [10mins | 12mins | 15mins | 20mins | 30mins | 60mins]
#    [1hour | 2hour | 3hour | 4hour | 5hour | 6hour | 8hour | 12hour | 24hour]
#
# Set up a cron job to periodically monitor and log memory usage
# every 'X' minutes *OR* every 'Y' hours to check for any trends
# in unusual increases in memory usage, especially if unexpected
# large files are being created in "TMPFS" or "JFFS" filesystem.
#------------------------------------------------------------------------
# Creation Date: 2021-Apr-03 [Martinski W.]
# Last Modified: 2025-Dec-04 [Martinski W.]
#########################################################################
set -u

readonly LMS_VERSION="0.7.15"
readonly LMS_VERFILE="lmsVersion.txt"
readonly LMS_VERSTAG="25120420"

readonly SCRIPT_BRANCH="master"
readonly LMS_SCRIPT_URL="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${SCRIPT_BRANCH}/Diags"

readonly branchStr_TAG="[Branch: $SCRIPT_BRANCH]"
readonly scriptFileName="${0##*/}"
readonly scriptFileNTag="${scriptFileName%.*}"
readonly scriptLogFName="${scriptFileNTag}.LOG"
readonly backupLogFName="${scriptFileNTag}.BKP.LOG"
readonly tempLogFPath="/tmp/var/tmp/${scriptFileNTag}.TMP.LOG"
readonly duFilterSizeKB=500   #Filter for "du" output#
readonly CPU_Temptr_ProcDMUtemp="/proc/dmu/temperature"
readonly CPU_Temptr_SysPowerCPU="/sys/power/bpcm/cpu_temp"
readonly CPU_Temptr_ThermalZone="/sys/devices/virtual/thermal/thermal_zone0/temp"

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

#-----------------------------------------------------
# Default maximum log file size in KByte units.
# 1.0MByte should be enough to store about 5 days
# worth of log entries, assuming you run the script
# no more frequently than every 20 minutes.
#-----------------------------------------------------
readonly MIN_LogFileSizeKB=512    #512KB#
readonly MIN_LogFileSizeMB=0.5
readonly DEF_LogFileSizeKB=1024   #1.0MB#
readonly MAX_LogFileSizeKB=8192   #8.0MB#
readonly MAX_LogFileSizeMB=8.0
readonly xNumberRegExp="(0|0[.][0-9]{1,3}|[1-9][0-9]*|[1-9][0-9]*[.][0-9]{1,3})"

readonly CRON_Tag="LogMemStats"
readonly cronDefaultMins=5  #VALID: [0-5]#
readonly cronDefaultHour=0  #VALID: [0-23]#
readonly cronMinsRegExp0="[0-5]"  #NO Overlap#
readonly cronMinsRegExp1="6|10|12|15|20|30|60"
readonly cronMinsRegExp2="($cronMinsRegExp1)mins"
readonly cronHourRegExp1="1|2|3|4|5|6|8|12|24"
readonly cronHourRegExp2="($cronHourRegExp1)hour"
readonly cronValidMins="10mins, 12mins, 15mins, 20mins, 30mins, 60mins"
readonly cronValidHour="1hour, 2hour, 3hour, 4hour, 5hour, 6hour, 8hour, 12hour, 24hour"

[ -z "${CRU_Cmd:+xSETx}" ] && CRU_Cmd="$(which cru)"
if [ -z "$(which crontab)" ]
then cronListCmd="$CRU_Cmd l"
else cronListCmd="crontab -l"
fi

#-----------------------------------------------------
# Make sure to set the log directory to a location
# that survives a reboot so logs are not deleted.
#-----------------------------------------------------
readonly HOMEdir="/home/root"
readonly defLogDirectoryPath="/opt/var/log"
readonly altLogDirectoryPath="/jffs/scripts/logs"

maxLogFileSizeKB="$DEF_LogFileSizeKB"
userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"
userLogDirectoryPath="$defLogDirectoryPath"

scriptDirPath="$(/usr/bin/dirname "$0")"
[ "$scriptDirPath" = "." ] && scriptDirPath="$(pwd)"

readonly scriptFilePath="${scriptDirPath}/$scriptFileName"
readonly logMemStatsCFGdir="/jffs/configs"
readonly logMemStatsCFGname="LogMemStatsConfig.txt"
readonly logMemStatsCFGfile="${logMemStatsCFGdir}/$logMemStatsCFGname"
readonly tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

## The shared custom email library to support email notifications ##
readonly ADDONS_SHARED_LIBS_DIR_PATH="/jffs/addons/shared-libs"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FNAME="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME="DownloadCEMLibraryFile.lib.sh"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FPATH="${ADDONS_SHARED_LIBS_DIR_PATH}/$CUSTOM_EMAIL_LIB_SCRIPT_FNAME"
readonly CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH="${ADDONS_SHARED_LIBS_DIR_PATH}/$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME"
readonly CUSTOM_EMAIL_LIB_SCRIPT_URL="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/master/EMail"

scriptLogFPath="${userLogDirectoryPath}/$scriptLogFName"
backupLogFPath="${userLogDirectoryPath}/$backupLogFName"

isInteractive=false
if [ -t 0 ] && ! tty | grep -qwi "not"
then isInteractive=true ; fi

#-----------------------------------------------------------------------#
_PrintMsg_()
{
   ! "$isInteractive" && return 0
   printf "$1"
}

#-----------------------------------------------------------------------#
_MsgToSysLog_()
{
   local msgType  prioNum=5
   if [ $# -gt 1 ] && [ -n "$2" ]
   then msgType="$2"
   else msgType="NOTICE"
   fi
   case "$msgType" in
       ALERT) prioNum=2 ;;
       ERROR) prioNum=3 ;;
        WARN) prioNum=4 ;;
      NOTICE) prioNum=5 ;;
        INFO) prioNum=6 ;;
   esac
   logger -t "${scriptFileName}_[$$]" -p $prioNum "$1"
}

#-----------------------------------------------------------------------#
_WaitForEnterKey_()
{
   ! "$isInteractive" && return 0
   printf "\nPress <Enter> key to continue..."
   read -rs EnterKEY ; echo
}

#-----------------------------------------------------------------------#
_ShowUsage_()
{
   ! "$isInteractive" && return 0
   cat <<EOF
----------------------------------------------------------------------------
SYNTAX:

To view and log current snapshot of statuses:
   ./$scriptFileName

To get this usage and syntax description:
   ./$scriptFileName [-help | help]

To remove an existing CRON Job (if any):
   ./$scriptFileName -delcronjob

To create a CRON Job to execute every 20 minutes:
   ./$scriptFileName -setcronjob

To create a CRON Job to execute every X minutes:
   ./$scriptFileName -setcronjob [10mins | 12mins | 15mins | 20mins | 30mins | 60mins]

To create a CRON Job to execute every X hours:
   ./$scriptFileName -setcronjob [1hour | 2hour | 3hour | 4hour | 5hour | 6hour | 8hour | 12hour | 24hour]

To set the maximum size of the log file in MByte units [DEFAULT is 1.0MB = 1024KB]:
   ./$scriptFileName -maxlogsize [$MIN_LogFileSizeMB to $MAX_LogFileSizeMB]

To enable sending email notifications for threshold alerts:
   ./$scriptFileName -enableEmailNotification

To disable sending email notifications for threshold alerts:
   ./$scriptFileName -disableEmailNotification

To test alert notifications using some dummy/fake threshold data:
   ./$scriptFileName [-cputest | -jffstest | -tmpfstest | -nvramtest]

To check for script updates:
   ./$scriptFileName -versioncheck [-verbose | -quiet | -veryquiet]
----------------------------------------------------------------------------
EOF
}

#-----------------------------------------------------------#
_GetCurrentFWVersion_()
{
   local theVersionStr  extVersNum

   fwInstalledBaseVers="$(nvram get firmver | sed 's/\.//g')"
   fwInstalledBuildVers="$(nvram get buildno)"
   fwInstalledExtendNum="$(nvram get extendno)"

   extVersNum="$fwInstalledExtendNum"
   echo "$extVersNum" | grep -qiE "^(alpha|beta)" && extVersNum="0_$extVersNum"
   [ -z "$extVersNum" ] && extVersNum=0

   theVersionStr="${fwInstalledBuildVers}.$extVersNum"
   [ -n "$fwInstalledBaseVers" ] && \
   theVersionStr="${fwInstalledBaseVers}.${theVersionStr}"

   echo "$theVersionStr"
}

#-----------------------------------------------------------#
_GetRouterModelID_()
{
   local retCode=1  routerModelID=""
   local nvramModelKeys="odmpid wps_modelnum model build_name"
   for nvramKey in $nvramModelKeys
   do
       routerModelID="$(nvram get "$nvramKey")"
       [ -n "$routerModelID" ] && retCode=0 && break
   done
   echo "$routerModelID" ; return "$retCode"
}

#-----------------------------------------------------------#
_DownloadCEMLibraryHelperFile_()
{
   local tempScriptFileDL="${CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH}.DL"

   [ ! -d "$ADDONS_SHARED_LIBS_DIR_PATH" ] && \
   mkdir -m 755 -p "$ADDONS_SHARED_LIBS_DIR_PATH" 2>/dev/null
   if [ ! -d "$ADDONS_SHARED_LIBS_DIR_PATH" ]
   then
       _PrintMsg_ "\n**ERROR**: Directory Path [$ADDONS_SHARED_LIBS_DIR_PATH] *NOT* FOUND.\n"
       return 1
   fi

   _PrintMsg_ "\nDownloading the library helper script file to support email notifications...\n"

   curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
        ${CUSTOM_EMAIL_LIB_SCRIPT_URL}/$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME \
        -o "$tempScriptFileDL"

   if [ ! -s "$tempScriptFileDL" ] || \
      grep -Eiq "^404: Not Found" "$tempScriptFileDL"
   then
       [ -s "$tempScriptFileDL" ] && { echo ; cat "$tempScriptFileDL" ; }
       rm -f "$tempScriptFileDL"
       _PrintMsg_ "\n**ERROR**: Unable to download the library helper script [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME]\n"
       return 1
   else
       mv -f "$tempScriptFileDL" "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       chmod 755 "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       . "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       _PrintMsg_ "The email library helper script [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME] was downloaded.\n"
       return 0
   fi
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

   if [ $# -gt 1 ] && echo "$2" | grep -qE "^(-quiet|-veryquiet)$"
   then isVerboseMode=false ; else isVerboseMode=true ; fi

   "$isVerboseMode" && \
   _PrintMsg_ "\nChecking for script updates...\n"

   curl -LSs --retry 4 --retry-delay 5 --retry-connrefused \
   "${LMS_SCRIPT_URL}/$LMS_VERFILE" -o "$theVersTextFile"

   if [ ! -s "$theVersTextFile" ] || \
      grep -Eiq "^404: Not Found" "$theVersTextFile"
   then
       [ -s "$theVersTextFile" ] && cat "$theVersTextFile"
       _PrintMsg_ "\n**ERROR**: Could not download the version file [$LMS_VERFILE]\n"
       rm -f "$theVersTextFile"
       return 1
   fi
   chmod 666 "$theVersTextFile"
   dlFileVerStr="$(cat "$theVersTextFile")"

   dlFileVerNum="$(_VersionStrToNum_ "$dlFileVerStr")"
   scriptVerNum="$(_VersionStrToNum_ "$LMS_VERSION")"

   if [ "$dlFileVerNum" -le "$scriptVerNum" ]
   then
       retCode=1
       "$isVerboseMode" && _PrintMsg_ "Done.\n"
   else
       retCode=0
       "$isVerboseMode" && \
       _PrintMsg_ "New script version update [$dlFileVerStr] available.\n"
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

#-----------------------------------------------------------------------#
_CreateConfigurationFile_()
{
   [ -s "$logMemStatsCFGfile" ] && return 0
   [ ! -d "$logMemStatsCFGdir" ] && \
   mkdir -m 755 "$logMemStatsCFGdir" 2>/dev/null
   [ ! -d "$logMemStatsCFGdir" ] && return 1

   {
      echo "## $(date +'%Y-%b-%d, %I:%M:%S %p %Z') ##"
      echo "maxLogFileSizeKB=$DEF_LogFileSizeKB"
      echo "userLogDirectoryPath=\"${defLogDirectoryPath}\""
      echo "prefLogDirectoryPath=\"${defLogDirectoryPath}\""
      echo "cpuEnableEmailNotifications=true"
      echo "cpuLastEmailNotificationTime=0_INIT"
      echo "jffsEnableEmailNotifications=true"
      echo "jffsLastEmailNotificationTime=0_INIT"
      echo "nvramEnableEmailNotifications=true"
      echo "nvramLastEmailNotificationTime=0_INIT"
      echo "tmpfsEnableEmailNotifications=true"
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

   local dateTimeStr

   if ! grep -qE "^## [0-9]+[-].* ##$" "$logMemStatsCFGfile"
   then
       dateTimeStr="## $(date +'%Y-%b-%d, %I:%M:%S %p %Z') ##"
       sed -i "1 i $dateTimeStr" "$logMemStatsCFGfile"
   fi
   if ! grep -qE "^maxLogFileSizeKB=[1-9][0-9]+$" "$logMemStatsCFGfile"
   then
       sed -i "/^maxLogFileSizeKB=/d" "$logMemStatsCFGfile"
       sed -i "2 i maxLogFileSizeKB=$DEF_LogFileSizeKB" "$logMemStatsCFGfile"
   fi
   if ! grep -q "^userLogDirectoryPath=" "$logMemStatsCFGfile"
   then
       sed -i "3 i userLogDirectoryPath=\"${defLogDirectoryPath}\"" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^prefLogDirectoryPath=" "$logMemStatsCFGfile"
   then
       sed -i "4 i prefLogDirectoryPath=\"${defLogDirectoryPath}\"" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -qE "^cpuEnableEmailNotifications=(true|false)$" "$logMemStatsCFGfile"
   then
       sed -i "/^cpuEnableEmailNotifications=/d" "$logMemStatsCFGfile"
       sed -i "5 i cpuEnableEmailNotifications=true" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^cpuLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "6 i cpuLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -qE "^jffsEnableEmailNotifications=(true|false)$" "$logMemStatsCFGfile"
   then
       sed -i "/^jffsEnableEmailNotifications=/d" "$logMemStatsCFGfile"
       sed -i "7 i jffsEnableEmailNotifications=true" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^jffsLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "8 i jffsLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -qE "^nvramEnableEmailNotifications=(true|false)$" "$logMemStatsCFGfile"
   then
       sed -i "/^nvramEnableEmailNotifications=/d" "$logMemStatsCFGfile"
       sed -i "9 i nvramEnableEmailNotifications=true" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^nvramLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "10 i nvramLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -qE "^tmpfsEnableEmailNotifications=(true|false)$" "$logMemStatsCFGfile"
   then
       sed -i "/^tmpfsEnableEmailNotifications=/d" "$logMemStatsCFGfile"
       sed -i "11 i tmpfsEnableEmailNotifications=true" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -q "^tmpfsLastEmailNotificationTime=" "$logMemStatsCFGfile"
   then
       sed -i "12 i tmpfsLastEmailNotificationTime=0_INIT" "$logMemStatsCFGfile"
       retCode=1
   fi
   if ! grep -qE "^isSendEmailNotificationsEnabled=(true|false)$" "$logMemStatsCFGfile"
   then
       sed -i "/^isSendEmailNotificationsEnabled=/d" "$logMemStatsCFGfile"
       echo "isSendEmailNotificationsEnabled=false" >> "$logMemStatsCFGfile"
       retCode=1
   fi
}

#-----------------------------------------------------------------------#
_GetConfigurationOption_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      [ ! -s "$logMemStatsCFGfile" ] || \
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
   local doShowMsg=false  theMsge=""  emailOpt

   _DoShowMsge_()
   {
       if "$doShowMsg" && [ -n "$theMsge" ]
       then _PrintMsg_ "$theMsge"
       fi
   }

   case "$1" in
       maxLogFileSizeKB)
            maxLogFileSizeKB="$2"
            userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"
            doShowMsg=true
            theMsge="\nMaximum log file size has has been set to ${maxLogFileSizeKB} KBytes.\n\n"
            ;;
       userLogDirectoryPath)
            userLogDirectoryPath="$2"
            scriptLogFPath="${2}/$scriptLogFName"
            backupLogFPath="${2}/$backupLogFName"
            ;;
       prefLogDirectoryPath)
            prefLogDirectoryPath="$2"
            ;;
       cpuEnableEmailNotifications)
            cpuEnableEmailNotifications="$2"
            ;;
       jffsEnableEmailNotifications)
            jffsEnableEmailNotifications="$2"
            ;;
       nvramEnableEmailNotifications)
            nvramEnableEmailNotifications="$2"
            ;;
       tmpfsEnableEmailNotifications)
            tmpfsEnableEmailNotifications="$2"
            ;;
       isSendEmailNotificationsEnabled)
            isSendEmailNotificationsEnabled="$2"
            doShowMsg=true
            [ "$2" = "true" ] && emailOpt="ENABLED" || emailOpt="DISABLED"
            theMsge="\nEmail Notification for alerts has been set to ${emailOpt}.\n\n"
            ;;
   esac

   keyName="$1"
   if ! grep -q "^${keyName}=" "$logMemStatsCFGfile"
   then
       echo "${keyName}=$2" >> "$logMemStatsCFGfile"
       _DoShowMsge_
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

   _DoShowMsge_
   return 0
}

#-----------------------------------------------------------------------#
_InitConfigurationSettings_()
{
   [ ! -s "$logMemStatsCFGfile" ] && return 1
   . "$logMemStatsCFGfile"

   if ! echo "$maxLogFileSizeKB" | grep -qE '^[1-9][0-9]+$' || \
      [ "$maxLogFileSizeKB" -lt "$MIN_LogFileSizeKB" ] || \
      [ "$maxLogFileSizeKB" -gt "$MAX_LogFileSizeKB" ]
   then
       _SetConfigurationOption_ maxLogFileSizeKB "$DEF_LogFileSizeKB"
   fi
   userMaxLogFileSize="$((maxLogFileSizeKB * 1024))"

   if [ -z "${isSendEmailNotificationsEnabled:+xSETx}" ] || \
      { [ "$isSendEmailNotificationsEnabled" != "true" ] && \
        [ "$isSendEmailNotificationsEnabled" != "false" ] ; }
   then
       _SetConfigurationOption_ isSendEmailNotificationsEnabled false
   fi
}

#-----------------------------------------------------------------------#
_CheckConfigurationFile_()
{
   _CreateConfigurationFile_
   _ValidateConfigurationFile_
   _InitConfigurationSettings_
}

#-------------------------------------
# To send email notifications alerts
#-------------------------------------
onehrSecs=3600
cpuEnableEmailNotifications=true
cpuLastEmailNotificationTime="0_INIT"
jffsEnableEmailNotifications=true
jffsLastEmailNotificationTime="0_INIT"
nvramEnableEmailNotifications=true
nvramLastEmailNotificationTime="0_INIT"
tmpfsEnableEmailNotifications=true
tmpfsLastEmailNotificationTime="0_INIT"
isSendEmailNotificationsEnabled=false

#-----------------------------------------------------------------------#
# CPU Celsius Temperature Thresholds
# >> 94 = Red Alert Level 3 [4 hrs]
# >> 92 = Red Alert Level 2 [12 hrs]
# >> 90 = Red Alert Level 1 [24 hrs]
# >> 89 = Yellow Warning Level 1 [48 hrs]
# <= 89 = Green OK
#-----------------------------------------------------------------------#
cpuTemperatureCelsius=""
cpuTempThresholdTestOnly=false
readonly cpuThermalThresholdTestOnly=10
readonly cpuThermalThresholdWarning1=89
readonly cpuThermalThresholdRedAlert1=90
readonly cpuThermalThresholdRedAlert2=92
readonly cpuThermalThresholdRedAlert3=94
readonly cpuTopRedAlertMinHours="$((onehrSecs * 4))"

#-----------------------------------------------------------------------#
# NVRAM Percent Usage Thresholds
# >> 97% Used = Red Alert Level 3 [4 hrs]
# >> 96% Used = Red Alert Level 2 [12 hrs]
# >> 95% Used = Red Alert Level 1 [24 hrs]
# >> 93% Used = Yellow Warning Level 2 [36 hrs]
# >> 90% Used = Yellow Warning Level 1 [48 hrs]
# <= 90% Used = Green OK
#-----------------------------------------------------------------------#
nvramUsageThresholdTestOnly=false
readonly nvramUsedThresholdTestOnly=10
readonly nvramUsedThresholdWarning1=90
readonly nvramUsedThresholdWarning2=93
readonly nvramUsedThresholdRedAlert1=95
readonly nvramUsedThresholdRedAlert2=96
readonly nvramUsedThresholdRedAlert3=97
readonly nvramTopRedAlertMinHours="$((onehrSecs * 4))"

#-----------------------------------------------------------------------#
# JFFS Filesystem Percent Usage Thresholds
# >> 85% Used = Red Alert Level 3 [4 hrs]
# >> 80% Used = Red Alert Level 2 [12 hrs]
# >> 75% Used = Red Alert Level 1 [24 hrs]
# >> 72% Used = Yellow Warning Level 2 [36 hrs]
# >> 70% Used = Yellow Warning Level 1 [48 hrs]
# <= 70% Used = Green OK
#-----------------------------------------------------------------------#
jffsUsageThresholdTestOnly=false
readonly jffsUsedThresholdTestOnly=1
readonly jffsUsedThresholdWarning1=70
readonly jffsUsedThresholdWarning2=72
readonly jffsUsedThresholdRedAlert1=75
readonly jffsUsedThresholdRedAlert2=80
readonly jffsUsedThresholdRedAlert3=85
readonly jffsTopRedAlertMinHours="$((onehrSecs * 4))"

#-----------------------------------------------------------------------#
# "tmpfs" Filesystem Percent Usage Thresholds
# >> 90% Used = Red Alert Level 3 [4 hrs]
# >> 85% Used = Red Alert Level 2 [12 hrs]
# >> 80% Used = Red Alert Level 1 [24 hrs]
# >> 75% Used = Yellow Warning Level 2 [36 hrs]
# >> 70% Used = Yellow Warning Level 1 [48 hrs]
# <= 70% Used = Green OK
#-----------------------------------------------------------------------#
tmpfsUsageThresholdTestOnly=false
readonly tmpfsUsedThresholdTestOnly=0
readonly tmpfsUsedThresholdWarning1=70
readonly tmpfsUsedThresholdWarning2=75
readonly tmpfsUsedThresholdRedAlert1=80
readonly tmpfsUsedThresholdRedAlert2=85
readonly tmpfsUsedThresholdRedAlert3=90
readonly tmpfsTopRedAlertMinHours="$((onehrSecs * 4))"

#-----------------------------------------------------------------------#
_CreateEMailContent_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1 ; fi

   local prevTimeStampSec  prevTimeStampTag  prevTimeStampStr
   local nextTimeStampSec  nextTimeStampTag  nextTimeStampStr
   local curTimeDiffSecs  minTimeDiffSecs
   local doConfigUpdate  timeStampID  theOptionTimeID  retCode

   rm -f "$tmpEMailBodyFile"

   case "$1" in
       CPU_TEMP_TestOnly)
           timeStampID=cpu
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router CPU Temperature [TESTING]"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "This notification is for <b>*TESTING*</b> PURPOSES ONLY.\n\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdTestOnly}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       CPU_TEMP_Warning1)
           timeStampID=cpu
           minTimeDiffSecs="$((onehrSecs * 48))"
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
           minTimeDiffSecs="$((onehrSecs * 24))"
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
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED2
           emailSubject="Router CPU Temperature ALERT"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdRedAlert2}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       CPU_TEMP_RedAlert3)
           timeStampID=cpu
           minTimeDiffSecs="$cpuTopRedAlertMinHours"
           nextTimeStampTag=RED3
           emailSubject="Router CPU Temperature ALERT"
           emailBodyTitle="CPU Temperature: ${2}°C"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router CPU temperature of <b>${2}°C</b> exceeds <b>${cpuThermalThresholdRedAlert3}°C</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_TestOnly)
           timeStampID=jffs
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router JFFS Usage [TESTING]"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "This notification is for <b>*TESTING*</b> PURPOSES ONLY.\n\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdTestOnly}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
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
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdWarning1}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_Warning2)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 36))"
           nextTimeStampTag=YLW2
           emailSubject="Router JFFS Usage WARNING"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdWarning2}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert1)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=RED1
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert1}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert2)
           timeStampID=jffs
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED2
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert2}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_USED_RedAlert3)
           timeStampID=jffs
           minTimeDiffSecs="$jffsTopRedAlertMinHours"
           nextTimeStampTag=RED3
           emailSubject="Router JFFS Usage ALERT"
           emailBodyTitle="JFFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS usage of <b>${2}%%</b> exceeds <b>${jffsUsedThresholdRedAlert3}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_NOT_MOUNTED)
           timeStampID=jffs
           minTimeDiffSecs="$jffsTopRedAlertMinHours"
           nextTimeStampTag=RED4
           emailSubject="Router JFFS NOT Mounted"
           emailBodyTitle="JFFS is *NOT* Mounted"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS partition is <b>NOT</b> found mounted.\n"
           } > "$tmpEMailBodyFile"
           ;;
       JFFS_READ_ONLY)
           timeStampID=jffs
           minTimeDiffSecs="$jffsTopRedAlertMinHours"
           nextTimeStampTag=RED5
           emailSubject="Router JFFS is READ-ONLY"
           emailBodyTitle="JFFS is READ-ONLY"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router JFFS partition is mounted <b>READ-ONLY</b>.\n"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_TestOnly)
           timeStampID=nvram
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router NVRAM Usage [TESTING]"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "This notification is for <b>*TESTING*</b> PURPOSES ONLY.\n\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdTestOnly}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_Warning1)
           timeStampID=nvram
           minTimeDiffSecs="$((onehrSecs * 48))"
           nextTimeStampTag=YLW1
           emailSubject="Router NVRAM Usage WARNING"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdWarning1}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_Warning2)
           timeStampID=nvram
           minTimeDiffSecs="$((onehrSecs * 36))"
           nextTimeStampTag=YLW2
           emailSubject="Router NVRAM Usage WARNING"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdWarning2}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_RedAlert1)
           timeStampID=nvram
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=RED1
           emailSubject="Router NVRAM Usage ALERT"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdRedAlert1}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_RedAlert2)
           timeStampID=nvram
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED2
           emailSubject="Router NVRAM Usage ALERT"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdRedAlert2}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_USED_RedAlert3)
           timeStampID=nvram
           minTimeDiffSecs="$nvramTopRedAlertMinHours"
           nextTimeStampTag=RED3
           emailSubject="Router NVRAM Usage ALERT"
           emailBodyTitle="NVRAM Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router NVRAM usage of <b>${2}%%</b> exceeds <b>${nvramUsedThresholdRedAlert3}%%</b>.\n"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       NVRAM_NOT_FOUND)
           timeStampID=nvram
           minTimeDiffSecs="$nvramTopRedAlertMinHours"
           nextTimeStampTag=RED4
           emailSubject="Router NVRAM NOT Found"
           emailBodyTitle="NVRAM was *NOT* Found"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router NVRAM was <b>NOT</b> found.\n"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_TestOnly)
           timeStampID=tmpfs
           minTimeDiffSecs=0
           nextTimeStampTag=TEST
           emailSubject="Router TMPFS Usage [TESTING]"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "This notification is for <b>*TESTING*</b> PURPOSES ONLY.\n\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdTestOnly}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
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
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdWarning1}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_Warning2)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 36))"
           nextTimeStampTag=YLW2
           emailSubject="Router TMPFS Usage WARNING"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>*WARNING*</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdWarning2}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert1)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 24))"
           nextTimeStampTag=RED1
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert1}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert2)
           timeStampID=tmpfs
           minTimeDiffSecs="$((onehrSecs * 12))"
           nextTimeStampTag=RED2
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert2}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
             printf "\n%s\n" "$3"
           } > "$tmpEMailBodyFile"
           ;;
       TMPFS_USED_RedAlert3)
           timeStampID=tmpfs
           minTimeDiffSecs="$tmpfsTopRedAlertMinHours"
           nextTimeStampTag=RED3
           emailSubject="Router TMPFS Usage ALERT"
           emailBodyTitle="TMPFS Usage: ${2}%"
           {
             printf "<b>**ALERT**</b>\n"
             printf "Router TMPFS usage of <b>${2}%%</b> exceeds <b>${tmpfsUsedThresholdRedAlert3}%%</b>.\n"
             printf "\n%s" "$(df -hT | head -n1)"
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
   theOptionTimeID="${timeStampID}LastEmailNotificationTime"

   prevTimeStampStr="$(_GetConfigurationOption_ "$theOptionTimeID")"
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
   elif echo "$nextTimeStampTag" | grep -qE "^(YLW[1-3]|RED[1-5])$"
   then
       curTimeDiffSecs="$((nextTimeStampSec - prevTimeStampSec))"
       if [ "$curTimeDiffSecs" -gt "$minTimeDiffSecs" ]
       then
           retCode=0
           doConfigUpdate=true
       fi
   fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ "$theOptionTimeID" "$nextTimeStampStr"

   return "$retCode"
}

#-----------------------------------------------------------------------#
_SendEMailNotification_()
{
   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       logTag="**WARNING**_${scriptFileName}_[$$]"
       logMsg="Email library script [$CUSTOM_EMAIL_LIB_SCRIPT_FNAME] *NOT* FOUND."
       _MsgToSysLog_ "$logMsg" WARN
       _PrintMsg_ "\n%s: %s\n\n" "$logTag" "$logMsg"
       _WaitForEnterKey_
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
       logMsg="Failure to send email notification [Error Code: $retCode] [$1]."
   fi
   _PrintMsg_ "\n${logTag} ${logMsg}\n"
   [ "$retCode" -ne 0 ] && _WaitForEnterKey_

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
_NVRAM_GetUsageInfo_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then echo "*ERROR**: NO Parameters" ; return 1 ; fi

   _GetFloat_() { printf "%.2f" "$(echo "$1" | awk "{print $1}")" ; }

   printf "NVRAM Used:  %7d Bytes = %6.2f KB [%4.1f%%]\n" \
          "$1" "$(_GetFloat_ "($1 / 1024)")" "$(_GetFloat_ "($1 * 100 / $3)")"
   printf "NVRAM Free:  %7d Bytes = %6.2f KB [%4.1f%%]\n" \
          "$2" "$(_GetFloat_ "($2 / 1024)")" "$(_GetFloat_ "($2 * 100 / $3)")"
   printf "NVRAM Total: %7d Bytes = %6.2f KB\n" \
          "$3" "$(_GetFloat_ "($3 / 1024)")"
}

#-----------------------------------------------------------------------#
_Show_NVRAM_Usage_()
{
   local tempFile  nvramUsageStr  total  usedx  freex
   tempFile="${HOMEdir}/nvramUsage.txt"
   nvram show 1>/dev/null 2>"$tempFile"
   nvramUsageStr="$(grep -i "^size:" "$tempFile")"
   rm -f "$tempFile"

   if [ -z "$nvramUsageStr" ]
   then
       printf "\n**ERROR**: NVRAM size info is NOT found.\n"
       return 1
   fi
   printf "\nNVRAM Usage:\n%s\n" "$nvramUsageStr"
   usedx="$(echo "$nvramUsageStr" | awk -F ' ' '{print $2}')"
   freex="$(echo "$nvramUsageStr" | awk -F ' ' '{print $4}')"
   freex="$(echo "$freex" | sed 's/[()]//g')"
   total="$((usedx + freex))"
   echo
   _NVRAM_GetUsageInfo_ "$usedx" "$freex" "$total"
   echo
}

#-----------------------------------------------------------------------#
_Show_JFFS_Usage_()
{
   _GetFloat_() { printf "%.2f" "$(echo "$1" | awk "{print $1}")" ; }
   local jffsMountStr  jffsUsageStr  typex  total  usedx  freex  totalx

   jffsMountStr="$(mount | grep -E '[[:blank:]]+/jffs[[:blank:]]+')"
   jffsUsageStr="$(df -kT /jffs | grep -E '.*[[:blank:]]+(jffs|ubifs).*[[:blank:]]+/jffs$')"

   if [ -z "$jffsMountStr" ] || [ -z "$jffsUsageStr" ]
   then
       printf "\n**ERROR**: JFFS partition is NOT found mounted.\n"
       return 1
   fi
   typex="$(echo "$jffsUsageStr" | awk -F ' ' '{print $2}')"
   total="$(echo "$jffsUsageStr" | awk -F ' ' '{print $3}')"
   usedx="$(echo "$jffsUsageStr" | awk -F ' ' '{print $4}')"
   freex="$(echo "$jffsUsageStr" | awk -F ' ' '{print $5}')"
   totalx="$total"

   if [ "$typex" = "ubifs" ] && [ "$((usedx + freex))" -ne "$total" ]
   then totalx="$((usedx + freex))" ; fi
   echo
   printf "JFFS Used:  %6d KB = %5.2f MB [%4.1f%%]\n" \
          "$usedx" "$(_GetFloat_ "($usedx / 1024)")" "$(_GetFloat_ "($usedx * 100 / $totalx)")"
   printf "JFFS Free:  %6d KB = %5.2f MB [%4.1f%%]\n" \
          "$freex" "$(_GetFloat_ "($freex / 1024)")" "$(_GetFloat_ "($freex * 100 / $totalx)")"
   printf "JFFS Total: %6d KB = %5.2f MB\n" \
          "$total" "$(_GetFloat_ "($total / 1024)")"

   if echo "$jffsMountStr" | grep -qE "[[:blank:]]+[(]?ro[[:blank:],]"
   then
       printf "\nMount Point:\n" ; echo "${jffsMountStr}"
       printf "\n**WARNING**\n"
       printf "JFFS partition appears to be READ-ONLY.\n"
   fi
}

#-----------------------------------------------------------------------#
_JFFS_MailUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || \
      ! "$isSendEmailNotificationsEnabled" || \
      ! "$jffsEnableEmailNotifications"
   then return 1 ; fi

   _SendEMailNotification_ "$@"
}

#-----------------------------------------------------------------------#
_JFFS_ShowUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1 ; fi

   local logMsg  alertMsg  usageThreshold  forTestOnly=false

   case "$1" in
       JFFS_NOT_MOUNTED)
           alertMsg="JFFS partition is *NOT* found mounted."
           {
              printf "\n**ALERT**\n${alertMsg}\n"
           } >> "$tempLogFPath"
           _MsgToSysLog_ "$alertMsg" ALERT
           return 0
           ;;
       JFFS_READ_ONLY)
           alertMsg="JFFS partition is mounted READ-ONLY."
           {
              printf "\n**ALERT**\n${alertMsg}\n"
           } >> "$tempLogFPath"
           _MsgToSysLog_ "$alertMsg" ALERT
           return 0
           ;;
       JFFS_USED_TestOnly)
           forTestOnly=true
           usageThreshold="$jffsUsedThresholdTestOnly"
           logMsg="This notification is for **TESTING** PURPOSES ONLY:"
           ;;
       JFFS_USED_Warning1)
           usageThreshold="$jffsUsedThresholdWarning1"
           logMsg="**WARNING**"
           ;;
       JFFS_USED_Warning2)
           usageThreshold="$jffsUsedThresholdWarning2"
           logMsg="**WARNING**"
           ;;
       JFFS_USED_RedAlert1)
           usageThreshold="$jffsUsedThresholdRedAlert1"
           logMsg="**ALERT**"
           ;;
       JFFS_USED_RedAlert2)
           usageThreshold="$jffsUsedThresholdRedAlert2"
           logMsg="**ALERT**"
           ;;
       JFFS_USED_RedAlert3)
           usageThreshold="$jffsUsedThresholdRedAlert3"
           logMsg="**ALERT**"
           ;;
       *) _PrintMsg_ "\n**ERROR**: UNKNOWN JFFS Usage Parameter [$1]\n"
           return 1
           ;;
   esac

   alertMsg="JFFS usage of ${2}% exceeds ${usageThreshold}%."
   {
      printf "\n${logMsg}\n"
      "$forTestOnly" && \
      printf "---------------------------------------------------\n"
      printf "%s\n" "$alertMsg"
      printf "%s\n" "$(df -hT | head -n1)"
      printf "%s\n" "$3"
   } >> "$tempLogFPath"

   _MsgToSysLog_ "$alertMsg" ALERT
   "$forTestOnly" && logMsg="**TESTING** ONLY"
   _MsgToSysLog_ "${logMsg}: [$3]" ALERT

   return 0
}

#-----------------------------------------------------------------------#
_CheckUsageThresholds_JFFS_()
{
   local jffsMountStr  jffsUsageStr  percentNum=0  doConfigUpdate
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag
   local returnAfterChecking=false

   jffsMountStr="$(mount | grep -E '[[:blank:]]+/jffs[[:blank:]]+')"
   jffsUsageStr="$(df -kT /jffs | grep -E '.*[[:blank:]]+(jffs|ubifs).*[[:blank:]]+/jffs$')"

   if [ -z "$jffsMountStr" ] || [ -z "$jffsUsageStr" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_NOT_MOUNTED UNKNOWN UNKNOWN
       _JFFS_MailUsageNotification_ JFFS_NOT_MOUNTED UNKNOWN UNKNOWN
       return 0
   fi

   if echo "$jffsMountStr" | grep -qE "[[:blank:]]+[(]?ro[[:blank:],]"
   then
       _JFFS_ShowUsageNotification_ JFFS_READ_ONLY UNKNOWN UNKNOWN
       _JFFS_MailUsageNotification_ JFFS_READ_ONLY UNKNOWN UNKNOWN
       returnAfterChecking=true
   fi

   percentNum="$(echo "$jffsUsageStr" | awk -F ' ' '{print $6}')"
   percentNum="$(echo "$percentNum" | awk -F '%' '{print $1}')"

   [ "$percentNum" -eq 0 ] && return 1

   if "$jffsUsageThresholdTestOnly" && \
      [ "$percentNum" -gt "$jffsUsedThresholdTestOnly" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_TestOnly "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_TestOnly "$percentNum" "$jffsUsageStr"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert3" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_RedAlert3 "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_RedAlert3 "$percentNum" "$jffsUsageStr"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert2" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_RedAlert2 "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_RedAlert2 "$percentNum" "$jffsUsageStr"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdRedAlert1" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_RedAlert1 "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_RedAlert1 "$percentNum" "$jffsUsageStr"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdWarning2" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_Warning2 "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_Warning2 "$percentNum" "$jffsUsageStr"
       return 0
   fi
   if [ "$percentNum" -gt "$jffsUsedThresholdWarning1" ]
   then
       _JFFS_ShowUsageNotification_ JFFS_USED_Warning1 "$percentNum" "$jffsUsageStr"
       _JFFS_MailUsageNotification_ JFFS_USED_Warning1 "$percentNum" "$jffsUsageStr"
       return 0
   fi

   "$returnAfterChecking" && return 0

   doConfigUpdate=false
   prevTimeStampStr="$(_GetConfigurationOption_ jffsLastEmailNotificationTime)"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   if [ -z "$prevTimeStampTag" ] || [ "$prevTimeStampTag" != "GRN" ]
   then doConfigUpdate=true ; fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ jffsLastEmailNotificationTime "${percentNum}_GRN"
   return 0
}

#-----------------------------------------------------------------------#
_NVRAM_MailUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || \
      ! "$isSendEmailNotificationsEnabled" || \
      ! "$nvramEnableEmailNotifications"
   then return 1 ; fi

   _SendEMailNotification_ "$@"
}

#-----------------------------------------------------------------------#
_NVRAM_ShowUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1 ; fi

   local logMsg  alertMsg  usageThreshold  usageInfo  forTestOnly=false

   case "$1" in
       NVRAM_NOT_FOUND)
           alertMsg="NVRAM was NOT found."
           {
              printf "\n**ALERT**\n${alertMsg}\n"
           } >> "$tempLogFPath"
           _MsgToSysLog_ "$alertMsg" ALERT
           return 0
           ;;
       NVRAM_USED_TestOnly)
           forTestOnly=true
           usageThreshold="$nvramUsedThresholdTestOnly"
           logMsg="This notification is for **TESTING** PURPOSES ONLY:"
           ;;
       NVRAM_USED_Warning1)
           usageThreshold="$nvramUsedThresholdWarning1"
           logMsg="**WARNING**"
           ;;
       NVRAM_USED_Warning2)
           usageThreshold="$nvramUsedThresholdWarning2"
           logMsg="**WARNING**"
           ;;
       NVRAM_USED_RedAlert1)
           usageThreshold="$nvramUsedThresholdRedAlert1"
           logMsg="**ALERT**"
           ;;
       NVRAM_USED_RedAlert2)
           usageThreshold="$nvramUsedThresholdRedAlert2"
           logMsg="**ALERT**"
           ;;
       NVRAM_USED_RedAlert3)
           usageThreshold="$nvramUsedThresholdRedAlert3"
           logMsg="**ALERT**"
           ;;
       *) _PrintMsg_ "\n**ERROR**: UNKNOWN NVRAM Usage Parameter [$1]\n"
           return 1
           ;;
   esac

   alertMsg="NVRAM usage of ${2}% exceeds ${usageThreshold}%."
   {
      printf "\n${logMsg}\n"
      "$forTestOnly" && \
      printf "---------------------------------------------------\n"
      printf "%s" "$alertMsg"
      printf "\n%s\n" "$3"
   } >> "$tempLogFPath"

   _MsgToSysLog_ "$alertMsg" ALERT
   "$forTestOnly" && logMsg="**TESTING** ONLY"
   usageInfo="$(echo "$3" | grep -E '^NVRAM Used:')"
   _MsgToSysLog_ "${logMsg}: [$usageInfo]" ALERT

   return 0
}

#-----------------------------------------------------------------------#
_CheckUsageThresholds_NVRAM_()
{
   _GetFloat_() { printf "%.1f" "$(echo "$1" | awk "{print $1}")" ; }
   _GetIntgr_() { printf "%.0f" "$(echo "$1" | awk "{print $1}")" ; }

   local tempFile  nvramUsageStr  total  usedx  freex
   local percentNum=0  doConfigUpdate  percentIntgr  percentFloat
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   tempFile="${HOMEdir}/nvramUsage.txt"
   nvram show 1>/dev/null 2>"$tempFile"
   nvramUsageStr="$(grep -i "^size:" "$tempFile")"
   rm -f "$tempFile"

   if [ -z "$nvramUsageStr" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_NOT_FOUND UNKNOWN UNKNOWN
       _NVRAM_MailUsageNotification_ NVRAM_NOT_FOUND UNKNOWN UNKNOWN
       return 0
   fi
   usedx="$(echo "$nvramUsageStr" | awk -F ' ' '{print $2}')"
   freex="$(echo "$nvramUsageStr" | awk -F ' ' '{print $4}')"
   freex="$(echo "$freex" | sed 's/[()]//g')"
   total="$((usedx + freex))"

   percentFloat="$(_GetFloat_ "($usedx * 100 / $total)")"
   percentIntgr="$(_GetIntgr_ "($percentFloat * 10)")"
   [ "$percentIntgr" -eq 0 ] && return 1
   nvramUsageStr="$(_NVRAM_GetUsageInfo_ "$usedx" "$freex" "$total")"

   if "$nvramUsageThresholdTestOnly" && \
      [ "$percentIntgr" -gt "${nvramUsedThresholdTestOnly}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_TestOnly "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_TestOnly "$percentFloat" "$nvramUsageStr"
       return 0
   fi
   if [ "$percentIntgr" -gt "${nvramUsedThresholdRedAlert3}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_RedAlert3 "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_RedAlert3 "$percentFloat" "$nvramUsageStr"
       return 0
   fi
   if [ "$percentIntgr" -gt "${nvramUsedThresholdRedAlert2}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_RedAlert2 "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_RedAlert2 "$percentFloat" "$nvramUsageStr"
       return 0
   fi
   if [ "$percentIntgr" -gt "${nvramUsedThresholdRedAlert1}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_RedAlert1 "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_RedAlert1 "$percentFloat" "$nvramUsageStr"
       return 0
   fi
   if [ "$percentIntgr" -gt "${nvramUsedThresholdWarning2}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_Warning2 "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_Warning2 "$percentFloat" "$nvramUsageStr"
       return 0
   fi
   if [ "$percentIntgr" -gt "${nvramUsedThresholdWarning1}5" ]
   then
       _NVRAM_ShowUsageNotification_ NVRAM_USED_Warning1 "$percentFloat" "$nvramUsageStr"
       _NVRAM_MailUsageNotification_ NVRAM_USED_Warning1 "$percentFloat" "$nvramUsageStr"
       return 0
   fi

   doConfigUpdate=false
   prevTimeStampStr="$(_GetConfigurationOption_ nvramLastEmailNotificationTime)"
   prevTimeStampSec="$(echo "$prevTimeStampStr" | awk -F '_' '{print $1}')"
   prevTimeStampTag="$(echo "$prevTimeStampStr" | awk -F '_' '{print $2}')"

   if [ -z "$prevTimeStampTag" ] || [ "$prevTimeStampTag" != "GRN" ]
   then doConfigUpdate=true ; fi

   "$doConfigUpdate" && \
   _SetConfigurationOption_ nvramLastEmailNotificationTime "${percentIntgr}_GRN"
   return 0
}

#-----------------------------------------------------------------------#
_TMPFS_MailUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || \
      ! "$isSendEmailNotificationsEnabled" || \
      ! "$tmpfsEnableEmailNotifications"
   then return 1 ; fi

   _SendEMailNotification_ "$@"
}

#-----------------------------------------------------------------------#
_TMPFS_ShowUsageNotification_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1 ; fi

   local logMsg  alertMsg  usageThreshold  forTestOnly=false

   case "$1" in
       TMPFS_USED_TestOnly)
           forTestOnly=true
           usageThreshold="$tmpfsUsedThresholdTestOnly"
           logMsg="This notification is for **TESTING** PURPOSES ONLY:"
           ;;
       TMPFS_USED_Warning1)
           usageThreshold="$tmpfsUsedThresholdWarning1"
           logMsg="**WARNING**"
           ;;
       TMPFS_USED_Warning2)
           usageThreshold="$tmpfsUsedThresholdWarning2"
           logMsg="**WARNING**"
           ;;
       TMPFS_USED_RedAlert1)
           usageThreshold="$tmpfsUsedThresholdRedAlert1"
           logMsg="**ALERT**"
           ;;
       TMPFS_USED_RedAlert2)
           usageThreshold="$tmpfsUsedThresholdRedAlert2"
           logMsg="**ALERT**"
           ;;
       TMPFS_USED_RedAlert3)
           usageThreshold="$tmpfsUsedThresholdRedAlert3"
           logMsg="**ALERT**"
           ;;
       *) _PrintMsg_ "\n**ERROR**: UNKNOWN TMPFS Usage Parameter [$1]\n"
           return 1
           ;;
   esac

   alertMsg="TMPFS usage of ${2}% exceeds ${usageThreshold}%."
   {
      printf "\n${logMsg}\n"
      "$forTestOnly" && \
      printf "---------------------------------------------------\n"
      printf "%s\n" "$alertMsg"
      printf "%s\n" "$(df -hT | head -n1)"
      printf "%s\n" "$3"
   } >> "$tempLogFPath"

   _MsgToSysLog_ "$alertMsg" ALERT
   "$forTestOnly" && logMsg="**TESTING** ONLY"
   _MsgToSysLog_ "${logMsg}: [$3]" ALERT

   return 0
}

#-----------------------------------------------------------------------#
_CheckUsageThresholds_TMPFS_()
{
   local tmpfsUsage  percentNum=0  doConfigUpdate
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   tmpfsUsage="$(df -hT | grep -E '^tmpfs[[:blank:]]+tmpfs .*[[:blank:]]+/tmp$')"
   if [ -n "$tmpfsUsage" ]
   then
       percentNum="$(echo "$tmpfsUsage" | awk -F ' ' '{print $6}')"
       percentNum="$(echo "$percentNum" | awk -F '%' '{print $1}')"
   fi
   if [ -z "$percentNum" ] || [ "$percentNum" -eq 0 ] ; then return 1 ; fi

   if "$tmpfsUsageThresholdTestOnly" && \
      [ "$percentNum" -gt "$tmpfsUsedThresholdTestOnly" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_TestOnly "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_TestOnly "$percentNum" "$tmpfsUsage"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert3" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_RedAlert3 "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_RedAlert3 "$percentNum" "$tmpfsUsage"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert2" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_RedAlert2 "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_RedAlert2 "$percentNum" "$tmpfsUsage"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdRedAlert1" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_RedAlert1 "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_RedAlert1 "$percentNum" "$tmpfsUsage"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdWarning2" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_Warning2 "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_Warning2 "$percentNum" "$tmpfsUsage"
       return 0
   fi
   if [ "$percentNum" -gt "$tmpfsUsedThresholdWarning1" ]
   then
       _TMPFS_ShowUsageNotification_ TMPFS_USED_Warning1 "$percentNum" "$tmpfsUsage"
       _TMPFS_MailUsageNotification_ TMPFS_USED_Warning1 "$percentNum" "$tmpfsUsage"
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
_CPU_MailTemperatureNotification_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      ! "$isSendEmailNotificationsEnabled" || \
      ! "$cpuEnableEmailNotifications"
   then return 1 ; fi

   _SendEMailNotification_ "$@"
}

#-----------------------------------------------------------------------#
_CPU_ShowTemperatureNotification_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1 ; fi

   local logMsg  alertMsg  cpuThermalThreshold  forTestOnly=false

   case "$1" in
       CPU_TEMP_TestOnly)
           forTestOnly=true
           cpuThermalThreshold="$cpuThermalThresholdTestOnly"
           logMsg="This notification is for **TESTING** PURPOSES ONLY:"
           ;;
       CPU_TEMP_Warning1)
           cpuThermalThreshold="$cpuThermalThresholdWarning1"
           logMsg="**WARNING**"
           ;;
       CPU_TEMP_RedAlert1)
           cpuThermalThreshold="$cpuThermalThresholdRedAlert1"
           logMsg="**ALERT**"
           ;;
       CPU_TEMP_RedAlert2)
           cpuThermalThreshold="$cpuThermalThresholdRedAlert2"
           logMsg="**ALERT**"
           ;;
       CPU_TEMP_RedAlert3)
           cpuThermalThreshold="$cpuThermalThresholdRedAlert3"
           logMsg="**ALERT**"
           ;;
       *) _PrintMsg_ "\n**ERROR**: UNKNOWN CPU Temperature Parameter [$1]\n"
           return 1
           ;;
   esac

   alertMsg="CPU temperature of ${2}°C exceeds ${cpuThermalThreshold}°C."
   {
      printf "\n${logMsg}\n"
      "$forTestOnly" && \
      printf "---------------------------------------------------\n"
      printf "%s\n" "$alertMsg"
   } >> "$tempLogFPath"

   _MsgToSysLog_ "$alertMsg" ALERT
   "$forTestOnly" && logMsg="**TESTING** ONLY"
   _MsgToSysLog_ "${logMsg}: [CPU temperature ${2}°C]" ALERT

   return 0
}

#-----------------------------------------------------------------------#
_CheckTemperatureThresholds_CPU_()
{
   if ! echo "$cpuTemperatureCelsius" | grep -qE '^[1-9][0-9]*[.]?[0-9]+$'
   then return 1 ; fi

   _GetIntgr_() { printf "%.0f" "$(echo "$1" | awk "{print $1}")" ; }

   local doConfigUpdate  tempIntgr  tempFloat
   local prevTimeStampStr  prevTimeStampSec  prevTimeStampTag

   tempIntgr="$(_GetIntgr_ "($cpuTemperatureCelsius * 10)")"
   tempFloat="$(printf "%.1f" "$cpuTemperatureCelsius")"

   if "$cpuTempThresholdTestOnly" && \
      [ "$tempIntgr" -gt "${cpuThermalThresholdTestOnly}9" ]
   then
       _CPU_ShowTemperatureNotification_ CPU_TEMP_TestOnly "$tempFloat"
       _CPU_MailTemperatureNotification_ CPU_TEMP_TestOnly "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdRedAlert3}9" ]
   then
       _CPU_ShowTemperatureNotification_ CPU_TEMP_RedAlert3 "$tempFloat"
       _CPU_MailTemperatureNotification_ CPU_TEMP_RedAlert3 "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdRedAlert2}9" ]
   then
       _CPU_ShowTemperatureNotification_ CPU_TEMP_RedAlert2 "$tempFloat"
       _CPU_MailTemperatureNotification_ CPU_TEMP_RedAlert2 "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdRedAlert1}9" ]
   then
       _CPU_ShowTemperatureNotification_ CPU_TEMP_RedAlert1 "$tempFloat"
       _CPU_MailTemperatureNotification_ CPU_TEMP_RedAlert1 "$tempFloat"
       return 0
   fi
   if [ "$tempIntgr" -gt "${cpuThermalThresholdWarning1}9" ]
   then
       _CPU_ShowTemperatureNotification_ CPU_TEMP_Warning1 "$tempFloat"
       _CPU_MailTemperatureNotification_ CPU_TEMP_Warning1 "$tempFloat"
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
_Get_CPU_Temptr_ProcDMUtemp_()
{
   local rawTemp  charPos3  cpuTemp
   rawTemp="$(awk -F ' ' '{print $4}' "$CPU_Temptr_ProcDMUtemp")"

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
_Get_CPU_Temptr_ThermalZone_()
{
   local rawTemp  cpuTemp
   rawTemp="$(cat "$CPU_Temptr_ThermalZone")"
   cpuTemp="$((rawTemp / 1000)).$(printf "%03d" "$((rawTemp % 1000))")"
   cpuTemperatureCelsius="$cpuTemp"
   printf "CPU Temperature: %.1f°C\n" "$cpuTemp"
}

#-----------------------------------------------------------------------#
_Get_CPU_Temptr_SysPowerCPU_()
{
   local rawTemp  cpuTemp
   rawTemp="$(cat "$CPU_Temptr_SysPowerCPU")"
   cpuTemp="$(echo "$rawTemp" | awk -F' ' '{printf $2}')"
   cpuTemperatureCelsius="$cpuTemp"
   printf "CPU Temperature: %.1f°C\n" "$cpuTemp"
}

#-----------------------------------------------------------------------#
_CPU_Temperature_()
{
   cpuTemperatureCelsius=""
   if [ -f "$CPU_Temptr_ProcDMUtemp" ]
   then
       _Get_CPU_Temptr_ProcDMUtemp_ ; return 0
   fi
   if [ -f "$CPU_Temptr_SysPowerCPU" ]
   then
       _Get_CPU_Temptr_SysPowerCPU_ ; return 0
   fi
   if [ -f "$CPU_Temptr_ThermalZone" ]
   then
       _Get_CPU_Temptr_ThermalZone_ ; return 0
   fi
   printf "\n**ERROR**: CPU Temperature file was *NOT* found.\n"
   return 1
}

#-----------------------------------------------------------------------#
_Show_USB_Drives_()
{
    local mounPointList  theMountPoint  mountPointCount
    local mountPointDev  mounPointPath  readWriteChck
    local mountPointRegExp="^/dev/sd.*[[:blank:]]+/tmp/mnt/.*"

    mounPointList="$(grep -E "$mountPointRegExp" /proc/mounts)"
    if [ -z "$mounPointList" ]
    then
        printf "\n\nINFO: No USB-attached drives were found mounted.\n\n"
        return 1
    fi

    mountPointCount=0
    while read -r theMountPoint
    do
        mountPointDev="$(echo "$theMountPoint" | awk -F ' ' '{print $1}')"
        mounPointPath="$(echo "$theMountPoint" | awk -F ' ' '{print $2}')"
        readWriteChck="$(echo "$theMountPoint" | awk -F ' ' '{print $4}' | cut -d',' -f1)"
        df -hT "$mountPointDev" | grep -E "^${mountPointDev}[[:blank:]]+.*[[:blank:]]+${mounPointPath}$"

        if [ -z "$readWriteChck" ]    || \
           [ "$readWriteChck" = 'ro' ] || \
           [ "$readWriteChck" != 'rw' ]
        then
            printf "**WARNING**: Mounted drive is NOT shown as writable.\n\n"
        fi
        mountPointCount="$((mountPointCount + 1))"
    done <<EOT
$(echo "$mounPointList" | sort -d -t ' ' -k 1)
EOT
}

#-----------------------------------------------------------------------#
_CompareNums_()
{
    if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || \
       ! echo "$1" | grep -qE "^${xNumberRegExp}$" || \
       ! echo "$3" | grep -qE "^${xNumberRegExp}$" || \
       ! echo "$2" | grep -qE "^(-eq|-lt|-gt|-le|-ge)$"
    then
        _PrintMsg_ "\n**ERROR**: INVALID or EMPTY parameter [$*]\n\n"
        return 1
    fi

    case "$2" in
        -eq) if awk -v num1="$1" -v num2="$3" 'BEGIN {exit !(num1 == num2)}'
             then return 0 ; else return 1 ; fi
             ;;
        -lt) if awk -v num1="$1" -v num2="$3" 'BEGIN {exit !(num1 < num2)}'
             then return 0 ; else return 1 ; fi
             ;;
        -gt) if awk -v num1="$1" -v num2="$3" 'BEGIN {exit !(num1 > num2)}'
             then return 0 ; else return 1 ; fi
             ;;
        -le) if awk -v num1="$1" -v num2="$3" 'BEGIN {exit !(num1 <= num2)}'
             then return 0 ; else return 1 ; fi
             ;;
        -ge) if awk -v num1="$1" -v num2="$3" 'BEGIN {exit !(num1 >= num2)}'
             then return 0 ; else return 1 ; fi
             ;;
    esac
}

#-----------------------------------------------------------------------#
_SetMaxLogFileSize_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! echo "$1" | grep -qE "^${xNumberRegExp}$" || \
       _CompareNums_ "$1" -lt "$MIN_LogFileSizeMB" || \
       _CompareNums_ "$1" -gt "$MAX_LogFileSizeMB"
    then
        _PrintMsg_ "\n**ERROR**: INVALID or EMPTY parameter [$*]\n"
        _PrintMsg_ "VALID values: $MIN_LogFileSizeMB to ${MAX_LogFileSizeMB} MBytes.\n\n"
        return 1
    fi
    local sizeValueKB
    _GetIntgr_() { printf "%.0f" "$(echo "$1" | awk "{print $1}")" ; }
    sizeValueKB="$(_GetIntgr_ "($1 * 1024)")"
    _SetConfigurationOption_ maxLogFileSizeKB "$sizeValueKB"
    return 0
}

#-----------------------------------------------------------------------#
_RemoveCronJobSetup_()
{
    local theCRU_Tag="#${CRON_Tag}#"

    if eval $cronListCmd | grep -qE "/.*/$scriptFileName ${theCRU_Tag}$"
    then
        $CRU_Cmd d "$CRON_Tag"
        sleep 1
        if ! eval $cronListCmd | grep -qE " ${theCRU_Tag}$"
        then
            _PrintMsg_ "\nExisting CRON Job [$theCRU_Tag] was DELETED.\n\n"
        else
            _PrintMsg_ "\nExisting CRON Job [$theCRU_Tag] *NOT* deleted.\n\n"
        fi
    else
        _PrintMsg_ "\nCRON Job [$theCRU_Tag] *NOT* found.\n\n"
    fi
}

#-----------------------------------------------------------------------#
_SetUpCronJob_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]       || \
       ! echo "$2" | grep -qE "^(${cronHourRegExp1}|[*])$" || \
       ! echo "$1" | grep -qE "^(${cronMinsRegExp0}|${cronMinsRegExp1})$"
    then
        _PrintMsg_ "\n**ERROR**: INVALID parameters [$*]\n\n"
        return 1
    fi
    local cronHour="*"  cronMins="$cronDefaultMins"
    local theCRU_Tag="#${CRON_Tag}#"  setCRONjob  cronJobStr
    local cronSchedule  cronJobFPath  cronTagStrng  cronTagName

    if [ "$1" -lt 6 ]
    then cronMins="$1"
    elif [ "$1" -lt 60 ]
    then cronMins="*/$1"
    fi
    if [ "$2" = "24" ]
    then cronHour="$cronDefaultHour"
    elif [ "$2" != "*" ] && [ "$2" -ne 1 ]
    then cronHour="*/$2"
    fi

    setCRONjob=false
    cronJobStr="$(eval $cronListCmd | grep -E " /.*/$scriptFileName ")"

    if [ -n "$cronJobStr" ]
    then
        cronTagStrng="$(echo "$cronJobStr" | awk -F ' ' '{print $NF}')"
        cronJobFPath="$(echo "$cronJobStr" | awk -F ' ' '{print $(NF-1)}')"
        cronSchedule="$(echo "$cronJobStr" | awk -F ' ' '{print $1, $2, $3, $4, $5}')"

        if [ "$cronTagStrng" != "$theCRU_Tag" ]    || \
           [ "$cronJobFPath" != "$scriptFilePath" ] || \
           [ "$cronSchedule" != "$cronMins $cronHour * * *" ]
        then
            cronTagName="$(echo "$cronTagStrng" | sed "s/#//g")"
            $CRU_Cmd d "$cronTagName"
            sleep 1
            if ! eval $cronListCmd | grep -qE " ${cronTagStrng}$"
            then
                setCRONjob=true
                _PrintMsg_ "\nExisting CRON Job [$cronTagStrng] was DELETED.\n"
            else
                _PrintMsg_ "\nExisting CRON Job [$theCRU_Tag] *NOT* deleted.\n\n"
            fi
        else
            _PrintMsg_ "\nThe CRON Job [$cronTagStrng] is already FOUND.\n"
            _PrintMsg_ "CRON: [$cronJobStr]\n\n"
        fi
    else
        _PrintMsg_ "\n"
    fi

    if "$setCRONjob" || [ -z "$cronJobStr" ]
    then
        $CRU_Cmd a "$CRON_Tag" "$cronMins $cronHour * * * $scriptFilePath"
        sleep 1
        cronJobStr="$(eval $cronListCmd | grep -E " $scriptFilePath ${theCRU_Tag}$")"
        if [ -n "$cronJobStr" ]
        then
            _PrintMsg_ "New CRON Job [$theCRU_Tag] was CREATED.\n"
            _PrintMsg_ "CRON: [$cronJobStr]\n\n"
        else
            _PrintMsg_ "\n**ERROR**: CANNOT create new CRON Job [$theCRU_Tag]\n\n"
        fi
    fi
}

#-----------------------------------------------------------------------#
_CheckForCronJobSetup_()
{
    local cronMins  cronHour

    if [ $# -eq 0 ] || [ -z "$1" ]
    then
        _SetUpCronJob_ 20 "*"  #DEFAULT: Every 20 minutes#
        return "$?"
    fi
    if echo "$1" | grep -qE "^${cronMinsRegExp2}$"
    then
        cronMins="$(echo "$1" | sed 's/mins//')"
        _SetUpCronJob_ "$cronMins" "*"
        return "$?"
    fi
    if echo "$1" | grep -qE "^${cronHourRegExp2}$"
    then
        cronHour="$(echo "$1" | sed 's/hour//')"
        _SetUpCronJob_ "$cronDefaultMins" "$cronHour"
        return "$?"
    fi

    _PrintMsg_ "\n**ERROR**: INVALID parameter [$1]\n"
    _PrintMsg_ "\nVALID parameters:\n"
    _PrintMsg_ "${cronValidMins}\n${cronValidHour}\n\n"
    return 1
}

quietArg=""
updateArg=""

for PARAM in "$@"
do
   case "$PARAM" in
       "-verbose" | "-quiet" | "-veryquiet")
          quietArg="$PARAM"
          ;;
       -versioncheck)
          updateArg="$PARAM"
          ;;
       *) ;; #CONTINUE#
   esac
done

if [ "$updateArg" = "-versioncheck" ]
then
    _CheckForScriptUpdates_ "$(pwd)" "$quietArg"
    exit $?
fi

numVal=0
numProcs=15
duUnits="HR"
downloadHelper=false
readonly routerMODEL_ID="$(_GetRouterModelID_)"
readonly routerFWversion="$(_GetCurrentFWVersion_)"

if [ "$SCRIPT_BRANCH" = "master" ]
then scriptVersInfo="$LMS_VERSION"
else scriptVersInfo="${LMS_VERSION}_${LMS_VERSTAG}"
fi

_CheckConfigurationFile_
_ValidateLogDirPath_ "$userLogDirectoryPath" "$prefLogDirectoryPath" "$altLogDirectoryPath"
_CheckLogFileSize_

if [ $# -gt 0 ] && [ -n "$1" ]
then
    case "$1" in
        -numprocs=[0-9]*)
           numVal="${1##*=}"
           if echo "$numVal" | grep -qE "^[1-9][0-9]{1,2}$"
           then
               numProcs="$numVal"
           else
               _PrintMsg_ "\n\n*ERROR**: INVALID parameter [$numVal]\n\n"
               exit 1
           fi
           ;;
        -cputest) cpuTempThresholdTestOnly=true
           ;;
        -jffstest) jffsUsageThresholdTestOnly=true
           ;;
        -tmpfstest) tmpfsUsageThresholdTestOnly=true
           ;;
        -nvramtest) nvramUsageThresholdTestOnly=true
           ;;
        -enableEmailNotification)
           _SetConfigurationOption_ isSendEmailNotificationsEnabled true
           exit 0
           ;;
        -disableEmailNotification)
           _SetConfigurationOption_ isSendEmailNotificationsEnabled false
           exit 0
           ;;
        -download)
           if [ $# -gt 1 ] && [ "$2" = "-cemdlhelper" ]
           then downloadHelper=true ; fi
           ;;
        -maxlogsize)
           shift ; _SetMaxLogFileSize_ "$@"
           exit 0
           ;;
        -setcronjob)
           shift ; _CheckForCronJobSetup_ "$@"
           exit 0
           ;;
        -delcronjob)
           _RemoveCronJobSetup_
           exit 0
           ;;
        -help|help)
           _ShowUsage_ ; exit 0
           ;;
        kb|KB|mb|MB)
           duUnits="$1"
           ;;
        *) _PrintMsg_ "\n*ERROR**: UNKNOWN parameter [$1]\n"
           _WaitForEnterKey_
           _ShowUsage_ ; exit 1
           ;;
    esac
fi

if "$isSendEmailNotificationsEnabled"
then
   if "$downloadHelper" || [ ! -s "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ]
   then _DownloadCEMLibraryHelperFile_ ; fi

   if [ -s "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ]
   then
       . "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       _CheckForLibraryScript_CEM_ "$updateArg" "$quietArg"
   else
       _PrintMsg_ "\n**ERROR**: Helper script file [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME] *NOT* FOUND.\n"

       [ -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ] && . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"
   fi
fi

{
   echo "=================================="
   date +"%Y-%b-%d, %I:%M:%S %p %Z (%a)"
   printf "Router Model: ${routerMODEL_ID}\n"
   printf "F/W Installed: ${routerFWversion}\n"
   printf "Script Version: $scriptVersInfo $branchStr_TAG\n\n"
   printf "Uptime\n------\n" ; uptime ; echo
   _CPU_Temperature_ ; echo
   printf "free:\n" ; free ; echo
   _ProcMemInfo_ ; echo
   df -hT | head -n1
   df -hT | grep -E '(/jffs$|/tmp$|/var$)' | sort -d -t ' ' -k 7
   _Show_USB_Drives_
   _Show_JFFS_Usage_
   _Show_NVRAM_Usage_
   case "$duUnits" in
       kb|KB) printf "KBytes [du /tmp/]\n-----------------\n"
              _InfoKBdu_ "/tmp" 25
              echo
              printf "KBytes [du /jffs]\n-----------------\n"
              _InfoKBdu_ "/jffs" 25
              ;;
       mb|MB) printf "MBytes [du /tmp/]\n-----------------\n"
              _InfoMBdu_ "/tmp" 25
              echo
              printf "MBytes [du /jffs]\n-----------------\n"
              _InfoMBdu_ "/jffs" 25
              ;;
       hr|HR) printf "[du /tmp/]\n----------\n"
              _InfoHRdu_ "/tmp" 25
              echo
              printf "[du /jffs]\n----------\n"
              _InfoHRdu_ "/jffs" 25
             ;;
   esac
   echo
   top -b -n1 | head -n "$((numProcs + 4))"
} > "$tempLogFPath"

_CheckUsageThresholds_JFFS_
_CheckUsageThresholds_NVRAM_
_CheckUsageThresholds_TMPFS_
_CheckTemperatureThresholds_CPU_

"$isInteractive" && cat "$tempLogFPath"
cat "$tempLogFPath" >> "$scriptLogFPath"
rm -f "$tempLogFPath"
_PrintMsg_ "\nLog entry was added to:\n${scriptLogFPath}\n\n"

exit 0

#EOF#
