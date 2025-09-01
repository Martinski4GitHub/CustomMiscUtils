#!/bin/sh
######################################################################
# SaveRestoreNVRAMvars.sh
#
# To save & restore the list of NVRAM variable key names defined
# in a specific file. The specified file must contain the exact
# NVRAM variable key names (e.g. "dhcp_staticlist"), one entry
# per line, in the "[Key Names]" section. Regular expressions
# for NVRAM key names can be input in the "[Key Names: RegEx]"
# section.
#
# Creation Date: 2021-Jan-24 [Martinski W.]
# Last Modified: 2024-Dec-19 [Martinski W.]
######################################################################
set -u

readonly ScriptVERSION="0.7.14"
readonly version_TAG="Version: $ScriptVERSION"

ScriptFolder="$(/usr/bin/dirname "$0")"
if [ "$ScriptFolder" = "." ]
then ScriptFolder="$(pwd)" ; fi

readonly theJFFSdir="/jffs"
readonly theTEMPdir="/tmp/var/tmp"
readonly theScriptFName="${0##*/}"

readonly customBackupFileExt="tar.gzip"
readonly JFFS_SubDirBackupPrefix="JFFSsubdir"
readonly NVRAM_VarsBackupFPrefix="NVRAM_Vars"
readonly NVRAM_VarsBackupDIRname="NVRAM_VarsBackup"
readonly NVRAM_VarsBackupCFGname="NVRAM_CustomBackupConfig.txt"
readonly NVRAM_VarsBackupSTAname="NVRAM_CustomBackupStatus.txt"

readonly NVRAM_Directory="${theJFFSdir}/nvram"
readonly NVRAM_TempDIRname="nvramTempBackup"
readonly NVRAM_TempDIRpath="${theTEMPdir}/$NVRAM_TempDIRname"
readonly NVRAM_TempFilesMatch="${NVRAM_TempDIRpath}/NVRAMvar_*.TMP"
readonly NVRAM_TempShowVarFle="${NVRAM_TempDIRpath}/NVRAMshowVars.TMP"
readonly NVRAM_TempShowFilter="([0-3]:.*|ASUS_EULA_time=|TM_EULA_time=|sys_uptime_now=)"

readonly NVRAM_ConfigVarPrefix="NVRAM_"
readonly NVRAM_DefUserBackupDir="/opt/var/$NVRAM_VarsBackupDIRname"
readonly NVRAM_AltUserBackupDir="/jffs/configs/$NVRAM_VarsBackupDIRname"

readonly SCRIPT_NVRAM_BACKUP_STATUS="/tmp/$NVRAM_VarsBackupSTAname"
readonly SCRIPT_NVRAM_BACKUP_CONFIG="${ScriptFolder}/$NVRAM_VarsBackupCFGname"
readonly nvramBackupCFGCommentLine="## DO *NOT* EDIT THIS FILE BELOW THIS LINE. IT'S DYNAMICALLY UPDATED ##"
readonly Line0SEP="========================================================================="

readonly NOct="\e[0m"
readonly BOLDtext="\e[1m"
readonly DarkRED="\e[0;31m"
readonly LghtGREEN="\e[1;32m"
readonly LghtYELLOW="\e[1;33m"
readonly InvREDct="\e[41m"
readonly InvBYLWct="\e[30;103m"
readonly REDct="${DarkRED}${BOLDtext}"
readonly GRNct="${LghtGREEN}${BOLDtext}"
readonly YLWct="${LghtYELLOW}${BOLDtext}"

readonly MaxBckupsOpt="mx"
readonly BackupDirOpt="dp"
readonly ListFileOpt="fl"
readonly menuBckpOpt="bk"
readonly menuRestOpt="rt"
readonly menuDeltOpt="de"
readonly menuListOpt="ls"

readonly savedFileDateTimeStr="%Y-%m-%d_%H-%M-%S"

readonly theHighWaterMarkThreshold=5
readonly NVRAMtheMinNumBackupFiles=5
readonly NVRAMtheMaxNumBackupFiles=50
readonly NVRAMdefMaxNumBackupFiles=20

## For JFFS subdirectories tightly coupled with NVRAM settings ##
JFFS_SubDirNTag=""
JFFS_SubDirName=""
JFFS_SubDirPath=""
JFFS_TempDIRpath=""
JFFS_BackupFPath=""
JFFS_SubDirFilesMatch=""
JFFS_BackupFilesMatch=""
JFFS_OPVPN_BackedUp=false
JFFS_OPVPN_Restored=false
JFFS_ICONS_BackedUp=false
JFFS_ICONS_Restored=false

backupsFound=false
isVerbose=false
isInteractive=false
customMaxNumBackupFiles="$NVRAMdefMaxNumBackupFiles"
nvramVarsUserBackupDir="$NVRAM_DefUserBackupDir"
nvramVarsPrefBackupDir="$nvramVarsUserBackupDir"
nvramVarsUserBackupFPath="${nvramVarsUserBackupDir}/$NVRAM_VarsBackupFPrefix"
nvramBackupFilesMatch="${nvramVarsUserBackupFPath}_*.$customBackupFileExt"

NVRAM_VarKeyName=""
NVRAM_KeyVARsaved=""
NVRAM_KeyFLEsaved=""

## File containing list of NVRAM variable key names to back up ##
NVRAM_VarListFName="NVRAM_VarList.txt"
nvramVarsListFilePath="$(pwd)/$NVRAM_VarListFName"

#------------------------------------------------------------------#
_ShowUsage_()
{
   ! "$isInteractive" && exit 0

   cat <<EOF
--------------------------------------------------------------------
SYNTAX:

./$theScriptFName { -help | -menu | -backup [-quiet] | -restore [-quiet] }

EXAMPLE CALLS:

To get this usage & syntax description:
   ./$theScriptFName -help

To run the script in "Menu Mode" (i.e. menu-driven actions).
   ./$theScriptFName -menu

To back up all NVRAM variables found in the default list file:
   ./$theScriptFName -backup

   Default file name listing NVRAM variable key names:
   ./$NVRAM_VarListFName"

To restore NVRAM variables from the most recent backup file found:
   ./$theScriptFName -restore

The "-quiet" parameter turns off most interactive messages
*except* for errors, warnings and important results.
--------------------------------------------------------------------
EOF
   exit 0
}

[ -t 0 ] && ! tty | grep -qwi "not" && isInteractive=true
isVerbose="$isInteractive"

if [ $# -eq 0 ] || [ "$1" = "help" ] || [ "$1" = "-help" ]
then _ShowUsage_ ; fi

trap 'exit 10' EXIT HUP INT QUIT ABRT TERM

#------------------------------------------------------------------#
_WaitForEnterKey_()
{
   ! "$isInteractive" && return 0
   printf "\nPress <Enter> key to continue..."
   read -r EnterKEY ; echo
}

#------------------------------------------------------------------#
_WaitForResponse_()
{
   ! "$isInteractive" && return 0

   local defaultAnswer="No"
   if [ $# -gt 1 ] && [ "$2" = "YES" ]
   then defaultAnswer="Yes" ; fi

   printf "$1 [yY|nN] ${defaultAnswer}? "
   read -r YESorNO
   [ -z "$YESorNO" ] && YESorNO="$defaultAnswer"
   echo
   if echo "$YESorNO" | grep -qE "^([Yy](es)?)$"
   then return 0
   else return 1
   fi
}

#------------------------------------------------------------------#
# shellcheck disable=SC2086
_movef_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1 ; fi
   local prevIFS="$IFS"
   IFS="$(printf '\n\t')"
   mv -f $1 "$2" ; retcode="$?"
   IFS="$prevIFS"
   return "$retcode"
}

#------------------------------------------------------------------#
# shellcheck disable=SC2086
_remf_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      [ "$1" = "*" ] || [ "$1" = ".*" ] || [ "$1" = "/*" ]
   then return 1 ; fi
   local prevIFS="$IFS"
   IFS="$(printf '\n\t')"
   rm -f $1 ; retcode="$?"
   IFS="$prevIFS"
   return "$retcode"
}

#------------------------------------------------------------------#
# shellcheck disable=SC2086
_list2_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1 ; fi
   local prevIFS="$IFS"
   IFS="$(printf '\n\t')"
   ls $1 $2 ; retcode="$?"
   IFS="$prevIFS"
   return "$retcode"
}

#------------------------------------------------------------------#
_PrintMsg0_()
{
   "$isInteractive" && printf "${1}"
   return 0
}

#------------------------------------------------------------------#
_PrintMsg1_()
{
   "$isVerbose" && printf "${1}" && return 0
   "$isInteractive" && printf "."
}

#------------------------------------------------------------------#
_PrintError_()
{
   "$isInteractive" && \
   printf "\n${InvREDct}**ERROR**${NOct}: ${1}\n"
}

#------------------------------------------------------------------#
_PrintWarning_()
{
   "$isInteractive" && \
   printf "\n${YLWct}*WARNING*${NOct}: ${1}\n"
}

#------------------------------------------------------------------#
_NVRAM_GetFromCustomBackupConfig_()
{
   keyName="${NVRAM_ConfigVarPrefix}$1"
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      [ ! -f "$SCRIPT_NVRAM_BACKUP_CONFIG" ] || \
      ! grep -q "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then echo "" ; return 1 ; fi

   keyValue="$(grep "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG" | awk -F '=' '{print $2}')"
   echo "$keyValue" ; return 0
}

#------------------------------------------------------------------#
_NVRAM_FixCustomBackupConfig_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1; fi

   keyName="${NVRAM_ConfigVarPrefix}$1"
   if ! grep -q "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       echo "${keyName}=$2" >> "$SCRIPT_NVRAM_BACKUP_CONFIG"
       return 0
   fi

   keyValue="$(grep "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG" | awk -F '=' '{print $2}')"
   if [ -z "$keyValue" ] || [ "$keyValue" = "NONE" ]
   then
       fixedVal="$(echo "$2" | sed 's/[\/.*-]/\\&/g')"
       sed -i "s/${keyName}=.*/${keyName}=${fixedVal}/" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   fi
}

#------------------------------------------------------------------#
_ClearCustomBackupStatus_()
{ rm -f "$SCRIPT_NVRAM_BACKUP_STATUS" ; }

#------------------------------------------------------------------#
_UpdateCustomBackupStatus_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1; fi

   if [ "$2" = "NONE" ] || [ ! -f "$2" ]
   then
       echo "${NVRAM_ConfigVarPrefix}${1}=NONE" > "$SCRIPT_NVRAM_BACKUP_STATUS"
   else
       echo "${NVRAM_ConfigVarPrefix}DIRP=${2%/*}"  >  "$SCRIPT_NVRAM_BACKUP_STATUS"
       echo "${NVRAM_ConfigVarPrefix}FILE=${2##*/}" >> "$SCRIPT_NVRAM_BACKUP_STATUS"
       echo "${NVRAM_ConfigVarPrefix}${1}=OK"       >> "$SCRIPT_NVRAM_BACKUP_STATUS"
   fi
}

#------------------------------------------------------------------#
_NVRAM_ResetBackupFilePaths_()
{
   nvramVarsUserBackupFPath="${1}/$NVRAM_VarsBackupFPrefix"
   nvramBackupFilesMatch="${nvramVarsUserBackupFPath}_*.$customBackupFileExt"
}

#------------------------------------------------------------------#
_NVRAM_UpdateCustomBackupConfig_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1; fi

   if [ "$1" = "SAVED_DIR" ]
   then
       nvramVarsUserBackupDir="$2"
       _NVRAM_ResetBackupFilePaths_ "$nvramVarsUserBackupDir"
   #
   elif [ "$1" = "PREFS_DIR" ]
   then nvramVarsPrefBackupDir="$2"
   #
   elif [ "$1" = "LIST_FILE" ]
   then nvramVarsListFilePath="$2" ; fi

   if [ $# -eq 3 ] && [ "$3" = "STATUSupdate" ] && \
      { [ "$1" = "SAVED" ] || [ "$1" = "RESTD" ] ; } && \
      { [ "$2" = "NONE" ] || [ -f "$2" ] ; }
   then _UpdateCustomBackupStatus_ "$1" "$2" ; fi

   keyName="${NVRAM_ConfigVarPrefix}$1"
   if ! grep -q "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       echo "${keyName}=$2" >> "$SCRIPT_NVRAM_BACKUP_CONFIG"
       return 0
   fi

   keyValue="$(grep "^${keyName}=" "$SCRIPT_NVRAM_BACKUP_CONFIG" | awk -F '=' '{print $2}')"
   if [ -z "$keyValue" ] || [ "$keyValue" != "$2" ]
   then
       fixedVal="$(echo "$2" | sed 's/[\/.*-]/\\&/g')"
       sed -i "s/${keyName}=.*/${keyName}=${fixedVal}/" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   fi
}

#------------------------------------------------------------------#
_NVRAM_InitCustomBackupConfig_()
{
   thePrefix="$NVRAM_ConfigVarPrefix"
   if [ ! -f "$SCRIPT_NVRAM_BACKUP_CONFIG" ]
   then
      {
       echo "$nvramBackupCFGCommentLine"
       echo "${thePrefix}SAVED_MAX=20"
       echo "${thePrefix}SAVED_DIR=NONE"
       echo "${thePrefix}PREFS_DIR=NONE"
       echo "${thePrefix}LIST_FILE=NONE"
       echo "${thePrefix}SAVED=NONE"
       echo "${thePrefix}RESTD=NONE"
      } > "$SCRIPT_NVRAM_BACKUP_CONFIG"
       return 1
   fi
   local retCode=0

   commentStr="$(echo "$nvramBackupCFGCommentLine" | sed 's/[.*-]/\\&/g')"
   nFoundStr="$(grep -n "^${commentStr}" "$SCRIPT_NVRAM_BACKUP_CONFIG")"
   if [ -z "$nFoundStr" ] || \
      [ "$(echo "$nFoundStr" | awk -F ':' '{print $1}')" -ne 1 ]
   then
       sed -i "\\~${commentStr}~d" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       sed -i "1 i ${nvramBackupCFGCommentLine}" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       retCode=1
   fi
   if ! grep -q "^${thePrefix}SAVED_MAX=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       sed -i "2 i ${thePrefix}SAVED_MAX=20" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       retCode=1
   fi
   if ! grep -q "^${thePrefix}SAVED_DIR=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       sed -i "3 i ${thePrefix}SAVED_DIR=NONE" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       retCode=1
   fi
   if ! grep -q "^${thePrefix}PREFS_DIR=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       sed -i "4 i ${thePrefix}PREFS_DIR=NONE" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       retCode=1
   fi
   if ! grep -q "^${thePrefix}LIST_FILE=" "$SCRIPT_NVRAM_BACKUP_CONFIG"
   then
       sed -i "5 i ${thePrefix}LIST_FILE=NONE" "$SCRIPT_NVRAM_BACKUP_CONFIG"
       retCode=1
   fi
   return "$retCode"
}

#-----------------------------------------------------------#
_GetDefaultUSBMountPoint_()
{
   local mounPointPath  retCode=0
   local mountPointRegExp="^/dev/sd.* /tmp/mnt/.*"

   mounPointPath="$(grep -m1 "$mountPointRegExp" /proc/mounts | awk -F ' ' '{print $2}')"
   [ -z "$mounPointPath" ] && retCode=1
   echo "$mounPointPath" ; return "$retCode"
}

#------------------------------------------------------------------#
_IsPathInUSBMountPoint_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1; fi
   if echo "$1" | grep -qE "^(/tmp/mnt/|/tmp/opt/|/mnt/|/opt/)"
   then return 0 ; else return 1 ; fi
}

#------------------------------------------------------------------#
_NVRAM_ValidateUserBackupDirectory_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1; fi

   [ ! -d "$nvramVarsUserBackupDir" ] && \
   mkdir -m 755 "$nvramVarsUserBackupDir" 2>/dev/null
   [ -d "$nvramVarsUserBackupDir" ] && return 0

   if [ -z "$defUSBMountPoint" ] && \
      _IsPathInUSBMountPoint_ "$nvramVarsUserBackupDir"
   then errorMsg="\n${REDct}**INFO**${NOct}"
   else errorMsg="\n${REDct}**ERROR**${NOct}"
   fi

   if "$isInteractive"
   then
      printf "${errorMsg}: "
      printf "Backup directory [${InvREDct} ${nvramVarsUserBackupDir} ${NOct}] NOT FOUND."
      printf "\nTrying again with directory [$1]\n"
   fi

   nvramVarsUserBackupDir="$1"
   switchBackupDir=true
   return 1
}

#------------------------------------------------------------------#
_NVRAM_GetCustomBackupConfigVars_()
{
   local switchBackupDir  nvramVarsSavdBackupDir  defUSBMountPoint
   local resetBackupFilePaths=false

   switchBackupDir=false
   defUSBMountPoint="$(_GetDefaultUSBMountPoint_)"
   nvramVarsSavdBackupDir="$(_NVRAM_GetFromCustomBackupConfig_ "SAVED_DIR")"
   nvramVarsPrefBackupDir="$(_NVRAM_GetFromCustomBackupConfig_ "PREFS_DIR")"
   nvramVarsListFilePath="$(_NVRAM_GetFromCustomBackupConfig_ "LIST_FILE")"

   if [ -z "$nvramVarsSavdBackupDir" ] || [ "$nvramVarsSavdBackupDir" = "NONE" ]
   then nvramVarsSavdBackupDir="$NVRAM_DefUserBackupDir" ; fi

   if [ -z "$nvramVarsPrefBackupDir" ] || [ "$nvramVarsPrefBackupDir" = "NONE" ]
   then
       nvramVarsPrefBackupDir="$nvramVarsSavdBackupDir"
       _NVRAM_UpdateCustomBackupConfig_ PREFS_DIR "$nvramVarsPrefBackupDir"
   fi

   if [ "$nvramVarsUserBackupDir" != "$nvramVarsPrefBackupDir" ]
   then
       resetBackupFilePaths=true
       nvramVarsUserBackupDir="$nvramVarsPrefBackupDir"
   fi

   for nextBKdir in "$nvramVarsSavdBackupDir" "$NVRAM_DefUserBackupDir" "$NVRAM_AltUserBackupDir"
   do _NVRAM_ValidateUserBackupDirectory_ "$nextBKdir" && break ; done

   mkdir -m 755 "$nvramVarsUserBackupDir" 2>/dev/null
   if [ ! -d "$nvramVarsUserBackupDir" ]
   then
       _PrintError_ "Backup directory [${InvREDct} ${nvramVarsUserBackupDir} ${NOct}] NOT FOUND."
       _WaitForEnterKey_
       return 1
   fi

   if [ "$nvramVarsListFilePath" = "NONE" ] || \
      [ ! -f "$nvramVarsListFilePath" ]     || \
      [ ! -s "$nvramVarsListFilePath" ]
   then
       _PrintError_ "NVRAM variable list file [${InvREDct} ${nvramVarsListFilePath} ${NOct}] is EMPTY or NOT FOUND."
       _WaitForEnterKey_
       return 1
   fi

   if "$switchBackupDir"
   then
       _NVRAM_UpdateCustomBackupConfig_ SAVED_DIR "$nvramVarsUserBackupDir"
       LogMsg="Using Alternative Backup directory [$nvramVarsUserBackupDir]"
       _PrintWarning_ "$LogMsg"
       _WaitForEnterKey_
   else
       "$resetBackupFilePaths" && \
       _NVRAM_ResetBackupFilePaths_ "$nvramVarsUserBackupDir"
   fi

   customMaxNumBackupFiles="$(_NVRAM_GetFromCustomBackupConfig_ "SAVED_MAX")"
   if [ -z "$customMaxNumBackupFiles" ] || \
      ! echo "$customMaxNumBackupFiles" | grep -qE "^[0-9]{1,}$"
   then customMaxNumBackupFiles="$NVRAMdefMaxNumBackupFiles" ; fi

   if [ "$customMaxNumBackupFiles" -lt "$NVRAMtheMinNumBackupFiles" ]
   then customMaxNumBackupFiles="$NVRAMtheMinNumBackupFiles" ; fi

   if [ "$customMaxNumBackupFiles" -gt "$NVRAMtheMaxNumBackupFiles" ]
   then customMaxNumBackupFiles="$NVRAMtheMaxNumBackupFiles" ; fi

   _NVRAM_UpdateCustomBackupConfig_ SAVED_MAX "$customMaxNumBackupFiles"
   return 0
}

#------------------------------------------------------------------#
_CheckCustomBackupConfig_()
{
   if ! _NVRAM_InitCustomBackupConfig_
   then
       _NVRAM_FixCustomBackupConfig_ SAVED NONE
       _NVRAM_FixCustomBackupConfig_ RESTD NONE
       _NVRAM_FixCustomBackupConfig_ SAVED_MAX "$NVRAMdefMaxNumBackupFiles"
       _NVRAM_FixCustomBackupConfig_ SAVED_DIR "$NVRAM_DefUserBackupDir"
       _NVRAM_FixCustomBackupConfig_ PREFS_DIR "$NVRAM_DefUserBackupDir"
       _NVRAM_FixCustomBackupConfig_ LIST_FILE "$nvramVarsListFilePath"
   fi
   _NVRAM_GetCustomBackupConfigVars_
   return "$?"
}

#------------------------------------------------------------------#
_JFFS_SetSubDirVars_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then
       _PrintError_ "JFFS subdirectory parameters [${REDct}${*}${NOct}] EMPTY.\n"
       return 1
   fi

   local subDirFilesMatch="*"
   if [ "$1" = "ICONS" ] ; then subDirFilesMatch="*.log" ; fi

   JFFS_SubDirNTag="$1"
   JFFS_SubDirName="$2"
   JFFS_SubDirPath="${theJFFSdir}/$2"
   JFFS_TempDIRpath="$NVRAM_TempDIRpath"
   JFFS_BackupFPath="${JFFS_TempDIRpath}/${JFFS_SubDirBackupPrefix}_$1"
   JFFS_SubDirFilesMatch="${JFFS_SubDirPath}/$subDirFilesMatch"
   JFFS_BackupFilesMatch="${JFFS_BackupFPath}.$customBackupFileExt"

   if [ ! -d "$JFFS_TempDIRpath" ]
   then mkdir -m 755 "$JFFS_TempDIRpath" 2>/dev/null ; fi
   return 0
}

#------------------------------------------------------------------#
_JFFS_BackUpSubDirFiles_()
{
   local dirFileCount  retCode

   dirFileCount="$(_list2_ -1 "$JFFS_SubDirFilesMatch" 2>/dev/null | wc -l)"
   if [ ! -d "$JFFS_SubDirPath" ] || [ "$dirFileCount" -eq 0 ]
   then return 1 ; fi

   if ! tar -czf "$JFFS_BackupFilesMatch" -C "$theJFFSdir" "./$JFFS_SubDirName"
   then
       retCode=1
       _PrintError_ "Could NOT save JFFS subdirectory [$JFFS_SubDirPath] files."
   else
       retCode=0
       eval JFFS_${JFFS_SubDirNTag}_BackedUp=true
       chmod 664 "$JFFS_BackupFilesMatch"
       _PrintMsg1_ "JFFS subdirectory \"${GRNct}${JFFS_SubDirPath}${NOct}\" was backed up.\n"
   fi
   return "$retCode"
}

#------------------------------------------------------------------#
_JFFS_BackUpSubDir_()
{
   case "$1" in
       "OPVPN") _JFFS_SetSubDirVars_ "OPVPN" "openvpn" ;;
       "ICONS") _JFFS_SetSubDirVars_ "ICONS" "usericon" ;;
       *)
          JFFS_SubDirNTag="" ; JFFS_SubDirName="" ; JFFS_SubDirPath=""
          _PrintError_ "JFFS directory tag [${REDct}${1}${NOct}] NOT VALID."
          return 1
          ;;
   esac
   _JFFS_BackUpSubDirFiles_
}

#------------------------------------------------------------------#
_JFFS_CheckToBackUpSubDir_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   if [ "$1" = "custom_clientlist" ] && ! "$JFFS_ICONS_BackedUp"
   then _JFFS_BackUpSubDir_ "ICONS"
   #
   elif ! "$JFFS_OPVPN_BackedUp" && \
        echo "$1" | grep -qE "^vpn_server[1-2]_|^vpn_client[0-5]_"
   then _JFFS_BackUpSubDir_ "OPVPN" ; fi
}

#------------------------------------------------------------------#
_JFFS_RestoreSubDirFiles_()
{
   local retCode

   if [ ! -d "$JFFS_TempDIRpath" ] || [ ! -f "$JFFS_BackupFilesMatch" ]
   then return 1 ; fi

   if ! tar -xzf "$JFFS_BackupFilesMatch" -C "$theJFFSdir"
   then
       retCode=1
       _PrintError_ "JFFS subdirectory \"${REDct}${JFFS_SubDirPath}${NOct}\" was *NOT* restored."
   else
       retCode=0
       eval JFFS_${JFFS_SubDirNTag}_Restored=true
       _PrintMsg1_ "JFFS subdirectory \"${GRNct}${JFFS_SubDirPath}${NOct}\" was restored.\n"
   fi
   return "$retCode"
}

#------------------------------------------------------------------#
_JFFS_RestoreSubDir_()
{
   case "$1" in
       "OPVPN") _JFFS_SetSubDirVars_ "OPVPN" "openvpn" ;;
       "ICONS") _JFFS_SetSubDirVars_ "ICONS" "usericon" ;;
       *)
          JFFS_SubDirNTag="" ; JFFS_SubDirName="" ; JFFS_SubDirPath=""
          _PrintError_ "JFFS directory tag [${REDct}${1}${NOct}] NOT VALID."
          return 1
          ;;
   esac
   _JFFS_RestoreSubDirFiles_
}

#------------------------------------------------------------------#
_JFFS_CheckToRestoreSubDir_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   if [ "$1" = "custom_clientlist" ] && ! "$JFFS_ICONS_Restored"
   then _JFFS_RestoreSubDir_ "ICONS"
   #
   elif ! "$JFFS_OPVPN_Restored" && \
        echo "$1" | grep -qE "^vpn_server[1-2]_|^vpn_client[0-5]_"
   then _JFFS_RestoreSubDir_ "OPVPN" ; fi
}

#------------------------------------------------------------------#
_NVRAM_CleanupTempFiles_()
{
   if [ $# -eq 0 ] || [ "$1" != "-ALL" ]
   then
       rm -f "$NVRAM_KeyVARsaved" "$NVRAM_KeyFLEsaved"
   else
       _remf_ "${NVRAM_TempDIRpath}/*.TMP"
       _remf_ "${NVRAM_TempDIRpath}/*.$customBackupFileExt"
       rmdir "$NVRAM_TempDIRpath" 2>/dev/null

       JFFS_ICONS_BackedUp=false ; JFFS_ICONS_Restored=false
       JFFS_OPVPN_BackedUp=false ; JFFS_OPVPN_Restored=false
   fi
}

#------------------------------------------------------------------#
_NVRAM_VarSetKeyInfo_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi
   if echo "$1" | grep -q "[^a-zA-Z0-9_.:-]"
   then
       _PrintError_ "NVRAM variable key name \"${REDct}${1}${NOct}\" *NOT* VALID."
       return 1
   fi
   NVRAM_VarKeyName="$1"
   NVRAM_KeyVARsaved="${NVRAM_TempDIRpath}/NVRAMvar_${NVRAM_VarKeyName}.TMP"
   NVRAM_KeyFLEsaved="${NVRAM_TempDIRpath}/NVRAMfle_${NVRAM_VarKeyName}.TMP"
   if [ ! -d "$NVRAM_TempDIRpath" ]
   then mkdir -m 755 "$NVRAM_TempDIRpath" 2>/dev/null ; fi
   return 0
}

#------------------------------------------------------------------#
_NVRAM_VarSaveKeyValue_()
{
   local theKeyValue  NVRAM_SavedOK=false

   if [ -f "${NVRAM_Directory}/$NVRAM_VarKeyName" ]
   then
       if cp -fp "${NVRAM_Directory}/$NVRAM_VarKeyName" "$NVRAM_KeyFLEsaved"
       then NVRAM_SavedOK=true ; fi
   fi

   if grep -qE "^${NVRAM_VarKeyName}=" "$NVRAM_TempShowVarFle"
   then
       theKeyValue="$(grep -m1 -E "^${NVRAM_VarKeyName}=" "$NVRAM_TempShowVarFle" | awk -F '=' '{print $2}')"
       echo "$theKeyValue" > "$NVRAM_KeyVARsaved"
       NVRAM_SavedOK=true
   fi

   if "$NVRAM_SavedOK"
   then
       _JFFS_CheckToBackUpSubDir_ "$NVRAM_VarKeyName"
       _PrintMsg1_ "NVRAM variable \"${GRNct}${NVRAM_VarKeyName}${NOct}\" was backed up.\n"
       return 0
   fi

   _PrintWarning_ "NVRAM variable key name \"${InvBYLWct}${NVRAM_VarKeyName}${NOct}\" *NOT* FOUND."
   return 1
}

#------------------------------------------------------------------#
_NVRAM_VarRestoreKeyValue_()
{
   local NVRAM_RestoredOK=false  NVRAM_FoundOK=false
   local theKeyValueSaved

   if [ -d "$NVRAM_Directory" ] && [ -f "$NVRAM_KeyFLEsaved" ] && \
      [ "$(ls -1 "$NVRAM_Directory" 2>/dev/null | wc -l)" -gt 0 ]
   then
       theKeyValueSaved="$(cat "$NVRAM_KeyFLEsaved")"
       if [ "$(nvram get "$NVRAM_VarKeyName")" = "$theKeyValueSaved" ]
       then
           NVRAM_FoundOK=true
       else
           nvram set ${NVRAM_VarKeyName}="$theKeyValueSaved"
           mv -f "$NVRAM_KeyFLEsaved" "${NVRAM_Directory}/$NVRAM_VarKeyName"
           NVRAM_RestoredOK=true
       fi
   fi

   if [ -f "$NVRAM_KeyVARsaved" ]
   then
      theKeyValueSaved="$(cat "$NVRAM_KeyVARsaved")"
      if [ "$(nvram get "$NVRAM_VarKeyName")" = "$theKeyValueSaved" ]
      then
          NVRAM_FoundOK=true
      else
          nvram set ${NVRAM_VarKeyName}="$theKeyValueSaved"
          NVRAM_RestoredOK=true
      fi
   fi
   _NVRAM_CleanupTempFiles_

   if "$NVRAM_RestoredOK" || "$NVRAM_FoundOK"
   then _JFFS_CheckToRestoreSubDir_ "$NVRAM_VarKeyName" ; fi

   if "$NVRAM_RestoredOK"
   then
       _PrintMsg1_ "NVRAM variable \"${GRNct}${NVRAM_VarKeyName}${NOct}\" was restored.\n"
       nvram commit && return 0
   fi
   if "$NVRAM_FoundOK"
   then
       NVRAM_VarFoundOK=true
       _PrintMsg1_ "NVRAM variable \"${GRNct}${NVRAM_VarKeyName}${NOct}\" did NOT need to be restored.\n"
       return 1
   fi

   _PrintError_ "NVRAM variable \"${REDct}${NVRAM_VarKeyName}${NOct}\" was *NOT* restored."
   return 1
}

#------------------------------------------------------------------#
_CheckForBackupFiles_()
{
   theFileCount="$(_list2_ -1 "$nvramBackupFilesMatch" 2>/dev/null | wc -l)"
   if [ ! -d "$nvramVarsUserBackupDir" ] || [ "$theFileCount" -eq 0 ]
   then
       backupsFound=false
       _NVRAM_UpdateCustomBackupConfig_ SAVED NONE
       _NVRAM_UpdateCustomBackupConfig_ RESTD NONE
       return 1
   fi
   backupsFound=true  theBackupFile=""

   if [ $# -gt 0 ] && [ "$1" = "true" ]
   then   ## Update to the MOST recent backup file ##
       while IFS="$(printf '\n\t')" read -r theFILE
       do theBackupFile="$theFILE" ; break
       done <<EOT
$(_list2_ -1t "$nvramBackupFilesMatch" 2>/dev/null)
EOT
       _NVRAM_UpdateCustomBackupConfig_ SAVED "$theBackupFile"
       _NVRAM_UpdateCustomBackupConfig_ RESTD "$theBackupFile"
   fi
   return 0
}

#------------------------------------------------------------------#
_CheckForMaxBackupFiles_()
{
   if ! _CheckForBackupFiles_ "$@" || \
      [ "$theFileCount" -le "$customMaxNumBackupFiles" ]
   then return 0 ; fi

   local highWaterMark

   if [ "$customMaxNumBackupFiles" -ge "$NVRAMdefMaxNumBackupFiles" ]
   then highWaterMark="$customMaxNumBackupFiles"
   else highWaterMark="$((customMaxNumBackupFiles + theHighWaterMarkThreshold))"
   fi

   if [ "$highWaterMark" -gt "$NVRAMtheMaxNumBackupFiles" ]
   then highWaterMark="$NVRAMtheMaxNumBackupFiles" ; fi

   if [ $# -gt 0 ] && [ "$1" = "true" ] && \
      [ "$theFileCount" -gt "$highWaterMark" ]
   then   ## Remove the OLDEST backup file ##
       while IFS="$(printf '\n\t')" read -r theFILE
       do
           _remf_ "$theFILE"
           theFileCount="$((theFileCount - 1))"
           break
       done <<EOT
$(_list2_ -1tr "$nvramBackupFilesMatch" 2>/dev/null)
EOT
       if [ "$theFileCount" -le "$customMaxNumBackupFiles" ]
       then return 0 ; fi
   fi
   ! "$isInteractive" && return 1

   printf "\n\n${YLWct}**WARNING**${NOct}\n"
   printf "The number of backup files [${REDct}${theFileCount}${NOct}] exceeds the maximum [${GRNct}${customMaxNumBackupFiles}${NOct}].\n"
   printf "It's highly recommended that you either delete old backup files,\n"
   printf "or move them from the current directory to a different location.\n"
   _WaitForEnterKey_
   return 1
}

#------------------------------------------------------------------#
_SaveAllVarsToBackup_()
{
   local retCode
   _NVRAM_UpdateCustomBackupConfig_ SAVED WAIT

   theFilePath="${nvramVarsUserBackupFPath}_$(date +"$savedFileDateTimeStr").$customBackupFileExt"
   if ! tar -czf "$theFilePath" -C "$theTEMPdir" "./$NVRAM_TempDIRname"
   then
       retCode=1
       _NVRAM_UpdateCustomBackupConfig_ SAVED NONE STATUSupdate
       _PrintError_ "Could NOT save NVRAM variables."
   else
       retCode=0
       chmod 664 "$theFilePath"
       _NVRAM_UpdateCustomBackupConfig_ SAVED "$theFilePath" STATUSupdate
       _PrintMsg0_ "\nNVRAM variables were successfully saved in:\n[${GRNct}${theFilePath}${NOct}]\n"
   fi

   _NVRAM_CleanupTempFiles_ -ALL
   _CheckForMaxBackupFiles_ true
   return "$retCode"
}

#------------------------------------------------------------------#
_NVRAM_GetKeyNamesFromRegExp_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   if echo "$1" | grep -qE "^\*|^\.\*"
   then
       _PrintError_ "NVRAM variable key names Regular Expression \"${InvREDct}${1}${NOct}\" is INVALID."
       return 1
   fi
   if ! grep -qE "^${1}=" "$NVRAM_TempShowVarFle"
   then
       _PrintWarning_ "NVRAM variable key names NOT FOUND using \"${InvBYLWct}${1}${NOct}\" Regular Expression."
       return 1
   fi
   local theKeyNameStr  lastKeyNameStr="X"

   while read -r theVarKeyEntry
   do
       theKeyNameStr="$(echo "$theVarKeyEntry" | awk -F '=' '{print $1}')"
       if [ -z "$theKeyNameStr" ] || ! _NVRAM_VarSetKeyInfo_ "$theKeyNameStr"
       then continue
       fi
       if _NVRAM_VarSaveKeyValue_ && [ "$theKeyNameStr" != "$lastKeyNameStr" ]
       then nvramVarOKCount="$((nvramVarOKCount + 1))"
       fi
       lastKeyNameStr="$theKeyNameStr"
   done <<EOT
$(grep -E "^${1}=" "$NVRAM_TempShowVarFle" | sort -d -t '=' -k 1)
EOT
}

#------------------------------------------------------------------#
_SaveVarsFromUserList_()
{
   if [ ! -s "$nvramVarsListFilePath" ]
   then
       _PrintError_ "NVRAM variable list file [${InvREDct} ${nvramVarsListFilePath} ${NOct}] is EMPTY or NOT FOUND."
       _WaitForEnterKey_
       return 1
   fi

   local strnKeyNamesOnlyTag="[Key Names]"
   local grepKeyNamesOnlyTag="\[Key Names\]"
   local strnKeyNamesRegExTag="[Key Names: RegEx]"
   local grepKeyNamesRegExTag="\[Key Names: RegEx\]"

   if ! grep -qE "^(${grepKeyNamesOnlyTag}|${grepKeyNamesRegExTag})$" "$nvramVarsListFilePath"
   then
       _PrintError_ "NVRAM variable list file [${InvREDct} ${nvramVarsListFilePath} ${NOct}] does NOT include the required tags."
       _PrintMsg0_ "\nRequired tags: ${GRNct}${strnKeyNamesOnlyTag}${NOct} and ${GRNct}${strnKeyNamesRegExTag}${NOct}\n"
       _WaitForEnterKey_
       return 1
   fi

   local inputLineNumStr  inputListCount  nvramVarOKCount  nvramKeyNameStr
   local nvramKeyNameMode=false  nvramKeyRegExpMode=false  retCode=1

   _PrintMsg0_ "\nGetting list of NVRAM variable key names from:\n[${GRNct}${nvramVarsListFilePath}${NOct}]"
   _PrintMsg0_ "\nPlease wait...\n"
   _PrintMsg0_ "\n${Line0SEP}\n"

   ! "$isVerbose" && _PrintMsg0_ "Start backup process.\n"

   _NVRAM_CleanupTempFiles_ -ALL

   if [ ! -d "$NVRAM_TempDIRpath" ]
   then mkdir -m 755 "$NVRAM_TempDIRpath" 2>/dev/null ; fi

   # Create temporary file showing current NVRAM variables #
   nvram show 2>/dev/null | grep -vE "^$NVRAM_TempShowFilter" | sort -d -t '=' -k 1 > "$NVRAM_TempShowVarFle"

   inputListCount=0
   nvramVarOKCount=0

   while read -r theINPUTstr
   do
      if [ -z "$theINPUTstr" ] || echo "$theINPUTstr" | grep -qE "^#"
      then continue ; fi

      if echo "$theINPUTstr" | grep -qE "^${grepKeyNamesOnlyTag}$"
      then
          nvramKeyNameMode=true
          nvramKeyRegExpMode=false
          continue
      fi
      if echo "$theINPUTstr" | grep -qE "^${grepKeyNamesRegExTag}$"
      then
          nvramKeyNameMode=false
          nvramKeyRegExpMode=true
          continue
      fi

      inputListCount="$((inputListCount + 1))"
      inputLineNumStr="$(printf "%02d" "$inputListCount")"
      _PrintMsg1_ "\nEntry #${inputLineNumStr}: \"${GRNct}${theINPUTstr}${NOct}\"\n"

      nvramKeyNameStr="$(echo "$theINPUTstr" | awk -F ' ' '{print $1}')"
      if "$nvramKeyNameMode"
      then
          if ! _NVRAM_VarSetKeyInfo_ "$nvramKeyNameStr"
          then continue
          fi
          if _NVRAM_VarSaveKeyValue_
          then nvramVarOKCount="$((nvramVarOKCount + 1))"
          fi
      #
      elif "$nvramKeyRegExpMode"
      then
          _NVRAM_GetKeyNamesFromRegExp_ "$nvramKeyNameStr"
      fi
   done < "$nvramVarsListFilePath"

   ! "$isVerbose" && _PrintMsg0_ "\n"

   # Delete temporary file showing current NVRAM variables #
   rm -f "$NVRAM_TempShowVarFle"

   if [ "$nvramVarOKCount" -gt 0 ]
   then
       _SaveAllVarsToBackup_
       retCode="$?"
   fi
   if [ "$inputListCount" -gt 0 ]
   then _PrintMsg0_ "${Line0SEP}\n"
   fi

   _PrintMsg0_ "Number of NVRAM variable key entries: [$inputListCount]\n"
   _PrintMsg0_ "Number of NVRAM variables backed up: [$nvramVarOKCount]\n"

   _WaitForEnterKey_
   return "$retCode"
}

#------------------------------------------------------------------#
_GetFileSelectionIndex_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   local selectStr  promptStr  numRegExp  indexNum  indexList
   local multiIndexListOK  theAllStr="${GRNct}all${NOct}"

   if [ "$1" -eq 1 ]
   then selectStr="${GRNct}1${NOct}"
   else selectStr="${GRNct}1${NOct}-${GRNct}${1}${NOct}"
   fi

   if [ $# -lt 2 ] || [ "$2" != "-MULTIOK" ]
   then
       multiIndexListOK=false
       promptStr="[${theExitStr}]\nEnter selection:[${selectStr}]?"
   else
       multiIndexListOK=true
       promptStr="[${theExitStr}]\nEnter selection:[${selectStr} | ${theAllStr}]?"
   fi
   fileIndex=0  multiIndex=false
   numRegExp="([1-9]|[1-9][0-9])"

   while true
   do
       printf "${promptStr}  " ; read -r userInput

       if [ -z "$userInput" ] || \
          echo "$userInput" | grep -qE "^(e|exit|Exit)$"
       then fileIndex="NONE" ; break ; fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^(all|All)$"
       then fileIndex="ALL" ; break ; fi

       if echo "$userInput" | grep -qE "^${numRegExp}$" && \
          [ "$userInput" -gt 0 ] && [ "$userInput" -le "$1" ]
       then fileIndex="$userInput" ; break ; fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^${numRegExp}\-${numRegExp}[ ]*$"
       then ## Index Range ##
           index1st="$(echo "$userInput" | awk -F '-' '{print $1}')"
           indexMax="$(echo "$userInput" | awk -F '-' '{print $2}')"
           if [ "$index1st" -lt "$indexMax" ]  && \
              [ "$index1st" -gt 0 ] && [ "$index1st" -le "$1" ] && \
              [ "$indexMax" -gt 0 ] && [ "$indexMax" -le "$1" ]
           then
               indexNum="$index1st"
               indexList="$indexNum"
               while [ "$indexNum" -lt "$indexMax" ]
               do
                   indexNum="$((indexNum+1))"
                   indexList="${indexList},${indexNum}"
               done
               userInput="$indexList"
           fi
       fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^${numRegExp}(,[ ]*${numRegExp}[ ]*)+$"
       then ## Index List ##
           indecesOK=true
           indexList="$(echo "$userInput" | sed 's/ //g' | sed 's/,/ /g')"
           for theIndex in $indexList
           do
              if [ "$theIndex" -eq 0 ] || [ "$theIndex" -gt "$1" ]
              then indecesOK=false ; break ; fi
           done
           "$indecesOK" && fileIndex="$indexList" && multiIndex=true && break
       fi

       printf "${REDct}INVALID selection.${NOct}\n\n"
   done
}

#------------------------------------------------------------------#
_GetFileSelection_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   if [ $# -lt 2 ] || [ "$2" != "-MULTIOK" ]
   then indexType="" ; else indexType="$2" ; fi

   theFilePath=""  theFileName=""  fileTemp=""
   fileCount=0  fileIndex=0  multiIndex=false
   printf "\n${1}\n[Directory: ${GRNct}${nvramVarsUserBackupDir}${NOct}]\n\n"

   while IFS="$(printf '\n\t')" read -r backupFilePath
   do
       fileCount=$((fileCount + 1))
       fileVar="file_${fileCount}_Name"
       eval file_${fileCount}_Name="${backupFilePath##*/}"
       printf "${GRNct}%3d${NOct}. " "$fileCount"
       eval echo "\$${fileVar}"
   done <<EOT
$(_list2_ -1t "$nvramBackupFilesMatch" 2>/dev/null)
EOT

   echo
   _GetFileSelectionIndex_ "$fileCount" "$indexType"

   if [ "$fileIndex" = "ALL" ] || [ "$fileIndex" = "NONE" ]
   then theFilePath="$fileIndex" ; return 0 ; fi

   if [ "$indexType" = "-MULTIOK" ] && "$multiIndex"
   then
       for index in $fileIndex
       do
           fileVar="file_${index}_Name"
           eval fileTemp="\$${fileVar}"
           if [ -z "$theFilePath" ]
           then theFilePath="${nvramVarsUserBackupDir}/$fileTemp"
           else theFilePath="${theFilePath}|${nvramVarsUserBackupDir}/$fileTemp"
           fi
       done
   else
       fileVar="file_${fileIndex}_Name"
       eval theFileName="\$${fileVar}"
       theFilePath="${nvramVarsUserBackupDir}/$theFileName"
   fi
   return 0
}

#------------------------------------------------------------------#
_NVRAM_VarRestoreKeysFromBackup_()
{
   local tempFileCount
   tempFileCount="$(_list2_ -1 "$NVRAM_TempFilesMatch" 2>/dev/null | wc -l)"
   if [ ! -d "$NVRAM_TempDIRpath" ] || [ "$tempFileCount" -eq 0 ]
   then
       _PrintError_ "Backup file(s) in [${InvREDct} ${NVRAM_TempDIRpath} ${NOct}] NOT FOUND."
       return 1
   fi
   local retCode=1  tempFileName  theKeyNameStr  NVRAM_VarFoundOK

   nvramVarCount=0
   nvramVarOKCount=0
   NVRAM_VarFoundOK=false

   while IFS="$(printf '\n\t')" read -r backupFilePath
   do
      tempFileName="${backupFilePath##*/}"
      tempFileName="${tempFileName%.*}"
      theKeyNameStr="${tempFileName#*_}"
      if [ -z "$theKeyNameStr" ] || ! _NVRAM_VarSetKeyInfo_ "$theKeyNameStr"
      then continue ; fi

      nvramVarCount="$((nvramVarCount + 1))"
      if _NVRAM_VarRestoreKeyValue_
      then nvramVarOKCount="$((nvramVarOKCount + 1))" ; fi
   done <<EOT
$(_list2_ -1 "$NVRAM_TempFilesMatch" 2>/dev/null)
EOT

   if [ "$nvramVarOKCount" -gt 0 ] || "$NVRAM_VarFoundOK"
   then retCode=0 ; fi
   return "$retCode"
}

#------------------------------------------------------------------#
_RestoreVarsFromBackup_()
{
   local retCode  nvramVarCount=0  nvramVarOKCount=0
   theFilePath=""  theFileCount=0

   if ! _CheckForBackupFiles_
   then
       _NVRAM_UpdateCustomBackupConfig_ RESTD NONE STATUSupdate
       _PrintError_ "Backup file(s) [${InvREDct} ${nvramBackupFilesMatch} ${NOct}] NOT FOUND."
       return 1
   fi
   _NVRAM_UpdateCustomBackupConfig_ RESTD WAIT

   if [ $# -gt 0 ] && [ "$1" = "true" ]
   then  ## Restore from the MOST recent backup file ##
       while IFS="$(printf '\n\t')" read -r theFILE
       do theFilePath="$theFILE" ; break
       done <<EOT
$(_list2_ -1t "$nvramBackupFilesMatch" 2>/dev/null)
EOT
   else
       _GetFileSelection_ "Select a backup file to restore NVRAM variables from:"
   fi

   if [ "$theFilePath" = "NONE" ] || [ ! -f "$theFilePath" ]
   then
       _NVRAM_UpdateCustomBackupConfig_ RESTD NONE STATUSupdate
       return 1
   fi

   _PrintMsg0_ "\nRestoring NVRAM variables from:\n[${GRNct}$theFilePath${NOct}]\n"
   if ! _WaitForResponse_ "\nPlease confirm selection"
   then
       _PrintMsg0_ "NVRAM variables ${REDct}NOT${NOct} restored.\n"
       _WaitForEnterKey_
       return 99
   fi
   _PrintMsg0_ "\n${Line0SEP}\n"

   ! "$isVerbose" && _PrintMsg0_ "Start restore process.\n"

   _NVRAM_CleanupTempFiles_ -ALL

   if ! tar -xzf "$theFilePath" -C "$theTEMPdir"
   then
       retCode=99
       _NVRAM_UpdateCustomBackupConfig_ RESTD NONE STATUSupdate
       _PrintError_ "Could NOT restore NVRAM variables."
   else
       retCode=0
       if _NVRAM_VarRestoreKeysFromBackup_
       then
           _NVRAM_UpdateCustomBackupConfig_ RESTD "$theFilePath" STATUSupdate
       fi
       if [ "$nvramVarOKCount" -gt 0 ]
       then
           _PrintMsg0_ "NVRAM variables were restored ${GRNct}successfully${NOct}.\n"
       fi
   fi

   _NVRAM_CleanupTempFiles_ -ALL

   ! "$isVerbose" && _PrintMsg0_ "\n"

   _PrintMsg0_ "${Line0SEP}\n"
   _PrintMsg0_ "Number of NVRAM variables backed up: [$nvramVarCount]\n"
   _PrintMsg0_ "Number of NVRAM variables restored: [$nvramVarOKCount]\n"

   _WaitForEnterKey_
   return "$retCode"
}

#------------------------------------------------------------------#
_ListContentsOfBackupFile()
{
   local retCode
   theFilePath=""  theFileCount=0

   if ! _CheckForBackupFiles_
   then
       _PrintError_ "Backup file(s) [${InvREDct} ${nvramBackupFilesMatch} ${NOct}] NOT FOUND."
       return 1
   fi
   _GetFileSelection_ "Select a backup file to list contents of:"

   if [ "$theFilePath" = "NONE" ] || [ ! -f "$theFilePath" ]
   then return 1 ; fi

   printf "\nListing contents of backup file:\n[${GRNct}${theFilePath}${NOct}]\n\n"
   if tar -tzf "$theFilePath" -C "$theTEMPdir" | sort -d
   then
       retCode=0
       printf "\nContents were listed ${GRNct}successfully${NOct}.\n"
   else
       retCode=99
       _PrintError_ "Could NOT list contents."
   fi
   _WaitForEnterKey_
   return "$retCode"
}

#------------------------------------------------------------------#
_DeleteSavedBackupFile_()
{
   local retCode
   theFilePath=""  fileIndex=0  multiIndex=false

   if ! _CheckForBackupFiles_
   then
       _PrintError_ "Backup file(s) [${InvREDct} ${nvramBackupFilesMatch} ${NOct}] NOT FOUND."
       return 1
   fi
   _GetFileSelection_ "Select a backup file to delete:" -MULTIOK

   if [ "$theFilePath" = "NONE" ] ; then return 1 ; fi
   if [ "$theFilePath" != "ALL" ] && ! "$multiIndex" && [ ! -f "$theFilePath" ]
   then return 1 ; fi

   if [ "$theFilePath" != "ALL" ]
   then
       fileToDelete="$theFilePath"
       delMsg="Deleting backup file(s):"
   else
       fileToDelete="$nvramBackupFilesMatch"
       delMsg="Deleting ${REDct}ALL${NOct} backup file(s):"
   fi
   if ! "$multiIndex"
   then theFileList="$fileToDelete"
   else
       theFileList="$(echo "$fileToDelete" | sed 's/|/\n/g')"
       fileToDelete="$theFileList"
   fi

   printf "\n${delMsg}\n${GRNct}${theFileList}${NOct}\n"
   if ! _WaitForResponse_ "Please confirm deletion"
   then
       printf "File(s) ${REDct}NOT${NOct} deleted.\n"
       _WaitForEnterKey_
       return 99
   fi

   fileDelOK=true
   local prevIFS="$IFS"
   IFS="$(printf '\n\t')"
   for thisFile in $fileToDelete
   do if ! _remf_ "$thisFile" ; then fileDelOK=false ; fi ; done
   IFS="$prevIFS"

   if "$fileDelOK"
   then
       retCode=0
       printf "File deletion completed ${GRNct}successfully${NOct}.\n"
   else
       retCode=99
       _PrintError_ "Could NOT delete file(s)."
   fi
   _WaitForEnterKey_
   return "$retCode"
}

#------------------------------------------------------------------#
_SetMaxNumberOfBackupFiles_()
{
   local numRegExp="([1-9]|[1-9][0-9])"
   local newMaxNumOfBackups="DEFAULT"

   echo
   while true
   do
       printf "Enter the maximum number of backups of NVRAM variables to keep.\n"
       printf "[${theExitStr}]\n"
       printf "[Min=${GRNct}${NVRAMtheMinNumBackupFiles}${NOct},"
       printf " Max=${GRNct}${NVRAMtheMaxNumBackupFiles}${NOct}] |"
       printf " [Current Value: ${GRNct}${customMaxNumBackupFiles}${NOct}]:  "
       read -r userInput

       if [ -z "$userInput" ] || echo "$userInput" | grep -qE "^(e|exit|Exit)$"
       then newMaxNumOfBackups="DEFAULT" ; break ; fi

       if echo "$userInput" | grep -qE "^${numRegExp}$" && \
          [ "$userInput" -ge "$NVRAMtheMinNumBackupFiles" ] && \
          [ "$userInput" -le "$NVRAMtheMaxNumBackupFiles" ]
       then newMaxNumOfBackups="$userInput" ; break ; fi

       printf "${REDct}INVALID input.${NOct}\n\n"
   done

   if [ "$newMaxNumOfBackups" != "DEFAULT" ]
   then
       customMaxNumBackupFiles="$newMaxNumOfBackups"
       _NVRAM_UpdateCustomBackupConfig_ SAVED_MAX "$customMaxNumBackupFiles"
   fi
   return 0
}

#------------------------------------------------------------------#
_SetVarsListFilePath_()
{
   local newVarsListFilePath=""  colorCode  clearCode

   echo
   while true
   do
      if [ -s "$nvramVarsListFilePath" ]
      then
          colorCode=" $GRNct"
          clearCode="$NOct"
      else
          colorCode="$InvREDct "
          clearCode=" $NOct"
      fi

      printf "Enter the full path of the file containing the list of NVRAM variables to back up.\n"
      printf "[${theExitStr}]\n[CURRENT:${colorCode}${nvramVarsListFilePath}${clearCode}]:  "
      read -r userInput

      if echo "$userInput" | grep -qE "^(e|exit|Exit)$" || \
         { [ -z "$userInput" ] && [ -s "$nvramVarsListFilePath" ] ; }
      then
          newVarsListFilePath="$nvramVarsListFilePath"
          break
      fi

      if [ -z "$userInput" ] && [ ! -s "$nvramVarsListFilePath" ]
      then
          _PrintError_ "The file [${InvREDct} ${nvramVarsListFilePath} ${NOct}] does NOT exist.\n"
          continue
      fi

      if echo "$userInput" | grep -q '/$'
      then userInput="${userInput%/*}"
      fi

      if echo "$userInput" | grep -q '//'   || \
         echo "$userInput" | grep -q '/$'   || \
         ! echo "$userInput" | grep -q '^/' || \
         [ "${#userInput}" -lt 4 ]          || \
         [ "$(echo "$userInput" | awk -F '/' '{print NF-1}')" -lt 2 ]
      then
          printf "${REDct}INVALID input.${NOct}\n\n"
          continue
      fi

      if [ -s "$userInput" ]
      then newVarsListFilePath="$userInput" ; break ; fi

      _PrintError_ "The file [${InvREDct} ${userInput} ${NOct}] does NOT exist.\n"
   done

   if [ ! -s "$newVarsListFilePath" ]
   then
       _PrintError_ "File [${InvREDct} ${newVarsListFilePath} ${NOct}] NOT FOUND."
       _WaitForEnterKey_ ; return 1
   fi
   _NVRAM_UpdateCustomBackupConfig_ LIST_FILE "$newVarsListFilePath"
   return 0
}

#------------------------------------------------------------------#
_SetCustomBackupDirectory_()
{
   local newBackupDirPath="DEFAULT"

   echo
   while true
   do
      printf "Enter the directory path where the backups subdirectory [${GRNct}${NVRAM_VarsBackupDIRname}${NOct}] will be stored.\n"
      printf "[${theExitStr}]\n[CURRENT: ${GRNct}${nvramVarsUserBackupDir%/*}${NOct}]:  "
      read -r userInput

      if [ -z "$userInput" ] || \
         echo "$userInput" | grep -qE "^(e|exit|Exit)$"
      then newBackupDirPath="DEFAULT" ; break ; fi

      if echo "$userInput" | grep -q '/$'
      then userInput="${userInput%/*}" ; fi

      if echo "$userInput" | grep -q '//'   || \
         echo "$userInput" | grep -q '/$'   || \
         ! echo "$userInput" | grep -q '^/' || \
         [ "${#userInput}" -lt 4 ]          || \
         [ "$(echo "$userInput" | awk -F '/' '{print NF-1}')" -lt 2 ]
      then
          printf "${REDct}INVALID input.${NOct}\n\n"
          continue
      fi

      if [ -d "$userInput" ]
      then newBackupDirPath="$userInput" ; break ; fi

      rootDir="${userInput%/*}"
      if [ ! -d "$rootDir" ]
      then
          _PrintError_ "Root directory path [${InvREDct} ${rootDir} ${NOct}] does NOT exist.\n"
          printf "${REDct}INVALID input.${NOct}\n\n"
          continue
      fi

      printf "The directory path [${InvREDct} ${userInput} ${NOct}] does NOT exist.\n\n"
      if ! _WaitForResponse_ "Do you want to create it now"
      then
          printf "Directory was ${REDct}NOT${NOct} created.\n\n"
      else
          mkdir -m 755 "$userInput" 2>/dev/null
          if [ -d "$userInput" ]
          then newBackupDirPath="$userInput" ; break
          else _PrintError_ "Could NOT create directory [${InvREDct} ${userInput} ${NOct}].\n"
          fi
      fi
   done

   if [ "$newBackupDirPath" = "DEFAULT" ] && \
      [ "$nvramVarsUserBackupDir" != "$nvramVarsPrefBackupDir" ]
   then newBackupDirPath="$nvramVarsUserBackupDir" ; fi

   if [ "$newBackupDirPath" != "DEFAULT" ] && [ -d "$newBackupDirPath" ]
   then
       if  [ "${newBackupDirPath##*/}" != "$NVRAM_VarsBackupDIRname" ]
       then newBackupDirPath="${newBackupDirPath}/$NVRAM_VarsBackupDIRname" ; fi
       mkdir -m 755 "$newBackupDirPath" 2>/dev/null
       if [ ! -d "$newBackupDirPath" ]
       then
           _PrintError_ "Could NOT create directory [${REDct}${newBackupDirPath}${NOct}]."
           _WaitForEnterKey_ ; return 1
       fi
       if _CheckForBackupFiles_  && [ "$newBackupDirPath" != "$nvramVarsUserBackupDir" ]
       then
           printf "\nMoving existing backup files to directory:\n[${GRNct}$newBackupDirPath${NOct}]\n"
           if _movef_ "$nvramBackupFilesMatch" "$newBackupDirPath" && \
              ! _CheckForBackupFiles_
           then rmdir "$nvramVarsUserBackupDir" 2>/dev/null ; fi
       fi
       _NVRAM_UpdateCustomBackupConfig_ SAVED_DIR "$newBackupDirPath"
       _NVRAM_UpdateCustomBackupConfig_ PREFS_DIR "$newBackupDirPath"
       _CheckForBackupFiles_ true
   fi
   return 0
}

#------------------------------------------------------------------#
_GetCenterPadNums_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 0
   fi
   local  fullStrLen  stringLen0  padStrLen0

   stringLen0="${#1}"
   padStrLen1="$((($2 - stringLen0)/2))"
   padStrLen2="$padStrLen1"
   fullStrLen="$((padStrLen1 + stringLen0 + padStrLen2))"

   if [ "$fullStrLen" -lt "$2" ]
   then padStrLen2="$((padStrLen2 + 1))"
   elif [ "$fullStrLen" -gt "$2" ]
   then padStrLen1="$((padStrLen1 - 1))"
   fi
}

#------------------------------------------------------------------#
_ShowBackupRestoreMenuOptions_()
{
   SEPstr1="----------------------------------------------------------------"
   SEPstr2="########################################################"
   _CheckForBackupFiles_

   local fullSpaceLen=50  padStrLen1  padStrLen2  colorCode  clearCode
   _GetCenterPadNums_ "$version_TAG" "$fullSpaceLen"

   printf "\n${SEPstr2}\n"
   printf "##    Save and Restore Utility for NVRAM Variables    ##\n"
   printf "##%*s[${GRNct}${version_TAG}${NOct}]%*s##" "$padStrLen1" '' "$padStrLen2" ''
   printf "\n${SEPstr2}\n"

   printf "\n ${GRNct}${MaxBckupsOpt}${NOct}.  Maximum number of backup files to keep."
   printf "\n      [Current Max: ${GRNct}${customMaxNumBackupFiles}${NOct}]\n"

   if [ -d "$nvramVarsUserBackupDir" ]
   then
       colorCode=" $GRNct"
       clearCode="$NOct"
   else
       colorCode="$InvREDct "
       clearCode=" $NOct"
   fi
   printf "\n ${GRNct}${BackupDirOpt}${NOct}.  Directory path where backup files are stored."
   printf "\n      [Current Path:${colorCode}${nvramVarsUserBackupDir}${clearCode}]\n"

   if [ -s "$nvramVarsListFilePath" ]
   then
       colorCode=" $GRNct"
       clearCode="$NOct"
   else
       colorCode="$InvREDct "
       clearCode=" $NOct"
   fi
   printf "\n ${GRNct}${ListFileOpt}${NOct}.  File with a list of NVRAM variable key names to back up."
   printf "\n      [Current File:${colorCode}${nvramVarsListFilePath}${clearCode}]\n"

   if [ -d "$nvramVarsUserBackupDir" ] && [ -s "$nvramVarsListFilePath" ]
   then
       printf "\n ${GRNct}${menuBckpOpt}${NOct}.  Back up NVRAM variables listed in the file."
       printf "\n      [Current File: ${GRNct}${nvramVarsListFilePath}${NOct}]\n"
   fi

   if "$backupsFound"
   then
       printf "\n ${GRNct}${menuRestOpt}${NOct}.  Restore a backup of NVRAM variables.\n"
       printf "\n ${GRNct}${menuDeltOpt}${NOct}.  Delete a previously saved backup file.\n"
       printf "\n ${GRNct}${menuListOpt}${NOct}.  List contents of a previously saved backup file.\n"
   fi

   printf "\n  ${GRNct}e${NOct}.  Exit.\n"
   printf "\n${SEPstr1}\n"
   return 0
}

#------------------------------------------------------------------#
_MenuSelectionHandler_()
{
   local exitMenu=false  retCode
   local theExitStr="${GRNct}e${NOct}=Exit to main menu"

   until ! _ShowBackupRestoreMenuOptions_
   do
      while true
      do
          printf "Choose an option:  " ; read -r userOption
          if [ -z "$userOption" ] ; then echo ; continue ; fi

          if echo "$userOption" | grep -qE "^(e|exit|Exit)$"
          then exitMenu=true ; break ; fi

          if [ "$userOption" = "$MaxBckupsOpt" ]
          then _SetMaxNumberOfBackupFiles_; break ; fi

          if [ "$userOption" = "$BackupDirOpt" ]
          then _SetCustomBackupDirectory_ ; break ; fi

          if [ "$userOption" = "$ListFileOpt" ]
          then _SetVarsListFilePath_ ; break ; fi

          if [ "$userOption" = "$menuBckpOpt" ] && \
             [ -d "$nvramVarsUserBackupDir" ]   && \
             [ -s "$nvramVarsListFilePath" ]
          then _SaveVarsFromUserList_ ; break ; fi

          if [ "$userOption" = "$menuRestOpt" ] && "$backupsFound"
          then
              while true
              do
                 _RestoreVarsFromBackup_ ; retCode="$?"
                 if [ "$retCode" -eq 0 ] || [ "$retCode" -eq 99 ]
                 then continue ; else break ; fi
              done
              break
          fi

          if [ "$userOption" = "$menuDeltOpt" ] && "$backupsFound"
          then
              while true
              do
                 _DeleteSavedBackupFile_ ; retCode="$?"
                 if [ "$retCode" -eq 99 ]
                 then continue ; else break ; fi
              done
              break
          fi

          if [ "$userOption" = "$menuListOpt" ] && "$backupsFound"
          then
              while true
              do
                 _ListContentsOfBackupFile ; retCode="$?"
                 if [ "$retCode" -eq 0 ] || [ "$retCode" -eq 99 ]
                 then continue ; else break ; fi
              done
              break
          fi

          printf "${REDct}INVALID option.${NOct}\n\n"
      done
      "$exitMenu" && break
   done
}

#------------------------------------------------------------------#
if [ ! -d "$theJFFSdir" ]
then
    _PrintError_ "Directory [$theJFFSdir] *NOT* FOUND."
    exit 1
fi

if [ ! -d "$theTEMPdir" ]
then
    _PrintError_ "Directory [$theTEMPdir] *NOT* FOUND."
    exit 1
fi

if [ $# -gt 0 ] && [ "$1" != "-menu" ]
then
    if [ $# -gt 1 ] && [ "$2" = "-quiet" ]
    then isVerbose=false ; fi
fi

if ! _CheckCustomBackupConfig_
then
    if [ $# -eq 0 ] || \
       echo "$1" | grep -qE "^(-backup|-restore)$"
    then  _ShowUsage_
    fi
fi

if [ $# -gt 0 ]
then
   if [ "$1" = "-backup" ] || \
      [ "$1" = "-restore" ]
   then
       _CheckForBackupFiles_

       if [ "$1" = "-backup" ]
       then _SaveVarsFromUserList_
       elif [ "$1" = "-restore" ]
       then _RestoreVarsFromBackup_ true
       fi
   elif [ "$1" = "-menu" ]
   then
       _CheckForMaxBackupFiles_
       _MenuSelectionHandler_
       _CheckForMaxBackupFiles_ true
   else
        _PrintError_ "UNKNOWN Parameter [${REDct}${1}${NOct}]"
       _ShowUsage_
   fi
   _ClearCustomBackupStatus_
fi

exit 0

#EOF#
