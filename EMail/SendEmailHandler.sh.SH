#!/bin/sh
####################################################################
# SendEmailHandler.sh
#
# To send email notifications from any shell script using
# the shared custom email library script:
# "/jffs/addons/shared-libs/CustomEMailFunctions.lib.sh"
#
# IMPORTANT NOTE:
# Variables with the "cem" or "CEM" prefix are reserved for
# the shared custom email library. You can modify the values
# but do *NOT* change the variable names.
#
# Creation Date: 2026-Feb-19 [Martinski W.]
# Last Modified: 2026-Aug-30 [Martinski W.]
####################################################################
set -u

readonly SCRIPT_VERSION="0.5.0"
readonly SCRIPT_VERSTAG="26083023"
readonly SCRIPT_FNAME="SendEmailHandler.sh"

# Give FIRST priority to built-in binaries over any other #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

readonly scriptDirPath="$(/usr/bin/dirname "$0")"
readonly scriptFileName="${0##*/}"
readonly scriptFNameTag="${scriptFileName%.*}"

## The shared custom email library script to support email notifications ##
readonly ADDONS_SHARED_LIBS_DIR_PATH="/jffs/addons/shared-libs"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FNAME="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FPATH="${ADDONS_SHARED_LIBS_DIR_PATH}/$CUSTOM_EMAIL_LIB_SCRIPT_FNAME"

readonly CEM_LIB_BRANCH="master"
readonly CEM_LIB_GH_URL2="https://raw.githubusercontent.com/MartinSkyW/CustomMiscUtils/${CEM_LIB_BRANCH}/EMail"
readonly CEM_LIB_GH_URL1="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${CEM_LIB_BRANCH}/EMail"

readonly TEMP_DIR="/tmp/var/tmp"
readonly curlHTTPstatusStr="HTTP/S_Status_Code"
readonly curlTmpLogFile="${TEMP_DIR}/tmpCurl_${scriptFNameTag}_$$.TMP.LOG"
readonly curlErrLogFile="${TEMP_DIR}/tmpCurl_${scriptFNameTag}_$$.ERR.LOG"

readonly CLRct="\e[0m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly YLWct="\e[1;33m"
readonly MGNTct="\e[1;35m"

if [ -t 0 ] && ! tty | grep -qwi "NOT"
then readonly isInteractiveMode=true
else readonly isInteractiveMode=false
fi

#-----------------------------------------------------------#
_ShowUsage_()
{
   ! "$isInteractiveMode" && return 0
   cat <<EOF
----------------------------------------------------------------------------
SYNTAX:

To get this usage and syntax description:

   ./$scriptFileName -help

To check for and install the latest script version update: 

   ./$scriptFileName -checkupdate

To test and check if the email notification setup is working:

   ./$scriptFileName -emtest "FROM_NAME" "EMAIL_SUBJECT"

   EXAMPLE CODE:

   ./$scriptFileName -emtest "TheSenderID" "TESTING Email"

To send an email notification:

   ./$scriptFileName -emsend "FROM_NAME" "EMAIL_SUBJECT" "EMAIL_BODY_FILE_PATH" "EMAIL_BODY_TITLE"

   EXAMPLE CODE:

   echo "This is a TEST email notification." > ${TEMP_DIR}/theEmailBody.txt

   ./$scriptFileName -emsend "TheSenderID" "TESTING Email" "${TEMP_DIR}/theEmailBody.txt" "Testing Email Notification"

----------------------------------------------------------------------------
EOF
}

#-----------------------------------------------------------------------#
_PrintMsg_()
{ "$isInteractiveMode" && printf "$1" ; }

#-----------------------------------------------------------#
_DownloadScriptFile_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1
   fi
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR
   local theSrceFPath="${1}/$2"  theDestFName="$2"  theDestFPath="$3"
   local theTempFPathDL="${3}.DL.TMP"

   rm -f "$theTempFPathDL"
   printf '' > "$curlErrLogFile"
   printf '' > "$curlTmpLogFile"

   /usr/sbin/curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${curlHTTPstatusStr}: %{http_code}\n" --stderr "$curlErrLogFile" \
   "$theSrceFPath" --output "$theTempFPathDL" >> "$curlTmpLogFile"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="[Curl Status Code: $curlRetCode]"
   httpStatusSTR="$(grep -oE "${curlHTTPstatusStr}: [4-5][0-9]{2,}" "$curlTmpLogFile")"

   if [ "$curlRetCode" -eq 0 ] && \
      [ -z "$httpStatusSTR" ] && [ -s "$theTempFPathDL" ]
   then
       mv -f "$theTempFPathDL" "$theDestFPath"
       dos2unix "$theDestFPath" ; chmod 644 "$theDestFPath"
   else
       if [ "$curlRetCode" -eq 0 ] && [ -n "$httpStatusSTR" ]
       then
           statusCODE="$(echo "$httpStatusSTR" | awk -F' ' '{print $2}')"
           statusSTRx="[HTTP/S Status Code: $statusCODE]"
       fi
       if [ "$4" -eq "$urlDLMax" ] || "$isVerboseMode" || "$doDL_ShowErrorMsgs"
       then
           if [ -s "$curlErrLogFile" ]
           then echo ; cat "$curlErrLogFile"
           fi
           _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Unable to download the script file [$theDestFName]"
           _PrintMsg_ "\n${MGNTct}${statusSTRx}${CLRct}\n"
           [ "$4" -lt "$urlDLMax" ] && \
           _PrintMsg_ "\nTrying again with a different URL...\n"
       fi
       rm -f "$theTempFPathDL"
   fi

   rm -f "$curlErrLogFile" "$curlTmpLogFile"
   return "$statusCODE"
}

#-----------------------------------------------------------#
_DownloadCustomEmailLibraryScript_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE "^(-update|-install)$"
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
   local isVerboseMode="$cemIsVerboseMode"

   case "$1" in
        -update) actionStr1="Updating" ; actionStr2="updated" ;;
       -install) actionStr1="Installing" ; actionStr2="installed" ;;
   esac

   "$isVerboseMode" && \
   _PrintMsg_ "\n${actionStr1} the shared email library script file to support email notifications...\n"

   retCode=1 ; urlDLCount=0 ; urlDLMax=2
   for theScriptURL in "$CEM_LIB_GH_URL1" "$CEM_LIB_GH_URL2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadScriptFile_ "$theScriptURL" "$CUSTOM_EMAIL_LIB_SCRIPT_FNAME" "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" "$urlDLCount"
       then
           . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"
           chmod 755 "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"
           if "$isVerboseMode" || { [ "$urlDLCount" -gt 1 ] && "$doDL_ShowErrorMsgs" ; }
           then
               [ "$urlDLCount" -gt 1 ] && echo
               _PrintMsg_ "The shared email library script file [$CUSTOM_EMAIL_LIB_SCRIPT_FNAME] was ${actionStr2}.\n"
           fi
           retCode=0
           break
       fi
   done
   return "$retCode"
}

#-----------------------------------------------------------#
_CheckScriptVersionUpdate_()
{
   local dlVersionStr  dlVersTagStr  scriptMD5  dlTempMD5
   local scriptVerNum  dlFileVerNum  isVerboseMode=true
   local theScriptFPath="${scriptDirPath}/$SCRIPT_FNAME"
   local theTmpFilePath="${TEMP_DIR}/${SCRIPT_FNAME}.$$.TMP.SH"
   local retCode  urlDLCount  urlDLMax  doDL_ShowErrorMsgs=true

   _VersionStrToNum_()
   {
      if [ $# -eq 0 ] || [ -z "$1" ] ; then echo 0 ; return 1 ; fi
      local verNum  verStr

      verStr="$(echo "$1" | sed "s/['\"]//g")"
      verNum="$(echo "$verStr" | awk -F '.' '{printf ("%d%02d%02d\n", $1,$2,$3);}')"
      verNum="$(echo "$verNum" | sed 's/^0*//')"
      echo "$verNum" ; return 0
   }

   mkdir -m 755 -p "$ADDONS_SHARED_LIBS_DIR_PATH"
   if [ ! -d "$ADDONS_SHARED_LIBS_DIR_PATH" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Directory path [$ADDONS_SHARED_LIBS_DIR_PATH] *NOT* found.\n"
       return 1
   fi

   if [ $# -gt 0 ] && echo "$1" | grep -qE "^(-quiet|-veryquiet)$"
   then isVerboseMode=false ; doDL_ShowErrorMsgs=false
   fi

   "$isVerboseMode" && \
   _PrintMsg_ "\nChecking for custom email script updates...\n"

   retCode=1 ;  urlDLCount=0 ;  urlDLMax=2
   for theScriptURL in "$CEM_LIB_GH_URL1" "$CEM_LIB_GH_URL2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadScriptFile_ "$theScriptURL" "$SCRIPT_FNAME" "$theTmpFilePath" "$urlDLCount"
       then
           retCode=0 ; break
       fi
   done

   if [ "$retCode" -ne 0 ] || [ ! -s "$theTmpFilePath" ]
   then return 1
   fi

   dlVersionStr="$(grep -E '^readonly SCRIPT_VERSION=' "$theTmpFilePath")"
   dlVersTagStr="$(grep -E '^readonly SCRIPT_VERSTAG=' "$theTmpFilePath")"
   if [ -z "$dlVersionStr" ] || [ -z "$dlVersTagStr" ]
   then
       _PrintMsg_ "\n${REDct}**ERROR**${CLRct}: Could NOT find the VERSION string.\n"
       rm -f "$theTmpFilePath"
       return 1
   fi

   dlTempMD5="$(md5sum "$theTmpFilePath" 2>/dev/null | awk -F' ' '{print $1}')"
   scriptMD5="$(md5sum "$theScriptFPath" 2>/dev/null | awk -F' ' '{print $1}')"
   dlVersionStr="$(echo "$dlVersionStr" | tr -d '"' | cut -d'=' -f2)"
   dlVersTagStr="$(echo "$dlVersTagStr" | tr -d '"' | cut -d'=' -f2)"
   dlFileVerNum="$(_VersionStrToNum_ "$dlVersionStr")"
   scriptVerNum="$(_VersionStrToNum_ "$SCRIPT_VERSION")"

   if [ "$scriptMD5" = "$dlTempMD5" ] || \
      [ "$dlFileVerNum" -lt "$scriptVerNum" ]
   then
       rm -f "$theTmpFilePath"
       _PrintMsg_ "\nYou have the latest script version [${GRNct}${SCRIPT_VERSION}_${SCRIPT_VERSTAG}${CLRct}] available.\n\n"
       return 0
   fi

   _PrintMsg_ "\nLatest script version update [${MGNTct}${dlVersionStr}_${dlVersTagStr}${CLRct}] available.\n"
   mv -f "$theTmpFilePath" "$theScriptFPath"
   chmod 755 "$theScriptFPath"
   _PrintMsg_ "\nScript has been updated to the latest version [${GRNct}${dlVersionStr}_${dlVersTagStr}${CLRct}].\n\n"
   return 0
}

#-----------------------------------------------------------#
_CheckCustomEmailLibraryScript_()
{
   local doDL_LibScriptMsge=""
   local doDL_LibScriptFlag=false
   local doDL_ShowErrorMsgs=true
   local retCode=0  quietArg=""  doUpdateCheck=false
   if [ -z "${cemIsVerboseMode:+xSETx}" ]
   then cemIsVerboseMode=true
   fi

   for PARAM in "$@"
   do
      case $PARAM in
          "-quiet")
              quietArg="$PARAM"
              cemIsVerboseMode=false
              ;;
          "-veryquiet")
              quietArg="$PARAM"
              cemIsVerboseMode=false
              doDL_ShowErrorMsgs=false
              ;;
          "-verbose")
              cemIsVerboseMode=true
              ;;
          "-versionCheck")
              doUpdateCheck=true
              ;;
          *) ;; #IGNORED#
      esac
   done

   if [ -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ]
   then
       . "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

       if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
          { "$doUpdateCheck" && \
            _CheckLibraryUpdates_CEM_ "$ADDONS_SHARED_LIBS_DIR_PATH" "$quietArg" ; }
       then
           retCode=1
           doDL_LibScriptFlag=true
           doDL_LibScriptMsge="-update"
       fi
   else
       retCode=1
       doDL_LibScriptFlag=true
       doDL_LibScriptMsge="-install"
   fi

   if "$doDL_LibScriptFlag"
   then
       _DownloadCustomEmailLibraryScript_ "$doDL_LibScriptMsge"
       retCode="$?"
   fi

   return "$retCode"
}

#-----------------------------------------------------------#
# ARG1: The email name/alias to be used as "FROM_NAME"
# ARG2: The email Subject string.
# ARG3: Full path of file containing the email Body text.
# ARG4: The email Body Title string [OPTIONAL].
#-----------------------------------------------------------#
_SendEMail_()
{
   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       logTag=""${0##*/}"_[$$]"
       logMsg="**ERROR**: Custom Email Library Script [$CUSTOM_EMAIL_LIB_SCRIPT_FNAME] is *NOT* loaded."
       printf "\n%s: %s\n\n" "$logTag" "$logMsg"
       /usr/bin/logger -t "$logTag" "$logMsg"
       return 1
   fi

   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then
       printf "\n**ERROR**: INSUFFICIENT email parameters\n"
       return 1
   fi

   if [ ! -s "$3" ]
   then
       printf "\n**ERROR**: Email body contents file [$3] NOT found.\n"
       return 1
   fi

   local retCode  emailBodyTitleStr=""

   if [ $# -gt 3 ] && [ -n "$4" ]
   then emailBodyTitleStr="$4"
   fi

   ## ONLY for DEBUG/TEST purposes set these to 'true' ##
   cemIsDebugMode=false     ## true OR false ##
   cemIsVerboseMode=true   ## true OR false ##

   FROM_NAME="$1"
   _SendEMailNotification_CEM_ "$2" "-F=$3" "$emailBodyTitleStr"
   retCode="$?"

   if [ "$retCode" -eq 0 ]
   then
       logTag="INFO:"
       logMsg="The email notification was sent successfully [$2]."
   else
       logTag="**ERROR**:"
       logMsg="Failure to send email notification [Error Code: $retCode][$2]."
   fi
   printf "\n${logTag} ${logMsg}\n"

   return "$retCode"
}

#-----------------------------------------------------------#
_Send_Email_TEST_()
{
    local emailFromStr="$1"
    local emailSubject="$2"
    local emailBodyTitle="$3"
    local emailBodyFPath="/${TEMP_DIR}/tmpEMailBody_${scriptFNameTag}_$$.TXT"

    {
       printf "\nThis is a TEST to check & verify if sending email notifications"
       printf " is working well using the \"<b>${scriptFNameTag}</b>\" shell script.\n\n"
    } > "$emailBodyFPath"

    _SendEMail_ "$emailFromStr" "$emailSubject" "$emailBodyFPath" "$emailBodyTitle"

    rm -f "$emailBodyFPath"
    return 0
}

if [ $# -eq 0 ] || [ -z "$1" ] || [ "$1" = "-help" ] || \
   ! echo "$1" | grep -qE "^(-emsend|-emtest|-checkupdate)$"
then
    { [ $# -eq 0 ] || [ "$1" != "-help" ] ; } && \
    printf "\nNO valid arguments were provided.\n\n"
    _ShowUsage_
    exit 1
fi

if [ "$1" = "-checkupdate" ] || \
   [ ! -s "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH" ]
then
    _CheckScriptVersionUpdate_ -verbose
    _CheckCustomEmailLibraryScript_ -versionCheck -verbose
    [ "$1" = "-checkupdate" ] && exit 0
fi

. "$CUSTOM_EMAIL_LIB_SCRIPT_FPATH"

if [ "$1" = "-emtest" ]
then
    emailSenderIDx="Email_TEST"
    emailSubjectSTR="TESTING Email"
    emailBodyTITLE="Testing Email Notification"

    if [ $# -gt 1 ] && [ -n "$2" ]
    then emailSenderIDx="$2"
    fi
    if [ $# -gt 2 ] && [ -n "$3" ]
    then emailSubjectSTR="$3"
    fi
    if [ $# -gt 3 ] && [ -n "$4" ]
    then emailBodyTITLE="$4"
    fi
    _Send_Email_TEST_ "$emailSenderIDx" "$emailSubjectSTR" "$emailBodyTITLE"
#
elif [ "$1" = "-emsend" ]
then
    if [  $# -lt 5 ] || [ -z "$2" ] || \
       [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]
    then
        printf "\nINSUFFICIENT number of arguments.\n\n"
        _ShowUsage_
    else
        shift
        _SendEMail_ "$@"
    fi
fi

exit 0

#EOF#
