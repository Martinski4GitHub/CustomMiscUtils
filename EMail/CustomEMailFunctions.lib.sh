#!/bin/sh
######################################################################
# FILENAME: CustomEMailFunctions.lib.sh
# TAG: _LIB_CustomEMailFunctions_SHELL_
#
# Custom miscellaneous definitions and functions to send
# email notifications using AMTM email configuration file.
#---------------------------------------------------------------------
# Original Author: Martinski W.
# Creation Date: 2020-Jun-11 [Martinski W.]
# Last Modified: 2026-Sep-14 [Martinski W.]
######################################################################

if [ -z "${_LIB_CustomEMailFunctions_SHELL_:+xSETx}" ]
then _LIB_CustomEMailFunctions_SHELL_=0
else return 0
fi

CEM_LIB_VERSION="1.0.1"
CEM_LIB_VERSTAG="26091400"

CEM_LIB_REPO_BRANCH="develop"   ##**SET to "master" for RELEASE**##
CEM_LIB_REPO_URL_BASE2="https://raw.githubusercontent.com/MartinSkyW/CustomMiscUtils"
CEM_LIB_REPO_URL_BASE1="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils"
CEM_LIB_SCRIPT_GH_URL1="${CEM_LIB_REPO_URL_BASE1}/${CEM_LIB_REPO_BRANCH}/EMail"
CEM_LIB_SCRIPT_GH_URL2="${CEM_LIB_REPO_URL_BASE2}/${CEM_LIB_REPO_BRANCH}/EMail"

CEM_TEMP_DIR="/tmp/var/tmp"
CEM_ADDONS_DIR="/jffs/addons"

if [ -z "${cemIsVerboseMode:+xSETx}" ]
then cemIsVerboseMode=true ; fi

if [ -z "${cemIsFormatHTML:+xSETx}" ]
then cemIsFormatHTML=true ; fi

if [ -z "${cemIsDebugMode:+xSETx}" ]
then cemIsDebugMode=false ; fi

if [ -z "${cemDoSystemLog:+xSETx}" ]
then cemDoSystemLog=true ; fi

## Set to 'false' for DEBUG only ##
if [ -z "${cemDeleteMailContentFile:+xSETx}" ]
then cemDeleteMailContentFile=true ; fi

cemScriptDirPath="$(/usr/bin/dirname "$0")"
cemScriptFileName="${0##*/}"
cemScriptFNameTag="${cemScriptFileName%.*}"

# The shared Custom Email Library Script #
cemAddOnsSharedLibsDirPath="${CEM_ADDONS_DIR}/shared-libs"
cemCustomEmailLibScriptFName="CustomEMailFunctions.lib.sh"
cemCustomEmailLibScriptFPath="${cemAddOnsSharedLibsDirPath}/$cemCustomEmailLibScriptFName"

cemHTTPstatusStr="HTTP_Status_Code"
cemTmpCurlLogFile="${CEM_TEMP_DIR}/tmpEMail_${cemScriptFNameTag}_$$.TMP.LOG"
cemErrCurlLogFile="${CEM_TEMP_DIR}/tmpEMail_${cemScriptFNameTag}_$$.ERR.LOG"
cemTmpEMailContent="${CEM_TEMP_DIR}/tmpEMailContent_${cemScriptFNameTag}_$$.TXT"
cemDateTimeFormat="%Y-%b-%d %a %I:%M:%S %p %Z"

cemNvramInitUSleep=10
cemNvramWaitUSleep=50
cemNvramWaitFactor=20000
cemNvramWaitSecMAX=2
cemNvramWaitCntMAX="$((cemNvramWaitSecMAX * cemNvramWaitFactor))"
cemNvramValTmpFPath="${CEM_TEMP_DIR}/nvramValue_${cemScriptFNameTag}_$$.TMP.TXT"

cemSysLogALERT=1
cemSysLogCRITC=2
cemSysLogERROR=3
cemSysLogWARNG=4
cemSysLogNOTIC=5
cemSysLogINFOR=6
cemSysLogger="$(which logger)"
cemLogTagStr="${cemScriptFNameTag}_[$$]"
cemLogPrioNum="$cemSysLogNOTIC"

cemCLRct="\e[0m"
cemREDct="\e[1;31m"
cemGRNct="\e[1;32m"
cemYLWct="\e[1;33m"
cemMGNTct="\e[1;35m"

if [ -t 0 ] && ! tty | grep -qwi 'NOT'
then
    cemIsInteractive=true
else
    cemIsInteractive=false
    cemIsVerboseMode=false
fi

# AMTM Email Configuration file with user-defined settings #
amtmEMailDirPathCEM="${CEM_ADDONS_DIR}/amtm/mail"
amtmEMailConfFileCEM="${amtmEMailDirPathCEM}/email.conf"
amtmEMailPswdFileCEM="${amtmEMailDirPathCEM}/emailpw.enc"
amtmIsEMailConfigFileEnabled=false

#------------------------------------#
# AMTM Email Configuration variables #
#------------------------------------#
FROM_NAME=""  FROM_ADDRESS=""
TO_NAME=""  TO_ADDRESS=""
USERNAME=""  SMTP=""  PORT=""  PROTOCOL=""
PASSWORD=""  emailPwEnc=""

# Custom options from Email Library Script #
CC_NAME=""  CC_ADDRESS=""

#-----------------------------------------------------------#
_DoReInit_CEM_()
{
   unset amtmIsEMailConfigFileEnabled \
         _LIB_CustomEMailFunctions_SHELL_
}

#-----------------------------------------------------------#
_PrintMsg_CEM_()
{ "$cemIsInteractive" && printf "$1" ; }

#-----------------------------------------------------------#
_LogMsg_CEM_()
{
   if [ $# -lt 1 ] || [ -z "$1" ]
   then return 1
   fi
   if [ $# -gt 1 ] && [ -n "$2" ] && \
      echo "$2" | grep -qE '^[1-6]$'
   then cemLogPrioNum="$2"
   else cemLogPrioNum="$cemSysLogNOTIC"
   fi

   if "$cemIsInteractive" && "$cemIsVerboseMode" && \
      { [ $# -lt 3 ] || [ "$3" != "NOECHO" ] ; }
   then
       if [ "$cemLogPrioNum" -gt "$cemSysLogWARNG" ]
       then printf "${1}\n"
       elif [ "$cemLogPrioNum" -eq "$cemSysLogWARNG" ]
       then printf "${cemYLWct}${1}${cemCLRct}\n"
       else printf "${cemREDct}${1}${cemCLRct}\n"
       fi
   fi
   if "$cemDoSystemLog"
   then $cemSysLogger -t "$cemLogTagStr" -p "$cemLogPrioNum" "$1"
   fi
}

#-----------------------------------------------------------#
_DOStoUNIX_CEM_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
   then return 1 ; fi
   if grep -q "$(printf '\r\n')" "$1" 2>/dev/null
   then dos2unix "$1" ; fi
}

#-----------------------------------------------------------#
_DownloadScriptFile_CEM_()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1
   fi
   local srcFilePathURL="${1}/$2"
   local tempFilePathDL="${CEM_TEMP_DIR}/${2}.DL.$$.TMP"
   local theDestFName="$2"  theDestFPath="$3"
   local theMsgStr  logMsgStr
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR

   rm -f "$tempFilePathDL"
   printf '' > "$cemErrCurlLogFile"
   printf '' > "$cemTmpCurlLogFile"

   /usr/sbin/curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${cemHTTPstatusStr}: %{http_code}\n" --stderr "$cemErrCurlLogFile" \
   "$srcFilePathURL" --output "$tempFilePathDL" >> "$cemTmpCurlLogFile"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${cemHTTPstatusStr}: [4-5][0-9]{2,}" "$cemTmpCurlLogFile")"

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
       theMsgStr="${cemREDct}**ERROR**${cemCLRct}: Unable to download the script file ${cemREDct}${theDestFName}${cemCLRct} [${cemMGNTct}${statusSTRx}${cemCLRct}]"
       _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR" NOECHO

       if [ "$4" -eq "$urlDLMax" ] || "$showAllMsgs" || "$showWarnings"
       then
           if [ -s "$cemErrCurlLogFile" ]
           then echo ; cat "$cemErrCurlLogFile"
           fi
           _PrintMsg_CEM_ "\n${theMsgStr}\n"
           [ "$4" -lt "$urlDLMax" ] && \
           _PrintMsg_CEM_ "\nTrying again with a different URL...\n"
       fi
       rm -f "$tempFilePathDL"
   fi

   rm -f "$cemErrCurlLogFile" "$cemTmpCurlLogFile"
   return "$statusCODE"
}

#-----------------------------------------------------------#
_CheckLibraryUpdates_CEM_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then
       _PrintMsg_CEM_ "\n**ERROR**: NO parameter given for directory path.\n"
       return 1
   fi

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
       echo "${cemGRNct}${1}${cemCLRct} [${cemGRNct}${2}${cemCLRct}]"
   }

   mkdir -m 755 -p "$cemAddOnsSharedLibsDirPath"
   if [ ! -d "$cemAddOnsSharedLibsDirPath" ]
   then
       _PrintMsg_CEM_ "\n${cemREDct}**ERROR**${cemCLRct}: Directory Path [$cemAddOnsSharedLibsDirPath] *NOT* found.\n"
       return 0
   fi

   local cemScriptFPath="$cemCustomEmailLibScriptFPath"
   local cemTmpFilePath="${CEM_TEMP_DIR}/${cemCustomEmailLibScriptFName}.$$.TMP.SH"
   local scriptVerNum  dlFileVerNum  theVerStr
   local retCode  urlDLCount  urlDLMax
   local dlVersionStr  dlVersTagStr  scriptMD5  dlTempMD5
   local showAllMsgs="$cemIsVerboseMode"  showWarnings=true

   if [ $# -gt 1 ]
   then
       if echo "$2" | grep -qE '^[-]?quiet$'
       then showAllMsgs=false
       elif [ "$2" = "-veryquiet" ]
       then showAllMsgs=false ; showWarnings=false
       fi
   fi

   "$showAllMsgs" && \
   _PrintMsg_CEM_ "\nChecking for shared email library script updates...\n"

   retCode=1 ; urlDLCount=0 ; urlDLMax=2
   for theScriptURL in "$CEM_LIB_SCRIPT_GH_URL1" "$CEM_LIB_SCRIPT_GH_URL2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadScriptFile_CEM_ "$theScriptURL" "$cemCustomEmailLibScriptFName" "$cemTmpFilePath" "$urlDLCount"
       then
           retCode=0 ; break
       fi
   done

   if [ "$retCode" -ne 0 ] || [ ! -s "$cemTmpFilePath" ]
   then return 1
   fi

   dlVersionStr="$(grep -E '^CEM_LIB_VERSION=' "$cemTmpFilePath" | tr -d '"')"
   dlVersTagStr="$(grep -E '^CEM_LIB_VERSTAG=' "$cemTmpFilePath" | tr -d '"')"

   if [ -z "$dlVersionStr" ] || [ -z "$dlVersTagStr" ]
   then
       _PrintMsg_ "\n${cemREDct}**ERROR**${cemCLRct}: Could NOT find the VERSION string.\n"
       rm -f "$cemTmpFilePath"
       return 1
   fi

   dlTempMD5="$(md5sum "$cemTmpFilePath" 2>/dev/null | awk -F' ' '{print $1}')"
   scriptMD5="$(md5sum "$cemScriptFPath" 2>/dev/null | awk -F' ' '{print $1}')"
   dlVersionStr="$(echo "$dlVersionStr" | sed -e 's/.*CEM_LIB_VERSION=//;s/ .*$//')"
   dlVersTagStr="$(echo "$dlVersTagStr" | sed -e 's/.*CEM_LIB_VERSTAG=//;s/ .*$//')"
   dlFileVerNum="$(_VersionStrToNum_ "$dlVersionStr")"
   scriptVerNum="$(_VersionStrToNum_ "$CEM_LIB_VERSION")"

   if [ "$scriptMD5" = "$dlTempMD5" ] || \
      [ "$dlFileVerNum" -lt "$scriptVerNum" ]
   then
       retCode=1
       if "$showAllMsgs"
       then
           theVerStr="$(_FormatVersionStr_ "$CEM_LIB_VERSION" "$CEM_LIB_VERSTAG")"
           _PrintMsg_CEM_ "You have the latest email library script version $theVerStr installed.\n\n"
       fi
   else
       retCode=0
       _DoReInit_CEM_
       if "$showAllMsgs"
       then
           theVerStr="$(_FormatVersionStr_ "$dlVersionStr" "$dlVersTagStr")"
           _PrintMsg_CEM_ "New shared email library script version $theVerStr is available.\n\n"
       fi
   fi

   rm -f "$cemTmpFilePath"
   return "$retCode"
}

#-----------------------------------------------------------#
_NVRAM_Get_()
{
   local nvramProcID  nvramProcOK=false  retCode=1
   local waitCountNUM=0  logMsgStr  nvramKeyValue=""

   printf '' > "$cemNvramValTmpFPath"
   nvram get "$1" > "$cemNvramValTmpFPath" &
   nvramProcID="$!"
   usleep "$cemNvramInitUSleep"

   while true
   do
       if ! kill -EXIT "$nvramProcID" 2>/dev/null
       then nvramProcOK=true ; break
       fi
       usleep "$cemNvramWaitUSleep"
       waitCountNUM="$((waitCountNUM + 1))"
       if [ "$waitCountNUM" -ge "$cemNvramWaitCntMAX" ]
       then break
       fi
   done

   if kill -EXIT "$nvramProcID" 2>/dev/null
   then
       retCode=555
       nvramProcOK=false
       kill -KILL "$nvramProcID" 2>/dev/null ; wait "$nvramProcID"
       logMsgStr="**ALERT**: Wait timeout [$cemNvramWaitSecMAX secs] for 'nvram get $1' command expired."
       _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR" NOECHO
   fi
   if "$nvramProcOK" && [ -s "$cemNvramValTmpFPath" ]
   then
       nvramKeyValue="$(cat "$cemNvramValTmpFPath")"
       retCode=0
   fi

   rm -f "$cemNvramValTmpFPath"
   echo "$nvramKeyValue"
   return "$retCode"
}

#-----------------------------------------------------------#
_GetRouterModelID_CEM_()
{
   local retCode=1  nvramKeyName  nvramKeyValue=""
   local nvramModelKeys="odmpid wps_modelnum model build_name"
   for nvramKeyName in $nvramModelKeys
   do
       nvramKeyValue="$(_NVRAM_Get_ "$nvramKeyName")"
       if [ -n "$nvramKeyValue" ]
       then retCode=0 && break
       fi
   done
   echo "$nvramKeyValue" ; return "$retCode"
}

#-----------------------------------------------------------#
_GetRouterUserNameID_CEM_()
{
   local nvramKeyValue=""
   nvramKeyValue="$(_NVRAM_Get_ http_username)"
   if [ -n "$nvramKeyValue" ]
   then echo "$nvramKeyValue" ; return 0
   fi
   echo "$cemScriptFNameTag" ; return 0
}

#-----------------------------------------------------------#
_CheckEMailConfigFileFromAMTM_CEM_()
{
   amtmIsEMailConfigFileEnabled=false

   if [ ! -s "$amtmEMailConfFileCEM" ]
   then
       _PrintMsg_CEM_ "\n**ERROR**: Unable to send email notifications."
       _PrintMsg_CEM_ "\nAMTM email configuration file is not yet set up.\n"
       return 1
   fi

   if [ ! -s "$amtmEMailPswdFileCEM" ] || [ -z "$emailPwEnc" ] || \
      [ "$PASSWORD" = "PUT YOUR PASSWORD HERE" ]
   then
       _PrintMsg_CEM_ "\n**ERROR**: Unable to send email notifications."
       _PrintMsg_CEM_ "\nThe AMTM email password has not been set up.\n"
       return 1
   fi

   if [ -z "$TO_NAME" ] || [ -z "$USERNAME" ] || \
      [ -z "$FROM_ADDRESS" ] || [ -z "$TO_ADDRESS" ] || \
      [ -z "$SMTP" ] || [ -z "$PORT" ] || [ -z "$PROTOCOL" ]
   then
       _PrintMsg_CEM_ "\n**ERROR**: Unable to send email notifications."
       _PrintMsg_CEM_ "\nSome AMTM email configuration variables are not yet set up.\n"
       return 1
   fi

   chmod 640 "$amtmEMailConfFileCEM" "$amtmEMailPswdFileCEM"
   amtmIsEMailConfigFileEnabled=true
   return 0
}

#-------------------------------------------------------#
# ARG1: Email Subject string.
# ARG2: Email Body message string or the full path of
#       a file containing the Email Body message.
# ARG3: Email Body Title string [OPTIONAL].
#-------------------------------------------------------#
_CreateEMailContent_CEM_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
    then return 1
    fi
    local emailBodyMsge  emailBodyFile  emailBodyTitle=""

    rm -f "$cemTmpEMailContent"

    if ! echo "$2" | grep -qE '^-F=.+'
    then
        emailBodyMsge="$2"
    else
        emailBodyFile="${2##*=}"
        emailBodyMsge="$(cat "$emailBodyFile")"
        rm -f "$emailBodyFile"
    fi

    [ $# -gt 2 ] && [ -n "$3" ] && emailBodyTitle="$3"

    if "$cemIsFormatHTML"
    then
        if [ -n "$emailBodyTitle" ]
        then
            ! echo "$emailBodyTitle" | grep -qE '^[<]h[1-5][>].*[<]/h[1-5][>]$' && \
            emailBodyTitle="<h2>${emailBodyTitle}</h2>"
        fi
    else
        emailBodyMsge="$(echo "$emailBodyMsge" | sed 's/[<]b[>]//g ; s/[<]\/b[>]//g')"
        emailBodyTitle="$(echo "$emailBodyTitle" | sed 's/[<]h[1-5][>]//g ; s/[<]\/h[1-5][>]//g')"
    fi

    if [ -n "$CC_NAME" ] && [ -n "$CC_ADDRESS" ]
    then
        CC_ADDRESS_ARG="--mail-rcpt $CC_ADDRESS"
        CC_ADDRESS_STR="\"${CC_NAME}\" <$CC_ADDRESS>"
    fi

    ## Header-1 ##
    cat <<EOF > "$cemTmpEMailContent"
From: "$FROM_NAME" <$FROM_ADDRESS>
To: "$TO_NAME" <$TO_ADDRESS>
EOF

    [ -n "$CC_ADDRESS_STR" ] && \
    printf "Cc: %s\n" "$CC_ADDRESS_STR" >> "$cemTmpEMailContent"

    ## Header-2 ##
    cat <<EOF >> "$cemTmpEMailContent"
Subject: $1
Date: $(date -R)
EOF

    if "$cemIsFormatHTML"
    then
        cat <<EOF >> "$cemTmpEMailContent"
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"
Content-Disposition: inline

<!DOCTYPE html><html>
<head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head>
<body>$emailBodyTitle
<div style="color:black; font-family: sans-serif; font-size:130%;"><pre>
EOF
    else
        cat <<EOF >> "$cemTmpEMailContent"
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable
Content-Disposition: inline

EOF
        [ -n "$emailBodyTitle" ] && \
        printf "%s\n\n" "$emailBodyTitle" >> "$cemTmpEMailContent"
    fi

    ## Body ##
    printf "%s\n" "$emailBodyMsge" >> "$cemTmpEMailContent"

    ## Footer ##
    if "$cemIsFormatHTML"
    then
        cat <<EOF >> "$cemTmpEMailContent"

Sent by the "<b>${cemScriptFileName}</b>" script.
From the "<b>${FRIENDLY_ROUTER_NAME}</b>" router.

$(date +"$cemDateTimeFormat")
</pre></div></body></html>
EOF
    else
        cat <<EOF >> "$cemTmpEMailContent"

Sent by the "${cemScriptFileName}" script.
From the "${FRIENDLY_ROUTER_NAME}" router.

$(date +"$cemDateTimeFormat")
EOF
    fi

    return 0
}

#-------------------------------------------------------#
# ARG1: Email Subject string.
# ARG2: Email Body message string or the full path of
#       a file containing the Email Body message.
# ARG3: Email Body Title string [OPTIONAL].
#-------------------------------------------------------#
_SendEMailNotification_CEM_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      ! _CheckEMailConfigFileFromAMTM_CEM_
   then return 1 ; fi

   local CC_ADDRESS_STR=""  CC_ADDRESS_ARG=""
   local theMsgStr  logMsgStr  logPrioNum  mailpwd
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR

   [ -z "$FROM_NAME" ] && FROM_NAME="$(_GetRouterUserNameID_CEM_)"
   [ -z "$FRIENDLY_ROUTER_NAME" ] && FRIENDLY_ROUTER_NAME="$(_GetRouterModelID_CEM_)"

   ! _CreateEMailContent_CEM_ "$@" && return 1

   if "$cemIsVerboseMode"
   then
       _PrintMsg_CEM_ "\nSending email notification [${cemGRNct}${1}${cemCLRct}]."
       _PrintMsg_CEM_ "\nPlease wait...\n"
   fi

   printf '' > "$cemErrCurlLogFile"
   printf '' > "$cemTmpCurlLogFile"

   mailpwd="$(/usr/sbin/openssl aes-256-cbc "$emailPwEnc" -d -in "$amtmEMailPswdFileCEM" -pass pass:ditbabot,isoi)"

   /usr/sbin/curl -vLSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${cemHTTPstatusStr}: %{http_code}\n" \
   --output /dev/null --stderr "$cemErrCurlLogFile" \
   --url "${PROTOCOL}://${SMTP}:${PORT}" \
   --mail-from "$FROM_ADDRESS" --mail-rcpt "$TO_ADDRESS" $CC_ADDRESS_ARG \
   --user "${USERNAME}:$mailpwd" --upload-file "$cemTmpEMailContent" \
   $SSL_FLAG --ssl-reqd --crlf >> "$cemTmpCurlLogFile"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${cemHTTPstatusStr}: [4-5][0-9]{2,}" "$cemTmpCurlLogFile")"

   if [ "$curlRetCode" -eq 0 ] && [ -z "$httpStatusSTR" ]
   then
       logPrioNum="$cemSysLogINFOR"
       logMsgStr="The email notification [$1] was sent successfully."
       theMsgStr="The email notification [${cemGRNct}${1}${cemCLRct}] was sent successfully.\n"
   else
       if [ "$curlRetCode" -eq 0 ] && [ -n "$httpStatusSTR" ]
       then
           statusCODE="$(echo "$httpStatusSTR" | awk -F' ' '{print $2}')"
           statusSTRx="HTTP Status Code: $statusCODE"
       fi
       logPrioNum="$cemSysLogERROR"
       logMsgStr="**ERROR**: Failure to send email notification [$1] [$statusSTRx]."
       theMsgStr="${cemREDct}**ERROR**${cemCLRct}: Failure to send email notification [${cemMGNTct}${1}${cemCLRct}] [${cemREDct}${statusSTRx}${cemCLRct}].\n\n"

       if [ -s "$cemErrCurlLogFile" ] && \
          "$cemIsInteractive" && "$cemIsVerboseMode" && "$cemIsDebugMode"
       then
           echo "======================================================="
           cat "$cemErrCurlLogFile"
           echo "======================================================="
       fi
   fi
   sleep 2
   mailpwd='' ; unset mailpwd

   if "$cemIsVerboseMode" || [ "$logPrioNum" = "$cemSysLogERROR" ]
   then _PrintMsg_CEM_ "$theMsgStr"
   fi
   _LogMsg_CEM_ "$logMsgStr" "$logPrioNum" NOECHO

   if "$cemDeleteMailContentFile"
   then rm -f "$cemTmpEMailContent"
   else mv -f "$cemTmpEMailContent" "${cemTmpEMailContent}.DEBUG"
   fi
   rm -f "$cemTmpCurlLogFile" "$cemErrCurlLogFile"

   return "$statusCODE"
}

if [ -s "$amtmEMailConfFileCEM" ]
then
    chmod 640 "$amtmEMailConfFileCEM"
    _DOStoUNIX_CEM_ "$amtmEMailConfFileCEM"
    . "$amtmEMailConfFileCEM"
fi

_LIB_CustomEMailFunctions_SHELL_=1

#EOF#
