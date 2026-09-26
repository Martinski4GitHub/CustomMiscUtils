#!/bin/sh
#####################################################################
# SendEmail.sh
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
# Creation Date: 2026-Jun-14 [Martinski W.]
# Last Modified: 2026-Sep-25 [Martinski W.]
#####################################################################
set -u

readonly SCRIPT_VERSION="v0.9.1"
readonly SCRIPT_VERSTAG="26092523"
readonly SCRIPT_TNAME="SendEmail"
readonly SCRIPT_FNAME="${SCRIPT_TNAME}.sh"
SCRIPT_BRANCH="develop"   ##**SET to "master" for RELEASE**##

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

readonly REPO_URL_BASE2="https://raw.githubusercontent.com/MartinSkyW"
readonly REPO_URL_BASE1="https://raw.githubusercontent.com/Martinski4GitHub"

readonly EMAIL_LIB_BRANCH="master"
readonly EMAIL_LIB_URL_BASE1="${REPO_URL_BASE1}/CustomMiscUtils"
readonly EMAIL_LIB_URL_BASE2="${REPO_URL_BASE2}/CustomMiscUtils"
readonly EMAIL_LIB_REPO_URL1="${EMAIL_LIB_URL_BASE1}/${EMAIL_LIB_BRANCH}/EMail"
readonly EMAIL_LIB_REPO_URL2="${EMAIL_LIB_URL_BASE2}/${EMAIL_LIB_BRANCH}/EMail"

readonly SCRIPT_URL_BASE1="${REPO_URL_BASE1}/SendEmail"
readonly SCRIPT_URL_BASE2="${REPO_URL_BASE2}/SendEmail"
SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/$SCRIPT_BRANCH"
SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/$SCRIPT_BRANCH"

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
readonly BOLDct="\e[1m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly YLWct="\e[1;33m"
readonly MGNTct="\e[1;35m"
readonly CYANct="\e[1;36m"
readonly GRAYEDct="\e[0;30;47m"
readonly BOLDUNDERLN="\e[1;4m"

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

if [ "$SCRIPT_BRANCH" = 'master' ]
then
    readonly branchxStrTAG="[ Branch: stable ]"
    readonly versionStrTAG="${SCRIPT_VERSION}"
    readonly versionStrNums="${SCRIPT_VERSION} ${CLRct}[${GRNct}${SCRIPT_VERSTAG}${CLRct}]"
    readonly versionStrInfo="${GRNct}${SCRIPT_VERSION}${CLRct} [${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${GRNct}stable${CLRct}]"
else
    readonly branchxStrTAG="[ Branch: development ]"
    readonly versionStrTAG="${SCRIPT_VERSION}_${SCRIPT_VERSTAG}"
    readonly versionStrNums="${SCRIPT_VERSION} ${CLRct}[${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${MGNTct}develop${CLRct}]"
    readonly versionStrInfo="${GRNct}${SCRIPT_VERSION}${CLRct} [${GRNct}${SCRIPT_VERSTAG}${CLRct} - Branch: ${MGNTct}develop${CLRct}]"
fi

#OPTIONAL#
emailCCName=""
emailCCEmail=""
emailSenderID=""
emailBodyTitle=""

#Configuration Defaults#
doShowErrorMsgs=true
cemIsFormatHTML=true
cemIsVerboseMode=true

#-----------------------------------------------------------#
_ShowUsageVerbose_()
{
   ! "$isInteractive" && return 0
   cat <<EOF1 | xargs -0 echo -e
----------------------------------------------------------------------------
Version: $versionStrInfo
Author: Martinski W.

The ${GRNct}SendEmail${CLRct} script is a CLI utility to send email notifications.
It uses the shared Email Library script for the email functionality,
and the AMTM email configuration file as the user-defined email setup.


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

To test and verify if the current email notification setup is working:

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct}

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SUBJECT_LINE" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"

  ${YLWct}--------------${CLRct}
  Example calls:
  ${YLWct}--------------${CLRct}

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct}

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "TEST Email Subject"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "TEST Email Subject" ${MGNTct}-Title=${CLRct}"TESTING My Email Setup"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "TEST Email Subject"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "TEST Email Subject" ${MGNTct}-Title=${CLRct}"TESTING My Email Setup"

EOF2

   cat <<EOF3 | xargs -0 echo -e

To send email notifications [the order of the arguments is important]:

  ${GRNct}$SCRIPT_TNAME${CLRct} "SUBJECT_LINE" "EMAIL_BODY_STRING"

  ${GRNct}$SCRIPT_TNAME${CLRct} "SUBJECT_LINE" "EMAIL_BODY_STRING" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"

  ${GRNct}$SCRIPT_TNAME${CLRct} "SUBJECT_LINE" ${MGNTct}-Body=${CLRct}"EMAIL_BODY_FILE"

  ${GRNct}$SCRIPT_TNAME${CLRct} "SUBJECT_LINE" ${MGNTct}-Body=${CLRct}"EMAIL_BODY_FILE" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" "EMAIL_BODY_STRING"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" "EMAIL_BODY_STRING" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" ${MGNTct}-Body=${CLRct}"EMAIL_BODY_FILE"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"FROM_NAME" "SUBJECT_LINE" ${MGNTct}-Body=${CLRct}"EMAIL_BODY_FILE" ${MGNTct}-Title=${CLRct}"EMAIL_BODY_TITLE"


  ${YLWct}----------------------------------------------------------------${CLRct}
  Example calls using a simple one-line email body message string:
  ${YLWct}----------------------------------------------------------------${CLRct}
   
  ${GRNct}$SCRIPT_TNAME${CLRct} "Subject Line" "Simple Email Body Message String"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"SenderID" "Subject Line" "Simple Email Body Message String"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"SenderID" "Subject Line" "Simple Email Body Message String" ${MGNTct}-Title=${CLRct}"Email Body Title Line"


  ${YLWct}-------------------------------------------------------------------${CLRct}
  Example calls using an email body message file with multiple lines:
  ${YLWct}-------------------------------------------------------------------${CLRct}

  {
     echo "This email was sent for testing purposes only."
     echo "The email body may have multiple lines of text."
     echo "This is the third line of text of the email body."
  } > ${TMP_DIR}/theEmailBody.txt

  ${GRNct}$SCRIPT_TNAME${CLRct} "Subject Line" ${MGNTct}-Body=${CLRct}"${TMP_DIR}/theEmailBody.txt" 

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"SenderID" "Subject Line" ${MGNTct}-Body=${CLRct}"${TMP_DIR}/theEmailBody.txt"

  ${GRNct}$SCRIPT_TNAME ${MGNTct}-From=${CLRct}"SenderID" "Subject Line" ${MGNTct}-Body=${CLRct}"${TMP_DIR}/theEmailBody.txt" ${MGNTct}-Title=${CLRct}"Email Body Title Line"

EOF3

   cat <<EOF4 | xargs -0 echo -e

OPTIONAL command-line argument switches:

  ${CYANct}-html${CLRct}     Send email in HTML format
  ${CYANct}-ptext${CLRct}    Send email in 'Plain Text' format
  ${CYANct}-quiet${CLRct}    Disable "Verbose Mode" (show errors only)
  ${CYANct}-verbose${CLRct}  Enabled 'Verbose Mode'

  ${YLWct}--------------${CLRct}
  Example calls:
  ${YLWct}--------------${CLRct}

  ${GRNct}$SCRIPT_TNAME ${CYANct}-test -ptext${CLRct}

  ${GRNct}$SCRIPT_TNAME ${CYANct}-ptext${CLRct} "Subject Line" "Email Body Message String"

  ${GRNct}$SCRIPT_TNAME ${CYANct}-ptext -quiet${CLRct} ${MGNTct}-From=${CLRct}"SenderID" "Subject Line" "Email Body Message String" ${MGNTct}-Title=${CLRct}"Email Body Title Line"


DEFAULT global values if not explicitly modified:

   - Email is sent in HTML format
   - Verbose mode is ENABLED
   - The "SenderID" (aka "FROM_NAME") is empty and the value is extracted 
     from the NVRAM 'http_username' key
   - The "Body Title Line" (aka "EMAIL_BODY_TITLE") is empty


See configuration file ${CYANct}${SCRIPT_CONFIG_FPATH}${CLRct} for GLOBAL defaults.
A default can be overridden in each command execution by explicitly adding an argument.

For example, if adding the ${CYANct}-ptext${CLRct} argument, the email format will be Plain Text.
When adding the ${MGNTct}-From=${CYANct}"MyUniqueSenderID"${CLRct} argument, the defined sender ID is used
in the email notification sent by the command invocation.

If you want to change a global default for ALL command executions, modify the value
in the configuration file. Valid characters are only alphanumeric, period, hyphen,
underscore, and at (@) symbols.

${MGNTct}emailSenderID=${CYANct}"MyUniqueSenderID"${CLRct}
----------------------------------------------------------------------------
EOF4
}

#-----------------------------------------------------------#
_ShowUsageConcise_()
{
   ! "$isInteractive" && return 0
   cat <<EOF1 | xargs -0 echo -e
-----------------------------------------------------------------------
Version: $versionStrInfo
Author: Martinski W.

The ${GRNct}SendEmail${CLRct} script is a CLI utility to send email notifications.
It uses the shared Email Library script for the email functionality,
and the AMTM email configuration file as the user-defined email setup.

Example calls:

To get full help and description of all command line arguments:

 ${GRNct}$SCRIPT_TNAME ${CYANct}-help${CLRct}

Miscellaneous command line arguments:

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
 ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SubjectLine"
 ${GRNct}$SCRIPT_TNAME ${CYANct}-test${CLRct} "SubjectLine" ${MGNTct}-Title=${CLRct}"EmailBodyTITLE"

To send simple email notifications:

 ${GRNct}$SCRIPT_TNAME${CLRct} "SubjectLine" "EmailBodySTRING"
 ${GRNct}$SCRIPT_TNAME${CLRct} "SubjectLine" "EmailBodySTRING" ${MGNTct}-Title=${CLRct}"EmailBodyTITLE"
 ${GRNct}$SCRIPT_TNAME${CLRct} "SubjectLine" ${MGNTct}-Body=${CLRct}"EmailBodyFILE"
 ${GRNct}$SCRIPT_TNAME${CLRct} "SubjectLine" ${MGNTct}-Body=${CLRct}"EmailBodyFILE" ${MGNTct}-Title=${CLRct}"EmailBodyTITLE"
-----------------------------------------------------------------------
EOF1
}

#-----------------------------------------------------------#
_PressAnyKey_()
{
	! "$isInteractive" && return 0
	printf "\nPress ANY key to continue..."
	read -n1 -rs anyKEY ; echo
}

#-----------------------------------------------------------#
_ConfirmYESorNO_()
{
	if ! "$isInteractive"
	then return 0
	fi
	local promptStr  theAnswer

	if [ $# -eq 0 ] || [ -z "$1" ]
	then promptStr=" [yY|nN]?"
	else promptStr=" $1 [yY|nN]?"
	fi
	printf "$promptStr  " ; read -r theAnswer
	[ -z "$theAnswer" ] && theAnswer="NO"
	if echo "$theAnswer" | grep -qE "^([Yy](es)?|YES)$"
	then echo "OK" ; return 0
	else echo "NO" ; return 1
	fi
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
            _PrintMsg_ "Stale Lock Found. Resetting Lock file...\n"
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
        _PrintMsg_ "${MGNTct}*WARNING*${CLRct}: Another process [$procInfo] has the Lock.\n"
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

_EscapeChars_()
{ printf "%s" "$1" | sed 's/[][\/{}()$|.*^&+-]/\\&/g' ; }

#-----------------------------------------------------------#
_GetScriptConfigOption_()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then echo ; return 1
	fi
	local keyPair  defValue=""

	if [ $# -gt 1 ] && [ -n "$2" ]
	then defValue="$2"
	fi
	if [ ! -d "$SCRIPT_INSTALL_PATH" ]
	then
		echo "$defValue"
		return 1
	fi
	if [ ! -f "$SCRIPT_CONFIG_FPATH" ]
	then printf '' > "$SCRIPT_CONFIG_FPATH"
	fi
	chmod 644 "$SCRIPT_CONFIG_FPATH"

	keyPair="$(grep -m1 -E "^${1}=.*" "$SCRIPT_CONFIG_FPATH")"
	if [ -z "$keyPair" ]
	then
		if [ -z "$defValue" ]
		then echo "${1}=''" >> "$SCRIPT_CONFIG_FPATH"
		else echo "${1}=$defValue" >> "$SCRIPT_CONFIG_FPATH"
		fi
		echo "$defValue"
	else
		echo "$keyPair" | cut -d'=' -f2- | sed "s/['\"]//g"
	fi
	return 0
}

#-----------------------------------------------------------#
_SetScriptConfigOption_()
{
	if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
	then return 1
	fi
	local newVal

	if [ ! -d "$SCRIPT_INSTALL_PATH" ]
	then
		mkdir -p "$SCRIPT_INSTALL_PATH"
	fi
	if [ ! -f "$SCRIPT_CONFIG_FPATH" ]
	then printf '' > "$SCRIPT_CONFIG_FPATH"
	fi
	chmod 644 "$SCRIPT_CONFIG_FPATH"

    #Get a "clean" string for 'grep' & 'sed'#
    newVal="$(_EscapeChars_ "$2")"

	if ! grep -qE "^${1}=.*" "$SCRIPT_CONFIG_FPATH"
	then
		if echo "$2" | grep -qE '^(true|false)$'
		then echo "${1}=${2}" >> "$SCRIPT_CONFIG_FPATH"
		else echo "${1}='${2}'" >> "$SCRIPT_CONFIG_FPATH"
		fi
	elif ! grep -qE "^${1}=$newVal" "$SCRIPT_CONFIG_FPATH"
	then
		if echo "$2" | grep -qE '^(true|false)$'
		then
			sed -i "s/${1}=.*/${1}=${2}/" "$SCRIPT_CONFIG_FPATH"
		else
			sed -i "s/${1}=.*/${1}='${newVal}'/" "$SCRIPT_CONFIG_FPATH"
		fi
	fi
	return 0
}

#-----------------------------------------------------------#
_CheckEmailConfigFileFromAMTM_()
{
   local msgType  showMsg=true

   if [ $# -gt 0 ] && [ "$1" = "-check" ]
   then msgType="${REDct}**ERROR**${CLRct}"
   else msgType="${REDct}*WARNING*${CLRct}"
   fi
   if [ $# -gt 1 ] && [ "$2" = "-quiet" ]
   then showMsg=false
   fi

   isEmailConfigEnabledInAMTM=false

   if [ ! -s "$AMTM_Mail_Conf_File" ] || [ ! -s "$AMTM_Mail_Pswd_File" ]
   then
       "$showMsg" && \
       {
         _PrintMsg_ "\n${msgType}: Unable to send email notifications."
         _PrintMsg_ "\n${MGNTct}AMTM email configuration file has not been set up.${CLRct}\n"
       }
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
       "$showMsg" && \
       {
         _PrintMsg_ "\n${msgType}: Unable to send email notifications."
         _PrintMsg_ "\n${MGNTct}Some AMTM email configuration variables are found empty.${CLRct}\n"
       }
       return 1
   fi

   isEmailConfigEnabledInAMTM=true
   return 0
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
   _CheckScriptVersionUpdate_ "$@"
   _CheckCustomEmailLibraryScript_ "$@"
   _ReleaseEmailMutexFLock_ checkLockOK
}

#-----------------------------------------------------------#
_SwitchToStableBranch_()
{
   SCRIPT_BRANCH='master'
   SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/$SCRIPT_BRANCH"
   SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/$SCRIPT_BRANCH"
   _DoScriptUpdate_ -force
}

#-----------------------------------------------------------#
_SwitchToDevelopBranch_()
{
   SCRIPT_BRANCH='develop'
   SCRIPT_URL_REPO1="${SCRIPT_URL_BASE1}/$SCRIPT_BRANCH"
   SCRIPT_URL_REPO2="${SCRIPT_URL_BASE2}/$SCRIPT_BRANCH"
   _DoScriptUpdate_ -force
}

#-----------------------------------------------------------#
_DoScriptUpdateFromAMTM_()
{
   if [ $# -gt 0 ] && [ "$1" = "check" ]
   then return 0
   fi
   _DoScriptUpdate_ -force
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
   if [ $# -eq 0 ] || [ -z "$1" ] || [ "$1" != "-quiet" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Script [$SCRIPT_FNAME] is NOT properly set up.\n\n"
   fi
   return 1
}

#-----------------------------------------------------------#
_ScriptInstallation_()
{
   local verStr  rawFPath  retCode=0

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

   if ! _CheckEmailConfigFileFromAMTM_ -install
   then
       retCode=1
       _PressAnyKey_
   fi

   if [ $# -lt 2 ] || [ -z "$2" ] || [ "$2" != "-quiet" ]
   then
       if [ ! -L "$theScriptSLink" ]
       then echo
       else _PrintMsg_ "Command to run the script: ${GRNct}${theScriptSLink}${CLRct}\n"
       fi
       _PressAnyKey_
       _ShowUsageConcise_
   fi
   return "$retCode"
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
   for theScriptURL in "$EMAIL_LIB_REPO_URL1" "$EMAIL_LIB_REPO_URL2"
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

      verStr="$(echo "$1" | sed "s/[v'\"]//g")"
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
_IsOptionalEmailArg_()   ##*TBD*: '-Attach='??##
{
   if printf '%s\n' "$1" | grep -qE '^-(From|Title|Body|CCName|CCEmail)=.+'
   then return 0
   else return 1
   fi
}

#-----------------------------------------------------------#
_CheckValidParams_()
{
   if ! printf '%s\n' "$1" | grep -qE '^[-].+' || _IsOptionalEmailArg_ "$1" || \
      printf '%s\n' "$1" | grep -qE '^-(test|install|uninstall|checkupdate|forceupdate|stable|develop|showconf|version|getvers|html|ptext|quiet|silent|verbose)$'
   then return 0
   else return 1
   fi
}

#-----------------------------------------------------------#
# ARG1: Email Subject Line string.
# ARG2: Email Message Body string or the full path of
#       the file containing the Email Message Body.
#-----------------------------------------------------------#
_Send_EMail_Msg_()
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

   if echo "$2" | grep -qE '^-Body=.+'
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

   ## ONLY for DEBUG/TEST purposes set to 'true' ##
   cemIsDebugMode=false

   if [ -n "$emailCCName" ] && [ "$emailCCName" != 'TBD' ] && \
      [ -n "$emailCCEmail" ] && [ "$emailCCEmail" != 'TBD' ]
   then
       CC_NAME="$emailCCName" ; CC_ADDRESS="$emailCCEmail"
   fi
   [ -n "$emailSenderID" ] && FROM_NAME="$emailSenderID"
   [ -n "$emailBodyTitle" ] && emailBodyTitleStr="$emailBodyTitle"

   _SendEMailNotification_CEM_ "$1" -F="$emailBodySendFPath" "$emailBodyTitleStr"
   retCode="$?"

   if [ "$retCode" -eq 0 ]
   then
       logTag=""
       logMsg="The email notification [${GRNct}${1}${CLRct}] was sent successfully."
       if [ -n "$emailBodyFile" ] && echo "$emailBodyFile" | grep -qE '^/tmp/.+'
       then rm -f "$emailBodyFile"
       fi
   else
       showErrorMsgs=true
       logTag="${REDct}**ERROR**${CLRct}: "
       logMsg="Failure to send email notification [${MGNTct}${1}${CLRct}] [${REDct}Error Code: $retCode${CLRct}]."
   fi

   if ! "$cemIsVerboseMode" || "$showErrorMsgs"
   then
       _PrintMsg_ "\n${logTag}${logMsg}\n"
   fi
   return "$retCode"
}

#-----------------------------------------------------------#
_Send_Email_TEST_()
{
    local retCode  emailSubjectStr
    local emailBodyTestFPath="${emailBodyCFPath}.TEST"

    if [ $# -gt 0 ] && [ -n "$1" ]
    then emailSubjectStr="$1"
    else emailSubjectStr="TEST Email"
    fi
    if [ -z "$emailSenderID" ]
    then emailSenderID="Email_TEST"
    fi
    if [ -z "$emailBodyTitle" ]
    then emailBodyTitle="TESTING Email Notifications"
    fi

    {
       printf "\nThis is a <b>TEST</b> to check and verify if sending email notifications"
       printf " is working well using the \"<b>${SCRIPT_TNAME}</b>\" script tool.\n\n"
    } > "$emailBodyTestFPath"

    . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

    _Send_EMail_Msg_ "$emailSubjectStr" -Body="$emailBodyTestFPath"
    retCode="$?"

    rm -f "$emailBodyTestFPath"
    return "$retCode"
}

#-----------------------------------------------------------#
_CenterTextStr_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
       ! echo "$2" | grep -qE '^[1-9][0-9]+$'
    then echo ; return 1
    fi
    local stringLen="${#1}"
    local space1Len="$((($2 - stringLen)/2))"
    local space2Len="$space1Len"
    local totalLen="$((space1Len + stringLen + space2Len))"

    if [ "$totalLen" -lt "$2" ]
    then space2Len="$((space2Len + 1))"
    elif [ "$totalLen" -gt "$2" ]
    then space1Len="$((space1Len - 1))"
    fi
    if [ "$space1Len" -gt 0 ] && [ "$space2Len" -gt 0 ]
    then printf "%*s%s%*s" "$space1Len" '' "$1" "$space2Len" ''
    else printf "%s" "$1"
    fi
}

#-----------------------------------------------------------#
_ShowMenuHeader_()
{
   local spaceLen=44  colorCT
   [ "$SCRIPT_BRANCH" = 'master' ] && colorCT="$CYANct" || colorCT="$MGNTct"
   clear ; echo
   printf "${BOLDct}##==============================================##${CLRct}\n"
   printf "${BOLDct}##                ${GRNct}SendEmail Tool${CLRct}                ${BOLDct}##${CLRct}\n"
   printf "${BOLDct}##                --------------                ##${CLRct}\n"
   printf "${BOLDct}## ${CYANct}%s${CLRct}${BOLDct} ##${CLRct}\n" "$(_CenterTextStr_ "$versionStrTAG" "$spaceLen")"
   printf "${BOLDct}## ${colorCT}%s${CLRct}${BOLDct} ##${CLRct}\n" "$(_CenterTextStr_ "$branchxStrTAG" "$spaceLen")"
   printf "${BOLDct}##==============================================##${CLRct}\n\n"
}

#-----------------------------------------------------------#
_InvalidMenuOptionHandler_()
{
	if [ -n "$menuSelection" ]
	then printf "\n Invalid input [${REDct}${menuSelection}${CLRct}]"
	fi
	printf "\n Select a valid menu option\n"
	_PressAnyKey_
}

#-----------------------------------------------------------#
_InvalidEmailOptionHandler_()
{
	printf "\n The email notification options are ${MGNTct}NOT${CLRct} available."
	printf "\n AMTM email configuration file MUST be set up first.\n"
	_PressAnyKey_
}

#-----------------------------------------------------------#
_ToggleEmailFormatType_()
{
	if ! "$cemIsFormatHTML"
	then _SetScriptConfigOption_ 'cemIsFormatHTML' true
	else _SetScriptConfigOption_ 'cemIsFormatHTML' false
	fi
	cemIsFormatHTML="$(_GetScriptConfigOption_ 'cemIsFormatHTML' true)"
}

#-----------------------------------------------------------#
_SetFromSenderID_()
{
    printf "\n\n**DEBUG-TBD**: TO BE DONE\n\n"
    _PressAnyKey_
    return 0
}

#-----------------------------------------------------------#
_SetSecondaryEmailAddress_()
{
   local currCC_NameOpt  currCC_AddrOpt
   local nextCC_NameOpt  nextCC_AddrOpt
   local currCC_NameStr="Current Name/Alias:"
   local currCC_AddrStr="Current Address:"
   local invalidChars='[][" *?\\]'   #Avoid parsing issues#
   local clearOptStr="${GRNct}C${CLRct}=Clear/Remove Setting"
   local doReturnToMenu  doClearSetting  minCharLen  maxCharLen  curCharLen
   local menuExitStr="${GRNct}e${CLRct}=Go back"

   currCC_NameOpt="$(_GetScriptConfigOption_ 'emailCCName')"
   currCC_AddrOpt="$(_GetScriptConfigOption_ 'emailCCEmail')"

   if [ -z "$currCC_AddrOpt" ] || [ "$currCC_AddrOpt" = "TBD" ]
   then
       nextCC_AddrOpt=""  currCC_AddrOpt=""
       currCC_AddrStr="Currently ${YLWct}NONE${CLRct}"
   else
       nextCC_AddrOpt="$currCC_AddrOpt"
       currCC_AddrStr="$currCC_AddrStr ${GRNct}${currCC_AddrOpt}${CLRct}"
   fi
   currCC_AddrStr="$(echo "$currCC_AddrStr" | sed 's/%/%%/g')"

   userInput=""
   minCharLen=10
   maxCharLen=64
   doReturnToMenu=false
   doClearSetting=false

   while true
   do
       printf "\nEnter a secondary email address to receive email notifications.\n"
       if [ -z "$currCC_AddrOpt" ]
       then printf "[${menuExitStr}]\n"
       else printf "[${menuExitStr}] [${clearOptStr}]\n"
       fi
       printf "[${currCC_AddrStr}]:  "
       read -r userInput

       [ -z "$userInput" ] && break

       if printf '%s\n' "$userInput" | grep -qE '^(e|exit|Exit)$'
       then doReturnToMenu=true ; break ; fi

       if printf '%s\n' "$userInput" | grep -qE '^(C|c)$'
       then doClearSetting=true ; break ; fi

       if ! printf '%s\n' "$userInput" | grep -qE '.+[@].+'
       then
           printf "\n${REDct}INVALID input.${CLRct}\n"
           printf "Ampersand character [${GRNct}@${CLRct}] was NOT found, or it's found at the wrong place.\n"
           _PressAnyKey_ ; echo
           continue
       fi

       # Catch invalid chars that may cause parsing errors #
       if printf '%s\n' "$userInput" | grep -qE "$invalidChars"
       then
           printf "\n${REDct}INVALID input.${CLRct}\n"
           printf "One or more invalid characters were found.\n"
           _PressAnyKey_ ; echo
           continue
       fi

       curCharLen="${#userInput}"
       if [ "$curCharLen" -lt "$minCharLen" ] || [ "$curCharLen" -gt "$maxCharLen" ]
       then
           printf "\n${REDct}INVALID input length${CLRct} "
           printf "[Minimum=${GRNct}${minCharLen}${CLRct}, Maximum=${GRNct}${maxCharLen}${CLRct}]\n"
           _PressAnyKey_ ; echo
           continue
       fi

       nextCC_AddrOpt="$userInput"
       break
   done

   if "$doReturnToMenu" || \
      { [ -z "$nextCC_AddrOpt" ] && [ -z "$currCC_AddrOpt" ] ; }
   then return 0 ; fi   ##NO Change##

   if "$doClearSetting" || \
      { [ -z "$nextCC_AddrOpt" ] && [ -n "$currCC_AddrOpt" ] ; }
   then
       _SetScriptConfigOption_ 'emailCCName' TBD
       _SetScriptConfigOption_ 'emailCCEmail' TBD
       printf "\nThe secondary email address and associated name/alias were removed successfully.\n"
       _PressAnyKey_
       return 0
   fi

   if [ -z "$currCC_NameOpt" ] || [ "$currCC_NameOpt" = "TBD" ]
   then
       currCC_NameOpt=""
       nextCC_NameOpt="${nextCC_AddrOpt%%@*}"
       currCC_NameStr="$currCC_NameStr ${GRNct}${nextCC_NameOpt}${CLRct}"
   else
       nextCC_NameOpt="$currCC_NameOpt"
       currCC_NameStr="$currCC_NameStr ${GRNct}${currCC_NameOpt}${CLRct}"
   fi
   currCC_NameStr="$(echo "$currCC_NameStr" | sed 's/%/%%/g')"

   userInput=""
   minCharLen=6
   maxCharLen=64
   doReturnToMenu=false

   while true
   do
       printf "\nEnter a name or alias for the secondary email address.\n"
       printf "[${menuExitStr}]\n[${currCC_NameStr}]:  "
       read -r userInput

       if [ -z "$userInput" ] || \
          printf '%s\n' "$userInput" | grep -qE '^(e|exit|Exit)$'
       then doReturnToMenu=true ; break ; fi

       # Catch invalid chars that may cause parsing errors #
       if printf '%s\n' "$userInput" | grep -qE "$invalidChars"
       then
           printf "\n${REDct}INVALID input.${CLRct}\n"
           printf "One or more invalid characters were found.\n"
           _PressAnyKey_ ; echo
           continue
       fi

       curCharLen="${#userInput}"
       if [ "$curCharLen" -lt "$minCharLen" ] || [ "$curCharLen" -gt "$maxCharLen" ]
       then
           printf "\n${REDct}INVALID input length${CLRct} "
           printf "[Minimum=${GRNct}${minCharLen}${CLRct}, Maximum=${GRNct}${maxCharLen}${CLRct}]\n"
           _PressAnyKey_ ; echo
           continue
       fi

       nextCC_NameOpt="$userInput"
       break;
   done

   if [ "$nextCC_NameOpt" = "$currCC_NameOpt" ] && \
      [ "$nextCC_AddrOpt" = "$currCC_AddrOpt" ]
   then
       printf "\nThe secondary email address and associated name/alias remain unchanged.\n"
   else
       _SetScriptConfigOption_ 'emailCCName' "$nextCC_NameOpt"
       _SetScriptConfigOption_ 'emailCCEmail' "$nextCC_AddrOpt"
       printf "\nThe secondary email address and associated name/alias were updated successfully.\n"
   fi
   _PressAnyKey_
   return 0
}

#-----------------------------------------------------------#
_ConfigurationOptionsMenu_()
{
    local menuSelection=""
    local statusSTR  numberCT  optionCT  configOptsUpdated=false

    . "$SCRIPT_CONFIG_FPATH"

	while true
	do
		_ShowMenuHeader_
        printf "     ${BOLDUNDERLN}${GRNct}Configuration Options${CLRct}\n"

        _CheckEmailConfigFileFromAMTM_ -check -quiet
        if "$isEmailConfigEnabledInAMTM"
        then numberCT="$GRNct" ; optionCT=' '
        else numberCT="$GRAYEDct" ; optionCT="$GRAYEDct "
        fi

        printf "\n ${numberCT} 1${CLRct}.${optionCT}Toggle Email Format Type ${CLRct}\n"
        if "$isEmailConfigEnabledInAMTM"
        then
            if "$cemIsFormatHTML"
            then statusSTR="${GRNct}HTML"
            else statusSTR="${MGNTct}Plain Text"
            fi
            printf "     [Current Format: ${statusSTR}${CLRct}]\n"
        fi

        printf "\n ${numberCT} 2${CLRct}.${optionCT}Set Email Secondary Address ${CLRct}\n"
        if "$isEmailConfigEnabledInAMTM"
        then
            if [ -n "$emailCCName" ] && [ "$emailCCName" != 'TBD' ] && \
               [ -n "$emailCCEmail" ] && [ "$emailCCEmail" != 'TBD' ]
            then
			    printf "     [Current Name/Alias: ${GRNct}%s${CLRct}]\n" "$emailCCName"
			    printf "     [Current 2nd Address: ${GRNct}%s${CLRct}]\n" "$emailCCEmail"
            else
			    printf "     [Currently ${YLWct}NONE${CLRct}]\n"
            fi
        fi

        printf "\n ${numberCT} 3${CLRct}.${optionCT}Test email notification setup ${CLRct}\n"

		printf "\n  ${GRNct}e${CLRct}. Back to Main Menu\n\n"
		printf " Enter selection: "
		read -r menuSelection

		case "$menuSelection" in
			1)
				if "$isEmailConfigEnabledInAMTM"
				then _ToggleEmailFormatType_
				else _InvalidEmailOptionHandler_
				fi
				;;
			2)
				if "$isEmailConfigEnabledInAMTM"
				then
                    _SetSecondaryEmailAddress_
                    emailCCName="$(_GetScriptConfigOption_ 'emailCCName')"
                    emailCCEmail="$(_GetScriptConfigOption_ 'emailCCEmail')"
				else
                    _InvalidEmailOptionHandler_
				fi
				;;
			3)
				if "$isEmailConfigEnabledInAMTM"
				then
                    _Send_Email_TEST_
                    _PressAnyKey_
				else
                    _InvalidEmailOptionHandler_
				fi
				;;
			[Ee]) break ;;
			*)
                _InvalidMenuOptionHandler_
				;;
		esac
    done
}

#-----------------------------------------------------------#
_MainMenuHandling_()
{
   local menuSelection=""  branchSwitchStr  installedOK
   local scriptFilePath="$1"

   if _CheckScriptInstallation_ -quiet
   then installedOK=true
   else installedOK=false
   fi

   while true
   do
       _ShowMenuHeader_
       printf "      ${BOLDUNDERLN}${GRNct}Main Menu${CLRct}\n\n"

       if [ "$SCRIPT_BRANCH" = 'master' ]
       then branchSwitchStr="${MGNTct}development"
       else branchSwitchStr="${GRNct}stable/production"
       fi

       printf "   ${GRNct}1${CLRct}. Install/reinstall script\n"
       if "$installedOK"
       then
           printf "   ${GRNct}2${CLRct}. Check for available updates\n"
           printf "   ${GRNct}3${CLRct}. Force update to the latest version\n\n"
           printf "  ${GRNct}sw${CLRct}. Switch to the ${branchSwitchStr}${CLRct} version\n\n"
           printf "  ${GRNct}cf${CLRct}. Script configuration options\n"
           
       fi
       printf "\n  ${GRNct}un${CLRct}. Uninstall script\n"
       printf "\n   ${GRNct}e${CLRct}. Exit\n\n"
       printf " Enter selection: "
       read -r menuSelection

       case "$menuSelection" in
           1) if _ScriptInstallation_ "$scriptFilePath" -quiet
              then _PressAnyKey_
              fi
              if [ -f "$theScriptSLink" ]
              then
                  exec "$theScriptSLink"
                  exit 0
              fi
              ;;
          un) if ! _ConfirmYESorNO_ "\n Do you wish to continue with the uninstallation?"
			  then continue
			  fi
              _ScriptUninstallation_ "$scriptFilePath"
              exit 0
              ;;
          [Ee]) break ;;
       esac

       if ! "$installedOK"
       then
           _InvalidMenuOptionHandler_
           continue
       fi

       case "$menuSelection" in
           2)
              _DoScriptUpdate_ -check
              _PressAnyKey_
              exec "$theScriptSLink"
              exit 0
              ;;
           3) echo
              _DoScriptUpdate_ -force
              _PressAnyKey_
			  exec "$theScriptSLink"
              exit 0
			  ;;
          sw) echo
              if [ "$SCRIPT_BRANCH" = 'develop' ]
              then _SwitchToStableBranch_
              else _SwitchToDevelopBranch_
              fi
              _PressAnyKey_
              exec "$theScriptSLink"
              exit 0
              ;;
          cf) _ConfigurationOptionsMenu_
              ;;
           *) _InvalidMenuOptionHandler_
              ;;
       esac
   done
}

#-----------------------------------------------------------#
quietARG=""
showUsage=false
usageLong=false

if [ $# -eq 0 ] || [ -z "$1" ]
then
    _MainMenuHandling_ "$0"
    exit 0
fi

if printf '%s\n' "$1" | grep -qE '^[-]?help$'
then
    showUsage=true ; usageLong=true
elif ! _CheckValidParams_ "$1"
then
    _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: INVALID argument [${REDct}${1}${CLRct}] was provided.\n"
    showUsage=true ; _PressAnyKey_
fi

if "$showUsage"
then
    if "$usageLong"
    then _ShowUsageVerbose_
    else _ShowUsageConcise_
    fi
    exit 0
fi

case "$1" in
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
    -stable)
        _SwitchToStableBranch_
        exit 0
        ;;
    -develop)
        _SwitchToDevelopBranch_
        exit 0
        ;;
    -showconf)
        _ShowConfigDefaultsFile_
        exit 0
        ;;
    amtmupdate)
        shift
        _DoScriptUpdateFromAMTM_ "$@"
        exit "$?"
        ;;
     *) ##CONTINUE##
        ;;
esac

if ! _CheckScriptInstallation_
then exit 1
fi
. "$SCRIPT_CONFIG_FPATH"

theListOfARGs=""

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
         elif echo "$PARAM" | grep -qE '^-Title=.+'
         then
             emailBodyTitle="${PARAM##*=}"
         elif echo "$PARAM" | grep -qE '^-CCName=.+'
         then
             emailCCName="${PARAM##*=}"
         elif echo "$PARAM" | grep -qE '^-CCEmail=.+'
         then
             emailCCEmail="${PARAM##*=}"
         else
             theListOfARGs="${theListOfARGs:+$theListOfARGs} '$PARAM'"
         fi
         shift
         ;;
   esac
done

if [ -z "$theListOfARGs" ]
then
    _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: INSUFFICIENT number of arguments.\n"
    _PressAnyKey_ ; _ShowUsageConcise_
    exit 1
fi
eval set -- "$theListOfARGs"

if [ "$1" = "-checkupdate" ] || \
   [ "$1" = "-forceupdate" ] || \
   [ ! -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ]
then
    if [ -z "${cemIsVerboseMode:+xSETx}" ]
    then cemIsVerboseMode=true
    fi
    updateType=""
    if [ "$1" = "-forceupdate" ]
    then updateType="-force"
    else updateType="-check"
    fi
    _DoScriptUpdate_ "$updateType"

    if [ "$1" = "-checkupdate" ] || \
       [ "$1" = "-forceupdate" ]
    then exit 0
    fi
fi

! _CheckEmailConfigFileFromAMTM_ -check && exit 1

if [ "$1" = "-test" ]
then
    shift
    _Send_Email_TEST_ "$@"
    exit "$?"
fi

if [  $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
then
    _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: INSUFFICIENT number of arguments.\n"
    _PressAnyKey_ ; _ShowUsageConcise_
    exit 1
fi

. "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

_Send_EMail_Msg_ "$@"
exit "$?"

#EOF#
