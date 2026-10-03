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
# Last Modified: 2026-Oct-03 [Martinski W.]
######################################################################

if [ -z "${_LIB_CustomEMailFunctions_SHELL_:+xSETx}" ]
then _LIB_CustomEMailFunctions_SHELL_=0
else return 0
fi

CEM_LIB_VERSION="v1.1.0"
CEM_LIB_VERSTAG="26100308"

CEM_LIB_REPO_BRANCH="master"
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
cemPID="$(printf "%05d" "$$")"

# The shared Custom Email Library Script #
cemAddOnsSharedLibsDirPath="${CEM_ADDONS_DIR}/shared-libs"
cemCustomEmailLibScriptFName="CustomEMailFunctions.lib.sh"
cemCustomEmailLibScriptFPath="${cemAddOnsSharedLibsDirPath}/$cemCustomEmailLibScriptFName"

cemHTTPstatusStr="HTTP_Status_Code"
cemCurlTmpLogFPath="${CEM_TEMP_DIR}/tmpEMailCurl_${cemScriptFNameTag}_${cemPID}.TMP.LOG"
cemCurlErrLogFPath="${CEM_TEMP_DIR}/tmpEMailCurl_${cemScriptFNameTag}_${cemPID}.ERR.LOG"
cemTmpEMailContent="${CEM_TEMP_DIR}/tmpEMailBodyCont_${cemScriptFNameTag}_${cemPID}.TXT"
cemTmpEMailBodyMsg="${CEM_TEMP_DIR}/tmpEMailBodyMsge_${cemScriptFNameTag}_${cemPID}.MSG"
cemDateTimeFormat="%Y-%b-%d %a %I:%M:%S %p %Z"

cemNvramInitUSleep=10
cemNvramWaitUSleep=50
cemNvramWaitFactor=20000
cemNvramWaitSecMAX=2
cemNvramWaitCntMAX="$((cemNvramWaitSecMAX * cemNvramWaitFactor))"
cemNvramValTmpFPath="${CEM_TEMP_DIR}/cemNvramValue_${cemScriptFNameTag}_${cemPID}.TMP.TXT"

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
   local tempFilePathDL="${CEM_TEMP_DIR}/${2}.DL.${cemPID}.TMP"
   local theDestFName="$2"  theDestFPath="$3"
   local theMsgStr  logMsgStr
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR

   rm -f "$tempFilePathDL"
   printf '' > "$cemCurlErrLogFPath"
   printf '' > "$cemCurlTmpLogFPath"

   /usr/sbin/curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${cemHTTPstatusStr}: %{http_code}\n" --stderr "$cemCurlErrLogFPath" \
   "$srcFilePathURL" --output "$tempFilePathDL" >> "$cemCurlTmpLogFPath"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${cemHTTPstatusStr}: [4-5][0-9]{2,}" "$cemCurlTmpLogFPath")"

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
           if [ -s "$cemCurlErrLogFPath" ]
           then echo ; cat "$cemCurlErrLogFPath"
           fi
           _PrintMsg_CEM_ "\n${theMsgStr}\n"
           [ "$4" -lt "$urlDLMax" ] && \
           _PrintMsg_CEM_ "\nTrying again with a different URL...\n"
       fi
       rm -f "$tempFilePathDL"
   fi

   rm -f "$cemCurlErrLogFPath" "$cemCurlTmpLogFPath"
   return "$statusCODE"
}

#-----------------------------------------------------------#
_VersionStrToNum_CEM_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then echo 0 ; return 1
   fi
   local verNum  verStr

   verStr="$(echo "$1" | sed "s/[v'\"]//g")"
   verNum="$(echo "$verStr" | awk -F '.' '{printf ("%d%02d%02d\n", $1,$2,$3);}')"
   verNum="$(echo "$verNum" | sed 's/^0*//')"
   echo "$verNum" ; return 0
}

#-----------------------------------------------------------#
_FormatVersionStr_CEM_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then echo ; return 1
   fi
   echo "${cemGRNct}${1}${cemCLRct} [${cemGRNct}${2}${cemCLRct}]"
}

#-----------------------------------------------------------#
_CheckLibraryUpdates_CEM_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then
       _PrintMsg_CEM_ "\n**ERROR**: NO parameter given for directory path.\n"
       return 1
   fi

   mkdir -m 755 -p "$cemAddOnsSharedLibsDirPath"
   if [ ! -d "$cemAddOnsSharedLibsDirPath" ]
   then
       _PrintMsg_CEM_ "\n${cemREDct}**ERROR**${cemCLRct}: Directory Path [$cemAddOnsSharedLibsDirPath] *NOT* found.\n"
       return 0
   fi

   local cemScriptFPath="$cemCustomEmailLibScriptFPath"
   local cemTmpFilePath="${CEM_TEMP_DIR}/${cemCustomEmailLibScriptFName}.${cemPID}.TMP.SH"
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
   dlFileVerNum="$(_VersionStrToNum_CEM_ "$dlVersionStr")"
   scriptVerNum="$(_VersionStrToNum_CEM_ "$CEM_LIB_VERSION")"

   if [ "$scriptMD5" = "$dlTempMD5" ] || \
      [ "$dlFileVerNum" -lt "$scriptVerNum" ]
   then
       retCode=1
       if "$showAllMsgs"
       then
           theVerStr="$(_FormatVersionStr_CEM_ "$CEM_LIB_VERSION" "$CEM_LIB_VERSTAG")"
           _PrintMsg_CEM_ "You have the latest email library script version $theVerStr installed.\n\n"
       fi
   else
       retCode=0
       _DoReInit_CEM_
       if "$showAllMsgs"
       then
           theVerStr="$(_FormatVersionStr_CEM_ "$dlVersionStr" "$dlVersTagStr")"
           _PrintMsg_CEM_ "New shared email library script version $theVerStr is available.\n\n"
       fi
   fi

   rm -f "$cemTmpFilePath"
   return "$retCode"
}

#-----------------------------------------------------------#
_NVRAM_Get_CEM_()
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
       nvramKeyValue="$(_NVRAM_Get_CEM_ "$nvramKeyName")"
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
   nvramKeyValue="$(_NVRAM_Get_CEM_ http_username)"
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

#-----------------------------------------------------------#
_CheckValidParams_CEM_()
{
   if { ! printf '%s\n' "$1" | grep -qE '^[-].+' && \
        ! printf '%s\n' "$1" | grep -qE '^(File|Title|Attach)=.+' ; } || \
      printf '%s\n' "$1" | grep -qE '^-(File|Title|Attach)=.+'
   then return 0
   else return 1
   fi
}

#-----------------------------------------------------------------------#
_CheckMaxFileSize_CEM_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      [ ! -s "$1" ] || ! echo "$2" | grep -qE '^[1-9][0-9]?MB$'
   then return 1
   fi
   local theFileSize
   local maxFileSizeNum="$(echo "$2" | sed 's/MB//')"

   theFileSize="$(ls -1l "$1" | awk -F ' ' '{print $3}')"
   if [ "$theFileSize" -gt "$((maxFileSizeNum * 1024 * 1024))" ]
   then return 1
   else return 0
   fi
}

#-----------------------------------------------------------#
_GetEmailAttachmentType_CEM_()
{
    if [ $# -eq 0 ] || [ -z "$1" ]
    then return 1
    fi
    local retCode=0  theFileExt="${1##*.}"

    emailAttachFType=""
    case "$theFileExt" in
        txt|log|cfg|conf|sh|js|json|TXT|LOG|CFG)
            emailAttachFType='text/plain'
            ;;
        gif)
            emailAttachFType='image/gif'
            ;;
        png)
            emailAttachFType='image/png'
            ;;
        bmp)
            emailAttachFType='image/bmp'
            ;;
        jpg|jpeg)
            emailAttachFType='image/jpeg'
            ;;
        pdf)
            emailAttachFType='application/pdf'
            ;;
        zip)
            emailAttachFType='application/zip'
            ;;
        gzip)
            emailAttachFType='application/gzip'
            ;;
        tar)
            emailAttachFType='application/x-tar'
            ;;
        *) retCode=1
           logMsgStr="**ERROR**: UNKNOWN email file attachment type [$theFileExt]."
           _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
           ;;
    esac
    return "$retCode"
}

#-------------------------------------------------------#
# ARG1: Email Subject string.
# ARG2: Email Body message string or the full path of
#       the file containing the email message body.
# ARG3: Email Body Title string [OPTIONAL].
# ARG4: Full path of email file attachment [OPTIONAL].
#-------------------------------------------------------#
_CreateEMailContent_CEM_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
    then return 50
    fi
    local emailSubject="$1"  optionalARGs
    local emailBodyFile  emailBodyTitle=""
    local emailAttachFPath=""  emailAttachFName=""
    local emailAttachFType=""  emailAttachmentOK=false
    local emailMixedBoundary='MULTIPART-MIXED-BOUNDARY'

    if printf '%s\n' "$2" | grep -qE '^-(F|File)=.+'
    then
        emailBodyFile="${2##*=}"
        if [ ! -s "$emailBodyFile" ]
        then
            logMsgStr="**ERROR**: Email body file [$emailBodyFile] NOT found."
            _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
            return 51
        fi
        cp -fp "$emailBodyFile" "$cemTmpEMailBodyMsg"
        chmod 666 "$cemTmpEMailBodyMsg"
    else
        echo "$2" > "$cemTmpEMailBodyMsg"
    fi

    shift ; shift
    optionalARGs=""

    for PARAM in "$@"
    do
        if ! _CheckValidParams_CEM_ "$PARAM"
        then
            logMsgStr="**ERROR**: INVALID argument [${PARAM}] was provided."
            _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
            rm -f "$cemTmpEMailBodyMsg"
            return 52
        fi
        if printf '%s\n' "$PARAM" | grep -qE '^-Title=.+'
        then
            emailBodyTitle="${PARAM##*=}"
        elif printf '%s\n' "$PARAM" | grep -qE '^-Attach=.+'
        then
            emailAttachFPath="${PARAM##*=}"
            if [ ! -s "$emailAttachFPath" ]
            then
                logMsgStr="**ERROR**: Email file attachment [$emailAttachFPath] NOT found."
                _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
                rm -f "$cemTmpEMailBodyMsg"
                return 53
            fi
            emailAttachFName="${emailAttachFPath##*/}"
            if ! _GetEmailAttachmentType_CEM_ "$emailAttachFName"
            then
                rm -f "$cemTmpEMailBodyMsg"
                return 54
            fi
            if ! _CheckMaxFileSize_CEM_ "$emailAttachFPath" 10MB
            then
                logMsgStr="**ERROR**: Email file attachment [$emailAttachFPath] exceeds maximum file size [10MB]."
                _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
                rm -f "$cemTmpEMailBodyMsg"
                return 55
            fi
            emailAttachmentOK=true
        else
            optionalARGs="${optionalARGs:+$optionalARGs }'$PARAM'"
        fi
        shift
    done

    [ -n "$optionalARGs" ] && eval set -- "$optionalARGs"
    [ $# -gt 0 ] && [ -n "$1" ] && emailBodyTitle="$1"

    if "$emailAttachmentOK"
    then maxEmailBodySizeMB='5MB'
    else maxEmailBodySizeMB='8MB'
    fi
    if ! _CheckMaxFileSize_CEM_ "$cemTmpEMailBodyMsg" "$maxEmailBodySizeMB"
    then
        logMsgStr="**ERROR**: Email message body exceeds maximum size [$maxEmailBodySizeMB]."
        _LogMsg_CEM_ "$logMsgStr" "$cemSysLogERROR"
        rm -f "$cemTmpEMailBodyMsg"
        return 56
    fi

    if "$cemIsFormatHTML"
    then
        if [ -n "$emailBodyTitle" ]
        then
            ! echo "$emailBodyTitle" | grep -qE '^[<]h[1-5][>].*[<]/h[1-5][>]$' && \
            emailBodyTitle="<h2>${emailBodyTitle}</h2>"
        fi
    else
        sed -i 's/[<]b[>]//g ; s/[<]\/b[>]//g' "$cemTmpEMailBodyMsg"
        emailBodyTitle="$(echo "$emailBodyTitle" | sed 's/[<]h[1-5][>]//g ; s/[<]\/h[1-5][>]//g')"
    fi

    ## Header ##
    {
       echo "From: \"${FROM_NAME}\" <$FROM_ADDRESS>"
       echo "To: \"${TO_NAME}\" <$TO_ADDRESS>"
       [ -n "$CC_ADDRESS_OK" ] && \
       printf "Cc: \"${CC_NAME}\" <$CC_ADDRESS>\n"
       echo "Subject: $emailSubject"
       echo "Date: $(date -R)"
       echo "MIME-Version: 1.0"

       if "$emailAttachmentOK"
       then
           echo "Content-Type: multipart/mixed; boundary=\"${emailMixedBoundary}\""
           printf "\n--${emailMixedBoundary}\n"
       fi
    } > "$cemTmpEMailContent"

    ## Body ##
    if "$cemIsFormatHTML"
    then
        cat <<EOF >> "$cemTmpEMailContent"
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: 8bit
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
        printf "%s\n" "$emailBodyTitle" >> "$cemTmpEMailContent"
    fi

    ## Email Message Body ##
    cat "$cemTmpEMailBodyMsg" >> "$cemTmpEMailContent"

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

    if "$emailAttachmentOK"
    then
       {
          echo
          echo "--$emailMixedBoundary"
          echo "Content-Type: ${emailAttachFType}; name=\"$emailAttachFName\""
          echo "Content-Transfer-Encoding: base64"
          echo "Content-Disposition: attachment; filename=\"$emailAttachFName\""
          echo
          openssl base64 -A < "$emailAttachFPath"
          echo
          echo "--$emailMixedBoundary--"
       } >> "$cemTmpEMailContent" 
    fi

    rm -f "$cemTmpEMailBodyMsg"
    if [ -n "$emailBodyFile" ] && \
       echo "$emailBodyFile" | grep -qE '^/tmp/.+'
    then rm -f "$emailBodyFile"
    fi
    return 0
}

#-------------------------------------------------------#
# ARG1: Email Subject string.
# ARG2: Email Body message string or the full path of
#       the file containing the email message body.
# ARG3: Email Body Title string [OPTIONAL].
# ARG4: Full path of email file attachment [OPTIONAL].
#-------------------------------------------------------#
_SendEMailNotification_CEM_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      ! _CheckEMailConfigFileFromAMTM_CEM_
   then return 1 ; fi

   local retCode  CC_ADDRESS_OK=""
   local theMsgStr  logMsgStr  logPrioNum  mailpswd
   local curlRetCode  statusCODE  statusSTRx  httpStatusSTR

   [ -z "$FROM_NAME" ] && FROM_NAME="$(_GetRouterUserNameID_CEM_)"
   [ -z "$FRIENDLY_ROUTER_NAME" ] && FRIENDLY_ROUTER_NAME="$(_GetRouterModelID_CEM_)"

   if [ -n "$CC_NAME" ] && [ -n "$CC_ADDRESS" ]
   then CC_ADDRESS_OK=TRUE
   fi

   _CreateEMailContent_CEM_ "$@"
   retCode="$?" ; [ "$retCode" -ne 0 ] && return "$retCode"

   if "$cemIsVerboseMode"
   then
       _PrintMsg_CEM_ "\nSending email notification [${cemGRNct}${1}${cemCLRct}]."
       _PrintMsg_CEM_ "\nPlease wait...\n"
   fi

   mailpswd="$(/usr/sbin/openssl aes-256-cbc "$emailPwEnc" -d -in "$amtmEMailPswdFileCEM" -pass pass:ditbabot,isoi)"
   if [ -z "$mailpswd" ]
   then
       _LogMsg_CEM_ "**ERROR**: Failure to extract email password." "$cemSysLogERROR"
       return 60
   fi

   printf '' > "$cemCurlErrLogFPath"
   printf '' > "$cemCurlTmpLogFPath"

   /usr/sbin/curl -vLSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${cemHTTPstatusStr}: %{http_code}\n" \
   --output /dev/null --stderr "$cemCurlErrLogFPath" \
   --url "${PROTOCOL}://${SMTP}:${PORT}" \
   --user "${USERNAME}:$mailpswd" \
   --mail-from "$FROM_ADDRESS" \
   --mail-rcpt "$TO_ADDRESS" ${CC_ADDRESS_OK:+--mail-rcpt "$CC_ADDRESS"} \
   --upload-file "$cemTmpEMailContent" \
   $SSL_FLAG --ssl-reqd --crlf >> "$cemCurlTmpLogFPath"
   curlRetCode="$?"

   statusCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${cemHTTPstatusStr}: [4-5][0-9]{2,}" "$cemCurlTmpLogFPath")"

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

       if [ -s "$cemCurlErrLogFPath" ] && \
          "$cemIsInteractive" && "$cemIsVerboseMode" && "$cemIsDebugMode"
       then
           echo "======================================================="
           cat "$cemCurlErrLogFPath"
           echo "======================================================="
       fi
   fi
   mailpswd='XXXXXXXXXXXXXXX' ; unset mailpswd

   if "$cemIsVerboseMode" || [ "$logPrioNum" = "$cemSysLogERROR" ]
   then _PrintMsg_CEM_ "$theMsgStr"
   fi
   _LogMsg_CEM_ "$logMsgStr" "$logPrioNum" NOECHO

   sleep 1
   if "$cemDeleteMailContentFile"
   then rm -f "$cemTmpEMailContent"
   else mv -f "$cemTmpEMailContent" "${cemTmpEMailContent}.DEBUG"
   fi
   rm -f "$cemCurlTmpLogFPath" "$cemCurlErrLogFPath"

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
