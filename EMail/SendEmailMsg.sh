#!/bin/sh
#####################################################################
# SendEmailMsg.sh
#
# CLI script tool to send simple email notifications using
# the existing shared custom email library script:
# "/jffs/addons/shared-libs/CustomEMailFunctions.lib.sh"
#
# IMPORTANT NOTE:
# Variables with the "cem" or "CEM" prefix are reserved for
# the shared custom email library. You can modify the values
# but do *NOT* change the variable names.
#-------------------------------------------------------------------
# Original Author: Martinski W.
# Creation Date: 2026-Feb-19 [Martinski W.]
# Last Modified: 2026-Sep-17 [Martinski W.]
#####################################################################
set -u

readonly SCRIPT_VERSION="0.8.0"
readonly SCRIPT_VERSTAG="26091723"
readonly SCRIPT_TNAME="SendEmailMsg"
readonly SCRIPT_FNAME="${SCRIPT_TNAME}.sh"

# Give FIRST priority to built-in binaries over any other #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

readonly scriptDirPath="$(/usr/bin/dirname "$0")"
readonly scriptFileName="${0##*/}"
readonly scriptFNameTag="${scriptFileName%.*}"

readonly JFFS_ADDONS_DIR="/jffs/addons"
readonly JFFS_SCRIPTS_DIR="/jffs/scripts"

# The shared AMTM Email Configuration file with user-defined settings #
readonly AMTM_Mail_Dir_Path="${JFFS_ADDONS_DIR}/amtm/mail"
readonly AMTM_Mail_Conf_File="${AMTM_Mail_Dir_Path}/email.conf"
readonly AMTM_Mail_Pswd_File="${AMTM_Mail_Dir_Path}/emailpw.enc"
isEmailConfigEnabledInAMTM=false

## The shared Custom Email Library Script to send email notifications ##
readonly ADDONS_SHARED_LIBS_DIR_PATH="${JFFS_ADDONS_DIR}/shared-libs"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FNAME="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FPATH="${ADDONS_SHARED_LIBS_DIR_PATH}/$CUSTOM_EMAIL_LIB_SCRIPT_FNAME"

readonly SCRIPT_INSTALL_PATH="${JFFS_ADDONS_DIR}/${SCRIPT_TNAME}.d"
readonly SCRIPT_CONFIG_FPATH="${SCRIPT_INSTALL_PATH}/${SCRIPT_TNAME}.conf"
readonly theScriptFPath="${SCRIPT_INSTALL_PATH}/$SCRIPT_FNAME"
readonly theScriptSLink="${JFFS_SCRIPTS_DIR}/$SCRIPT_TNAME"

readonly SCRIPT_URL_BASE2="https://raw.githubusercontent.com/MartinSkyW/CustomMiscUtils"
readonly SCRIPT_URL_BASE1="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils"

SCRIPT_GH_BRANCH="develop"   ##**SET to "master" for RELEASE**##
SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/${SCRIPT_GH_BRANCH}/EMail"
SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/${SCRIPT_GH_BRANCH}/EMail"

readonly TMP_DIR="/tmp"
readonly TEMP_DIR="/tmp/var/tmp"
readonly curlHTTPstatusStr="HTTP_Status_Code"
readonly curlTmpLogFPath="${TEMP_DIR}/tmpSendCurl_${scriptFNameTag}_$$.TMP.LOG"
readonly curlErrLogFPath="${TEMP_DIR}/tmpSendCurl_${scriptFNameTag}_$$.ERR.LOG"
readonly emailBodyCFPath="${TEMP_DIR}/tmpEMailBody_${scriptFNameTag}.$$.TMP"

readonly emailUpdateMutexFLock_FD=783
readonly emailUpdateMutexFLock_FN="${TEMP_DIR}/CEMailUpdateCheck.FLOCK"
emailUpdateMutexFLock_OK=false  #To check if/when we own the Lock#

readonly CLRct="\e[0m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly YLWct="\e[1;33m"
readonly MGNTct="\e[1;35m"
readonly CYANct="\e[1;36m"

readonly pLogALERT=1
readonly pLogCRITC=2
readonly pLogERROR=3
readonly pLogWARNG=4
readonly pLogNOTIC=5
readonly pLogINFOR=6
readonly logTagStr="${scriptFNameTag}_[$$]"

if [ -t 0 ] && ! tty | grep -qwi 'NOT'
then readonly isInteractive=true
else readonly isInteractive=false
fi

if [ "$SCRIPT_GH_BRANCH" = "master" ]
then
    readonly versionStrNums="${SCRIPT_VERSION} ${CLRct}[${GRNct}${SCRIPT_VERSTAG}${CLRct}]"
    readonly versionStrInfo="${GRNct}${SCRIPT_VERSION}${CLRct} [${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${GRNct}master${CLRct}]"
else
    readonly versionStrNums="${SCRIPT_VERSION} ${CLRct}[${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${MGNTct}develop${CLRct}]"
    readonly versionStrInfo="${GRNct}${SCRIPT_VERSION}${CLRct} [${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${MGNTct}develop${CLRct}]"
fi

#OPTIONAL#
emailCCName=""
emailCCEmail=""
emailSenderID=""

#Configuration Defaults#
doShowErrorMsgs=true
cemIsFormatHTML=true
cemIsVerboseMode=true

#-----------------------------------------------------------#
_ShowUsageLong_()
{
   ! "$isInteractive" && return 0
   cat <<EOF1 | xargs -0 echo -e
----------------------------------------------------------------------------
Version: $versionStrInfo
Author: Martinski W.

CLI script utility to send email notifications from the router.
It leverages the shared email library script for the actual email operation,
and uses the AMTM email configuration file as the user-defined email setup.


To get this usage and syntax description:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-help${CLRct}


To display version information:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-version${CLRct}


To install the script and its configuration file:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-install${CLRct}


To uninstall the script and its configuration file:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-uninstall${CLRct}


To check for and install the latest script version update:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-checkupdate${CLRct}


To force installation of the latest script version update:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-forceupdate${CLRct}


To switch to the production/stable version of the script:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-stable${CLRct}


To switch to the development branch version of the script:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-develop${CLRct}


To view the current script configuration file:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-showconf${CLRct}

EOF1

   cat <<EOF2 | xargs -0 echo -e

To test and verify if the email notification setup is working:
[The order of the secondary arguments after the FIRST is important]

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct}

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE" "EMAIL_BODY_TITLE_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" "EMAIL_BODY_TITLE_LINE"

   ${YLWct}--------------${CLRct}
   Example calls:
   ${YLWct}--------------${CLRct}

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct}

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "TEST Email Subject"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "TEST Email Subject" "TESTING My Email Notification"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "TEST Email Subject"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "TEST Email Subject" "TESTING My Email Notification"

EOF2

   cat <<EOF3 | xargs -0 echo -e

To send email notifications [the order of the secondary arguments after the FIRST is important]:

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING" "EMAIL_BODY_TITLE_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE" "EMAIL_BODY_TITLE_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING" "EMAIL_BODY_TITLE_LINE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE" "EMAIL_BODY_TITLE_LINE"


   ${YLWct}----------------------------------------------------------------${CLRct}
   Example calls using a simple one-line email body message string:
   ${YLWct}----------------------------------------------------------------${CLRct}
   
   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "Email Subject Line" "My Simple Email Body Message String"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Email Subject Line" "My Simple Email Body Message String"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Email Subject Line" "My Simple Email Body Message String" "Email Body Title Line"


   ${YLWct}-------------------------------------------------------------------${CLRct}
   Example calls using an email body message file with multiple lines:
   ${YLWct}-------------------------------------------------------------------${CLRct}

   {
     echo "This email was sent for testing purposes only."
     echo "The email body may have multiple lines of text."
     echo "This is the third line of text of the email body."
   } > ${TMP_DIR}/theEmailBody.txt

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "Email Subject Line" ${MGNTct}-File=${CLRct}"${TMP_DIR}/theEmailBody.txt" 

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Email Subject Line" ${MGNTct}-File=${CLRct}"${TMP_DIR}/theEmailBody.txt"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Email Subject Line" ${MGNTct}-File=${CLRct}"${TMP_DIR}/theEmailBody.txt" "Email Body Title Line"

EOF3

   cat <<EOF4 | xargs -0 echo -e

OPTIONAL argument modifiers following the FIRST parameter:

   ${CYANct}-html${CLRct}     Send email in HTML format
   ${CYANct}-ptext${CLRct}    Send email in 'Plain Text' format
   ${CYANct}-quiet${CLRct}    Disable "Verbose Mode" (show errors only)
   ${CYANct}-verbose${CLRct}  Enabled 'Verbose Mode'

   ${YLWct}--------------${CLRct}
   Example calls:
   ${YLWct}--------------${CLRct}

   ${GRNct}$SCRIPT_TNAME ${CYANct}-test -ptext${CLRct}

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send -ptext${CLRct} "Email Subject Line" "Email Body Message String"

   ${GRNct}$SCRIPT_TNAME ${CYANct}-send -ptext -quiet${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Email Subject Line" "Email Body Message String" "Email Body Title Line"


DEFAULT values if not explicitly modified:

   - Email is sent in HTML format
   - Verbose mode is ENABLED
   - The "SenderID" (aka "FROM_NAME") is empty and the value is extracted 
     from the NVRAM 'http_username' key
   - The "Body Title Line" (aka "EMAIL_BODY_TITLE_LINE") is empty


See configuration file ${CYANct}${SCRIPT_CONFIG_FPATH}${CLRct} for global defaults.
A default can be overridden in each command execution by explicitly adding an argument.

For example, if adding the ${CYANct}-ptext${CLRct} argument, the email format will be Plain Text.
When adding the ${MGNTct}-From=${CYANct}"@MyUniqueHandleID"${CLRct} argument, the defined sender ID is used
in the email notification sent by the command invocation.

If you want to change a global default for ALL command executions, modify the value
in the configuration file. Valid characters are only alphanumeric, period, hyphen,
underscore, and at (@) symbols.

${MGNTct}emailSenderID=${CYANct}"@MyUniqueHandleID"${CLRct}
----------------------------------------------------------------------------
EOF4
}

#-----------------------------------------------------------#
_ShowUsageShort_()
{
   ! "$isInteractive" && return 0
   cat <<EOF1 | xargs -0 echo -e
----------------------------------------------------------------------------
Version: $versionStrInfo
Author: Martinski W.

CLI script utility to send email notifications from the router.
It leverages the shared email library script for the actual email operation,
and uses the AMTM email configuration file as the user-defined email setup.

Example Calls:

To get full help and description of all command arguments:
   ${GRNct}$SCRIPT_TNAME ${CYANct}-help${CLRct}

Miscellaneous functions:
   ${GRNct}$SCRIPT_TNAME ${CYANct}-version${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-install${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-uninstall${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-checkupdate${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-forceupdate${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-stable${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-develop${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-showconf${CLRct}

To test and verify if the email notification setup is working:
   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct}
   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE"
   ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE" "EMAIL_BODY_TITLE_LINE"

To send simple email notifications:
   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING"
   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" "EMAIL_BODY_MSG_STRING" "EMAIL_BODY_TITLE_LINE"
   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE"
   ${GRNct}$SCRIPT_TNAME ${CYANct}-send${CLRct} "SUBJECT_LINE" ${MGNTct}-File=${CLRct}"EMAIL_BODY_MSG_FILE" "EMAIL_BODY_TITLE_LINE"
----------------------------------------------------------------------------
EOF1
}

#-----------------------------------------------------------#
_PressAnyKey_()
{
	! "$isInteractive" && return 0
	local promptStr
	if [ $# -gt 0 ] && [ -n "$1" ]
	then promptStr="$1"
	else promptStr="Press ANY key to continue..."
	fi
	printf "\n$promptStr"
	read -n1 -rs anyKEY ; echo
}

#-----------------------------------------------------------#
_PrintMsg_()
{ "$isInteractive" && printf "$1" ; }

#-----------------------------------------------------------#
_LogMsg_()
{
   if [ $# -lt 1 ] || [ -z "$1" ]
   then return 1
   fi
   local logPrioNum

   if [ $# -gt 1 ] && [ -n "$2" ] && \
      echo "$2" | grep -qE '^[1-6]$'
   then logPrioNum="$2"
   else logPrioNum="$pLogNOTIC"
   fi
   if "$isInteractive" && \
      { [ $# -lt 3 ] || [ "$3" != "NOECHO" ] ; }
   then
       if [ "$logPrioNum" -gt "$pLogWARNG" ]
       then printf "${1}\n"
       elif [ "$logPrioNum" -eq "$pLogWARNG" ]
       then printf "${YLWct}${1}${CLRct}\n"
       else printf "${REDct}${1}${CLRct}\n"
       fi
   fi
   logger -t "$logTagStr" -p "$logPrioNum" "$1"
}

#-----------------------------------------------------------#
_ReleaseEmailMutexFLock_()
{
	if [ $# -gt 0 ] && \
	   [ "$1" = "checkLockOK" ] && \
	   [ "$emailUpdateMutexFLock_OK" = "false" ]
	then return 0
	fi
	printf '' > "$emailUpdateMutexFLock_FN"
	flock -u "$emailUpdateMutexFLock_FD" 2>/dev/null
    eval exec "${emailUpdateMutexFLock_FD}>&-"
	emailUpdateMutexFLock_OK=false
}

#---------------------------------------------------------------------#
# This is a mutually exclusive, blocking FLOCK mechanism meant to
# prevent updating the shared email scripts by concurrent processes.
#---------------------------------------------------------------------#
_AcquireEmailMutexFLock_()
{
    local retCode  procInfo  procName  procIDno  procIDof=""

    if [ -s "$emailUpdateMutexFLock_FN" ]
    then
        procInfo="$(head -n1 "$emailUpdateMutexFLock_FN")"
        procName="$(echo "$procInfo" | cut -d'|' -f1)"
        procIDno="$(echo "$procInfo" | cut -d'|' -f2)"
        if [ -n "$procName" ] && [ -n "$procIDno" ]
        then procIDof="$(pidof "$procName")"
        fi
        if [ -z "$procIDof" ] || \
           ! echo "$procIDof" | grep -qow "$procIDno"
        then
            _PrintMsg_ "Stale Lock Found. Resetting Lock file..."
            _ReleaseEmailMutexFLock_
        fi
    fi

    eval exec "${emailUpdateMutexFLock_FD}>$emailUpdateMutexFLock_FN"
    if flock -x "$emailUpdateMutexFLock_FD" 2>/dev/null
    then
        printf "$(basename "$0")|$$\n" > "$emailUpdateMutexFLock_FN"
        retCode=0 ; emailUpdateMutexFLock_OK=true
    else
        procInfo="$(head -n1 "$emailUpdateMutexFLock_FN")"
        if [ -n "$procInfo" ]
        then procInfo="$(echo "$procInfo" | sed 's/|/, PID=/')"
        fi
        _PrintMsg_ "${MGNTct}*WARNING*${CLRct}: Another process [$procInfo] has the Lock."
        retCode=1 ; emailUpdateMutexFLock_OK=false
    fi

    return "$retCode"
}

#-----------------------------------------------------------#
_DOStoUNIX_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
   then return 1 ; fi
   if grep -q "$(printf '\r\n')" "$1" 2>/dev/null
   then dos2unix "$1" ; fi
}

#-----------------------------------------------------------#
_CheckEmailConfigFileFromAMTM_()
{
   local msgType
   if [ $# -gt 0 ] && [ "$1" = "-check" ]
   then msgType="${REDct}**ERROR**${CLRct}"
   else msgType="${REDct}*WARNING*${CLRct}"
   fi
   isEmailConfigEnabledInAMTM=false

   if [ ! -s "$AMTM_Mail_Conf_File" ] || [ ! -s "$AMTM_Mail_Pswd_File" ]
   then
       _PrintMsg_ "\n${msgType}: Unable to send email notifications."
       _PrintMsg_ "\n${MGNTct}AMTM email configuration file has not been set up.${CLRct}\n"
       return 1
   fi

   # AMTM Email Configuration file variables #
   FROM_NAME=""  TO_NAME=""  FROM_ADDRESS=""  TO_ADDRESS=""
   USERNAME=""  SMTP=""  PORT=""  PROTOCOL=""
   PASSWORD=""  emailPwEnc=""

   . "$AMTM_Mail_Conf_File"

   if [ -z "$TO_NAME" ] || [ -z "$USERNAME" ] || \
      [ -z "$FROM_ADDRESS" ] || [ -z "$TO_ADDRESS" ] || \
      [ -z "$SMTP" ] || [ -z "$PORT" ] || [ -z "$PROTOCOL" ] || \
      [ -z "$emailPwEnc" ] || [ "$PASSWORD" = "PUT YOUR PASSWORD HERE" ]
   then
       _PrintMsg_ "\n${msgType}: Unable to send email notifications."
       _PrintMsg_ "\n${MGNTct}Some AMTM email configuration variables are found empty.${CLRct}\n"
       return 1
   fi

   isEmailConfigEnabledInAMTM=true
   return 0
}

#-----------------------------------------------------------#
_CheckScriptInstallation_()
{
   if [ -d "$SCRIPT_INSTALL_PATH" ] && \
      [ -s "$theScriptFPath" ] && \
      [ -s "$SCRIPT_CONFIG_FPATH" ]
   then return 0
   fi
   _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Script [$SCRIPT_FNAME] is NOT properly set up.\n\n"
   return 1
}

#-----------------------------------------------------------#
_ShowConfigDefaultsFile_()
{
   if [ ! -s "$SCRIPT_CONFIG_FPATH" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Configuration file [$SCRIPT_CONFIG_FPATH] NOT found.\n"
       return 1
   fi
   printf "\n${GRNct}${SCRIPT_CONFIG_FPATH}${CLRct}\n"
   printf "----------------------------------------------\n"
   cat "$SCRIPT_CONFIG_FPATH"
   printf "----------------------------------------------\n"
}

#-----------------------------------------------------------#
_CreateConfigDefaultsFile_()
{
   [ ! -s "$theScriptFPath" ] && return 1
   if [ ! -s "$SCRIPT_CONFIG_FPATH" ]
   then
      {
         echo '## Global Configuration Defaults ##'
         echo 'emailCCName=""'
         echo 'emailCCEmail=""'
         echo 'emailSenderID=""'
         echo 'cemIsFormatHTML=true'
         echo 'cemIsVerboseMode=true'
      } > "$SCRIPT_CONFIG_FPATH"
   fi
   chmod 644 "$SCRIPT_CONFIG_FPATH"
   _DOStoUNIX_ "$SCRIPT_CONFIG_FPATH"
   . "$SCRIPT_CONFIG_FPATH"
   return 0
}

#-----------------------------------------------------------#
_ScriptSymbolicLink_()
{
   [ ! -d "$JFFS_SCRIPTS_DIR" ] && return 1
   case "$1" in
       delete) rm -f "$theScriptSLink" ;;
       create) ln -snf "$theScriptFPath" "$theScriptSLink" ;;
   esac
}

#-----------------------------------------------------------#
_DoScriptUpdate_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE '^-(check|force)$'
   then return 1
   fi
   _AcquireEmailMutexFLock_
   _CheckScriptVersionUpdate_ "$1"
   _CheckCustomEmailLibraryScript_ "$1"
   _ReleaseEmailMutexFLock_
}

#-----------------------------------------------------------#
_UpdateToStableBranch_()
{
   SCRIPT_GH_BRANCH="master"
   SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/${SCRIPT_GH_BRANCH}/EMail"
   SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/${SCRIPT_GH_BRANCH}/EMail"
   _DoScriptUpdate_ -force
}

#-----------------------------------------------------------#
_UpdateToDevelopBranch_()
{
   SCRIPT_GH_BRANCH="develop"
   SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/${SCRIPT_GH_BRANCH}/EMail"
   SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/${SCRIPT_GH_BRANCH}/EMail"
   _DoScriptUpdate_ -force
}

#-----------------------------------------------------------#
_ScriptInstallation_()
{
   local verStr  rawFPath
   mkdir -m 755 -p "$SCRIPT_INSTALL_PATH"
   if [ ! -d "$SCRIPT_INSTALL_PATH" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Unable to create directory path [$SCRIPT_INSTALL_PATH]\n"
       return 1
   fi

   rawFPath="$(readlink -f "$1")"
   if [ "$1" != "$theScriptFPath" ] && \
      [ "$rawFPath" != "$theScriptFPath" ]
   then mv -f "$rawFPath" "$theScriptFPath"
   fi
   chmod 755 "$theScriptFPath"
   _DOStoUNIX_ "$theScriptFPath"
   _CreateConfigDefaultsFile_
   _ScriptSymbolicLink_ create

   verStr="${GRNct}$("$theScriptFPath" -getvers)${CLRct}"
   _PrintMsg_ "\nThe script ${GRNct}${SCRIPT_FNAME}${CLRct} version $verStr was installed.\n"
   if [ ! -L "$theScriptSLink" ]
   then echo
   else _PrintMsg_ "Command to run the script: ${GRNct}${theScriptSLink}${CLRct}\n"
   fi

   _CheckEmailConfigFileFromAMTM_ -install
   _PressAnyKey_ ; _ShowUsageShort_
   return 0
}

#-----------------------------------------------------------#
_ScriptUninstallation_()
{
   rm -f "$theScriptFPath"
   rm -f "$SCRIPT_CONFIG_FPATH"
   if [ "$(pwd)" != "$SCRIPT_INSTALL_PATH" ]
   then rm -fr "$SCRIPT_INSTALL_PATH"
   fi
   [ "$1" != "$theScriptFPath" ] && rm -f "$1"
   _ScriptSymbolicLink_ delete
   _PrintMsg_ "\nThe script ${GRNct}${SCRIPT_FNAME}${CLRct} was uninstalled.\n\n"
   return 0
}

#-----------------------------------------------------------#
##**TBD??**## _EditConfigMenu_() { return 1 ; }

#-----------------------------------------------------------#
_DownloadScriptFile_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1
   fi

   local srcFilePathURL="${1}/$2"
   local tempFilePathDL="${TEMP_DIR}/${2}.DL.$$.TMP"
   local theDestFName="$2"  theDestFPath="$3"
   local theMsgStr  logMsgStr
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR

   rm -f "$tempFilePathDL"
   printf '' > "$curlErrLogFPath"
   printf '' > "$curlTmpLogFPath"

   curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${curlHTTPstatusStr}: %{http_code}\n" --stderr "$curlErrLogFPath" \
   "$srcFilePathURL" --output "$tempFilePathDL" >> "$curlTmpLogFPath"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${curlHTTPstatusStr}: [4-5][0-9]{2,}" "$curlTmpLogFPath")"

   if [ "$curlRetCode" -eq 0 ] && \
      [ -z "$httpStatusSTR" ] && [ -s "$tempFilePathDL" ]
   then
       mv -f "$tempFilePathDL" "$theDestFPath"
       dos2unix "$theDestFPath" ; chmod 644 "$theDestFPath"
   else
       if [ "$curlRetCode" -eq 0 ] && [ -n "$httpStatusSTR" ]
       then
           statusCODE="$(echo "$httpStatusSTR" | awk -F' ' '{print $2}')"
           statusSTRx="HTTP Status Code: $statusCODE"
       fi
       logMsgStr="**ERROR**: Unable to download the script file [$theDestFName] [${statusSTRx}]"
       theMsgStr="${REDct}**ERROR**${CLRct}: Unable to download the script file ${REDct}${theDestFName}${CLRct} [${MGNTct}${statusSTRx}${CLRct}]"
       _LogMsg_ "$logMsgStr" "$pLogERROR" NOECHO

       if [ "$4" -eq "$urlDLMax" ] || "$isVerboseMode" || "$doShowErrorMsgs"
       then
           if [ -s "$curlErrLogFPath" ]
           then echo ; cat "$curlErrLogFPath"
           fi
           _PrintMsg_ "\n${theMsgStr}\n"
           [ "$4" -lt "$urlDLMax" ] && \
           _PrintMsg_ "\nTrying again with a different URL...\n"
       fi
       rm -f "$tempFilePathDL"
   fi

   rm -f "$curlErrLogFPath" "$curlTmpLogFPath"
   return "$statusCODE"
}

#-----------------------------------------------------------#
_DownloadCustomEmailLibraryScript_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE '^-(update|install|force)$'
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: NO valid parameter was provided to download library file.\n"
       return 1
   fi

   mkdir -m 755 -p "$ADDONS_SHARED_LIBS_DIR_PATH"
   if [ ! -d "$ADDONS_SHARED_LIBS_DIR_PATH" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Directory Path [$ADDONS_SHARED_LIBS_DIR_PATH] *NOT* found.\n"
       return 1
   fi

   local actionStr1  actionStr2  retCode  urlDLCount  urlDLMax
   local isVerboseMode="$cemIsVerboseMode"  updateType  theVerStr

   case "$1" in
       -force)
           updateType="force"
           actionStr1="Updating"
           actionStr2="updated to the latest version"
           ;;
       -update)
           updateType="check"
           actionStr1="Updating"
           actionStr2="updated to the latest version"
           ;;
       -install)
           updateType="check"
           actionStr1="Installing"
           actionStr2="installed, version"
           ;;
   esac

   [ "$updateType" = "check" ] && "$isVerboseMode" && \
   _PrintMsg_ "\n${actionStr1} the shared email library script to support email notifications...\n"

   retCode=1 ; urlDLCount=0 ; urlDLMax=2
   for theScriptURL in "$SCRIPT_URL_REPO1" "$SCRIPT_URL_REPO2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadScriptFile_ "$theScriptURL" "$CUSTOM_EMAIL_LIB_SCRIPT_FNAME" "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" "$urlDLCount"
       then
           . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"
           chmod 755 "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

           if [ "$updateType" = "force" ] || "$isVerboseMode" || \
              { [ "$urlDLCount" -gt 1 ] && "$doShowErrorMsgs" ; }
           then
               [ "$urlDLCount" -gt 1 ] && echo
               theVerStr="${GRNct}${CEM_LIB_VERSION}${CLRct} [${GRNct}${CEM_LIB_VERSTAG}${CLRct}]"
               _PrintMsg_ "The shared email library script ${GRNct}${CUSTOM_EMAIL_LIB_SCRIPT_FNAME}${CLRct} was ${actionStr2} ${theVerStr}.\n"
           fi
           retCode=0
           break
       fi
   done

   if [ "$retCode" -ne 0 ]
   then
       _PrintMsg_ "The shared email library script ${REDct}${CUSTOM_EMAIL_LIB_SCRIPT_FNAME}${CLRct} was NOT ${actionStr2}.\n"
   fi
   return "$retCode"
}

#-----------------------------------------------------------#
_CheckScriptVersionUpdate_()
{
   local dlVersionStr  dlVersTagStr  scriptMD5  dlTempMD5
   local scriptVerNum  dlFileVerNum  theVerStr  updateType
   local theTmpFilePath="${TEMP_DIR}/${SCRIPT_TNAME}.$$.TMP.SH"
   local retCode  urlDLCount  urlDLMax
   local isVerboseMode="$cemIsVerboseMode"

   _VersionStrToNum_()
   {
      if [ $# -eq 0 ] || [ -z "$1" ] ; then echo 0 ; return 1 ; fi
      local verNum  verStr

      verStr="$(echo "$1" | sed "s/['\"]//g")"
      verNum="$(echo "$verStr" | awk -F '.' '{printf ("%d%02d%02d\n", $1,$2,$3);}')"
      verNum="$(echo "$verNum" | sed 's/^0*//')"
      echo "$verNum" ; return 0
   }

   _FormatVersionStr_()
   {
       if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
       then echo ; return 1
       fi
       echo "${GRNct}${1}${CLRct} [${GRNct}${2}${CLRct}]"
   }

   if [ $# -gt 0 ] && [ "$1" = "-force" ]
   then updateType="force"
   else updateType="check"
   fi

   mkdir -m 755 -p "$SCRIPT_INSTALL_PATH"
   if [ ! -d "$SCRIPT_INSTALL_PATH" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Directory path [$SCRIPT_INSTALL_PATH] *NOT* found.\n"
       return 1
   fi

   [ "$updateType" = "check" ] && "$isVerboseMode" && \
   _PrintMsg_ "\nChecking for ${GRNct}${SCRIPT_FNAME}${CLRct} script updates...\n"

   retCode=1 ; urlDLCount=0 ; urlDLMax=2
   for theScriptURL in "$SCRIPT_URL_REPO1" "$SCRIPT_URL_REPO2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadScriptFile_ "$theScriptURL" "$SCRIPT_FNAME" "$theTmpFilePath" "$urlDLCount"
       then
           retCode=0 ; break
       fi
   done

   if [ "$retCode" -ne 0 ] || [ ! -s "$theTmpFilePath" ]
   then
       _PrintMsg_ "\nThe email script ${REDct}${SCRIPT_FNAME}${CLRct} was NOT updated.\n"
       return 1
   fi

   dlVersionStr="$(grep -E '^readonly SCRIPT_VERSION=' "$theTmpFilePath" | tr -d '"')"
   dlVersTagStr="$(grep -E '^readonly SCRIPT_VERSTAG=' "$theTmpFilePath" | tr -d '"')"
   if [ -z "$dlVersionStr" ] || [ -z "$dlVersTagStr" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Could NOT find the VERSION string.\n"
       rm -f "$theTmpFilePath"
       return 1
   fi

   dlTempMD5="$(md5sum "$theTmpFilePath" 2>/dev/null | awk -F' ' '{print $1}')"
   scriptMD5="$(md5sum "$theScriptFPath" 2>/dev/null | awk -F' ' '{print $1}')"
   dlVersionStr="$(echo "$dlVersionStr" | sed -e 's/.*SCRIPT_VERSION=//;s/ .*$//')"
   dlVersTagStr="$(echo "$dlVersTagStr" | sed -e 's/.*SCRIPT_VERSTAG=//;s/ .*$//')"
   dlFileVerNum="$(_VersionStrToNum_ "$dlVersionStr")"
   scriptVerNum="$(_VersionStrToNum_ "$SCRIPT_VERSION")"

   if [ "$updateType" = "check" ] && \
      { [ "$scriptMD5" = "$dlTempMD5" ] || \
        [ "$dlFileVerNum" -lt "$scriptVerNum" ]
      }
   then
       rm -f "$theTmpFilePath"
       theVerStr="$(_FormatVersionStr_ "$SCRIPT_VERSION" "$SCRIPT_VERSTAG")"
       _PrintMsg_ "You have the latest script version $theVerStr installed.\n"
       return 0
   fi

   theVerStr="$(_FormatVersionStr_ "$dlVersionStr" "$dlVersTagStr")"
   [ "$updateType" = "check" ] && \
   _PrintMsg_ "Latest script version update $theVerStr is available.\n"

   mv -f "$theTmpFilePath" "$theScriptFPath"
   chmod 755 "$theScriptFPath"
   _ScriptSymbolicLink_ create
   _PrintMsg_ "The email script ${GRNct}${SCRIPT_FNAME}${CLRct} was updated to the latest version ${theVerStr}.\n"

   return 0
}

#-----------------------------------------------------------#
_CheckCustomEmailLibraryScript_()
{
   local retCode=0
   local doDL_LibScriptMsge=""
   local doDL_LibScriptFlag=false

   if [ ! -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ]
   then
       _DownloadCustomEmailLibraryScript_ -install
       return "$?"
   fi

   . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

   if [ $# -gt 0 ] && [ "$1" = "-force" ]
   then
       retCode=1
       _DoReInit_CEM_
       doDL_LibScriptFlag=true
       doDL_LibScriptMsge="-force"
   else
       if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
          _CheckLibraryUpdates_CEM_ "$ADDONS_SHARED_LIBS_DIR_PATH" "$quietARG"
       then
           retCode=1
           doDL_LibScriptFlag=true
           doDL_LibScriptMsge="-update"
       fi
   fi

   if "$doDL_LibScriptFlag"
   then
       _DownloadCustomEmailLibraryScript_ "$doDL_LibScriptMsge"
       retCode="$?"
   fi
   return "$retCode"
}

#-----------------------------------------------------------#
_IsOptionalEmailArg_()
{
   if echo "$1" | grep -qE '^-(From|CCName|CCEmail)=.+'
   then return 0
   else return 1
   fi
}

#-----------------------------------------------------------#
_IsValidActionArg_()
{
   if echo "$1" | \
      grep -qE '^-(send|test|install|uninstall|checkupdate|forceupdate|stable|develop|showconf|version|getvers)$'
   then return 0
   else return 1
   fi
}

#-----------------------------------------------------------#
# ARG1: Email Subject string.
# ARG2: Email Body Message string or the full path of
#       the file containing the Email Body Message.
# ARG3: Email Body Title string [OPTIONAL].
#-----------------------------------------------------------#
_SendEMailMsg_()
{
   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       logMsgStr="Shared email library script [$CUSTOM_EMAIL_LIB_SCRIPT_FNAME] is *NOT* loaded."
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: ${MGNTct}${logMsgStr}${CLRct}\n\n"
       _LogMsg_ "$logMsgStr" "$pLogERROR" NOECHO
       return 1
   fi
   local retCode  showErrorMsgs=false
   local emailBodyMsgStr  emailBodyFile=""  emailBodyTitleStr=""
   local emailBodySendFPath="${emailBodyCFPath}.SEND"

   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: INSUFFICIENT email parameters\n"
       return 1
   fi

   if echo "$2" | grep -qE '^-File=.+'
   then
       emailBodyFile="${2##*=}"
       if [ ! -s "$emailBodyFile" ]
       then
           _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Email body message file [$emailBodyFile] NOT found.\n"
           return 1
       fi
       cp -fp "$emailBodyFile" "$emailBodySendFPath"
       chmod 666 "$emailBodySendFPath"
   elif ! _IsOptionalEmailArg_ "$2"
   then
       echo "$2" > "$emailBodySendFPath"
   fi

   if [ ! -s "$emailBodySendFPath" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Email body message file is EMPTY.\n"
       return 1
   fi

   if [ $# -gt 2 ] && [ -n "$3" ] && ! _IsOptionalEmailArg_ "$3"
   then emailBodyTitleStr="$3"
   fi

   ## ONLY for DEBUG/TEST purposes set to 'true' ##
   cemIsDebugMode=false

   if [ -n "$emailCCName" ] && [ -n "$emailCCEmail" ]
   then
       CC_NAME="$emailCCName" ; CC_ADDRESS="$emailCCEmail"
   fi
   [ -n "$emailSenderID" ] && FROM_NAME="$emailSenderID"

   _SendEMailNotification_CEM_ "$1" -F="$emailBodySendFPath" "$emailBodyTitleStr"
   retCode="$?"

   if [ "$retCode" -eq 0 ]
   then
       logTag=""
       logMsg="The email notification [${GRNct}${1}${CLRct}] was sent successfully."
   else
       showErrorMsgs=true
       logTag="${REDct}**ERROR**${CLRct}: "
       logMsg="Failure to send email notification [${MGNTct}${1}${CLRct}] [${REDct}Error Code: $retCode${CLRct}]."
   fi

   if ! "$cemIsVerboseMode" || "$showErrorMsgs"
   then
       _PrintMsg_ "\n${logTag}${logMsg}\n"
   fi

   [ -n "$emailBodyFile" ] && rm -f "$emailBodyFile"
   return "$retCode"
}

#-----------------------------------------------------------#
_Send_Email_TEST_()
{
    local retCode
    local emailSubject="$1"  emailBodyTitle="$2"
    local emailBodyTestFPath="${emailBodyCFPath}.TEST"

    {
       printf "\nThis is a TEST to check and verify if sending email notifications"
       printf " is working well using the \"<b>${SCRIPT_TNAME}</b>\" script tool.\n\n"
    } > "$emailBodyTestFPath"

    _SendEMailMsg_ "$emailSubject" -File="$emailBodyTestFPath" "$emailBodyTitle"
    retCode="$?"

    rm -f "$emailBodyTestFPath"
    return "$retCode"
}

#-----------------------------------------------------------#
showUsage=false
if [ $# -eq 0 ] || [ -z "$1" ] || echo "$1" | grep -qE '^[-]?help$'
then
    showUsage=true
elif ! _IsValidActionArg_ "$1"
then
    _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: NO valid arguments [$*] were provided.\n"
    showUsage=true ; _PressAnyKey_
fi
"$showUsage" && { _ShowUsageLong_ ; exit 0 ; }

action="$1" ; shift

case "$action" in
    -getvers)
        printf "${versionStrNums}\n"
        exit 0
        ;;
    -version)
        _PrintMsg_ "\nVersion: ${versionStrInfo}\n\n"
        exit 0
        ;;
    -install)
        _ScriptInstallation_ "$0"
        exit "$?"
        ;;
    -uninstall)
        _ScriptUninstallation_ "$0"
        exit "$?"
        ;;
    -showconf)
        _ShowConfigDefaultsFile_
        exit 0
        ;;
    *) ##CONTINUE##
       ;;
esac

if ! _CheckScriptInstallation_
then exit 1
fi
. "$SCRIPT_CONFIG_FPATH"

quietARG=""
mainRequiredARGs=""

for PARAM in "$@"
do
   case "$PARAM" in
       -html)
           shift
           cemIsFormatHTML=true
           ;;
       -ptext)
           shift
           cemIsFormatHTML=false
           ;;
       -quiet)
           shift
           quietARG="-quiet"
           cemIsVerboseMode=false
           ;;
       -silent)
           shift
           quietARG="-veryquiet"
           doShowErrorMsgs=false
           cemIsVerboseMode=false
           ;;
       -verbose)
           shift
           cemIsVerboseMode=true
           ;;
       *) 
         if echo "$PARAM" | grep -qE '^-From=.+'
         then
             emailSenderID="${PARAM##*=}"
         elif echo "$PARAM" | grep -qE '^-CCName=.+'
         then
             emailCCName="${PARAM##*=}"
         elif echo "$PARAM" | grep -qE '^-CCEmail=.+'
         then
             emailCCEmail="${PARAM##*=}"
         else
             mainRequiredARGs="${mainRequiredARGs:+$mainRequiredARGs} '$PARAM'"
         fi
         shift
         ;;
   esac
done

[ -n "$mainRequiredARGs" ] && eval set -- "$mainRequiredARGs"

if [ "$action" = "-stable" ]
then
    _UpdateToStableBranch_
    exit 0
elif [ "$action" = "-develop" ]
then
    _UpdateToDevelopBranch_
    exit 0
elif [ "$action" = "-checkupdate" ] || \
     [ "$action" = "-forceupdate" ] || \
     [ ! -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ]
then
    if [ -z "${cemIsVerboseMode:+xSETx}" ]
    then cemIsVerboseMode=true
    fi
    updateType=""
    if [ "$action" = "-forceupdate" ]
    then updateType="-force"
    else updateType="-check"
    fi
    _DoScriptUpdate_ "$updateType"

    if [ "$action" = "-checkupdate" ] || \
       [ "$action" = "-forceupdate" ]
    then exit 0
    fi
fi

! _CheckEmailConfigFileFromAMTM_ -check && exit 1
. "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

if [ "$action" = "-test" ]
then
    emailSubjectSTR="TEST Email"
    emailBodyTITLEx="TESTING Email Notifications"

    if [ -z "$emailSenderID" ]
    then emailSenderID="Email_TEST"
    fi
    if [ $# -gt 0 ] && [ -n "$1" ]
    then emailSubjectSTR="$1"
    fi
    if [ $# -gt 1 ] && [ -n "$2" ]
    then emailBodyTITLEx="$2"
    fi
    _Send_Email_TEST_ "$emailSubjectSTR" "$emailBodyTITLEx"
    exit "$?"
#
elif [ "$action" = "-send" ]
then
    if [  $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
    then
        _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: INSUFFICIENT number of arguments.\n"
        _PressAnyKey_ ; _ShowUsageShort_
    else
        _SendEMailMsg_ "$@"
        exit "$?"
    fi
fi

exit 0

#EOF#
