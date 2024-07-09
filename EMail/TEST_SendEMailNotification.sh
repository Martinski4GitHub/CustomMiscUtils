#!/bin/sh
####################################################################
# TEST_SendEMailNotification.sh
# 
# To test using the "CustomEMailFunctions.lib.sh" shared library.
# A simple example.
#
# IMPORTANT NOTE:
# Variables with the "cem" or "CEM" prefix are reserved for
# the shared custom email library. You can modify the values
# but do *NOT* change the variable names.
#
# Creation Date: 2020-Jun-11 [Martinski W.]
# Last Modified: 2024-Jul-09 [Martinski W.]
####################################################################
set -u

TEST_VERSION="0.5.14"

readonly scriptFileName="${0##*/}"
readonly scriptFileNTag="${scriptFileName%.*}"

## The shared custom email library to support email notifications ##
readonly ADDONS_SHARED_LIBS_DIR_PATH="/jffs/addons/shared-libs"
readonly CUSTOM_EMAIL_LIB_SCRIPT_FNAME="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME="DownloadCEMLibraryFile.lib.sh"
readonly CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH="${ADDONS_SHARED_LIBS_DIR_PATH}/$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME"
readonly CUSTOM_EMAIL_LIB_SCRIPT_URL="https://raw.githubusercontent.com/MartinSkyW/CustomMiscUtils/master/EMail"

#-----------------------------------------------------------#
_DownloadCEMLibraryHelperFile_()
{
   printf "\nDownloading the library helper script file to support email notifications...\n"

   curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
        ${CUSTOM_EMAIL_LIB_SCRIPT_URL}/$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME \
        -o "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"

   if [ ! -s "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ] || \
      grep -Eiq "^404: Not Found" "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
   then
       [ -s "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ] && { echo ; cat "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ; }
       rm -f "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       printf "\n**ERROR**: Unable to download the library helper script [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME]\n"
       return 1
   else
       chmod 755 "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       . "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
       printf "The email library helper script [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME] was downloaded.\n"
       return 0
   fi
}

if [ $# -gt 1 ] && [ "$1" = "download" ] && [ "$1" = "-cemdlhelper" ]
then _DownloadCEMLibraryHelperFile_ ; fi

if [ ! -f "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ]
then _DownloadCEMLibraryHelperFile_ ; fi

if [ -f "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH" ]
then
    . "$CUSTOM_EMAIL_LIB_DLSCRIPT_FPATH"
    _CheckForLibraryScript_CEM_ -quiet
else
    printf "\n**ERROR**: Library helper script file [$CUSTOM_EMAIL_LIB_DLSCRIPT_FNAME] *NOT* FOUND.\n"
fi

#-----------------------------------------------------------#
# ARG1: The email name/alias to be used as "FROM_NAME"
# ARG2: The email Subject string.
# ARG3: Full path of file containing the email Body text.
# ARG4: The email Body Title string [OPTIONAL].
#-----------------------------------------------------------#
_SendEMailNotification_()
{
   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       logTag="**ERROR**_${scriptFileName}_$$"
       logMsg="Email library script [$CUSTOM_EMAIL_LIB_SCRIPT_FNAME] *NOT* FOUND."
       printf "\n%s: %s\n\n" "$logTag" "$logMsg"
       /usr/bin/logger -t "$logTag" "$logMsg"
       return 1
   fi

   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then
       printf "\n**ERROR**: INSUFFICIENT email parameters\n"
       return 1
   fi

   if [ ! -f "$3" ]
   then
       printf "\n**ERROR**: Email body contents file [$3] NOT FOUND.\n"
       return 1
   fi

   local retCode  emailBodyTitleStr=""

   [ $# -gt 3 ] && [ -n "$4" ] && emailBodyTitleStr="$4"

   ## ONLY for DEBUG/TEST purposes set these as needed ##
   cemIsDebugMode=false            ## true OR false ##
   cemIsVerboseMode=true           ## true OR false ##
   cemDeleteMailContentFile=false  ## true OR false ##

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

#---------------#
# Example Setup #
#---------------#
emailSubject="TESTING Email Setup"
tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

#------------------------------------------
# Customizable Format Type Parameter.
# To set the desired email format type.
# For "HTML" format set to true.
# For "Plain Text" format set to false.
#------------------------------------------
cemIsFormatHTML=true

#----------------------------------------------------
# Customizable OPTIONAL Parameter.
# To set as a title at the top of the email body.
#----------------------------------------------------
emailBodyTitle=""
addBodyTitle=true
if "$addBodyTitle"
then
    emailBodyTitle="Testing Email Notification"
fi

#-----------------------------------------------------
# Customizable OPTIONAL Parameter.
# To use a secondary email address as "CC" parameter
# for email notifications.
#-----------------------------------------------------
addOptionalCC=false
if "$addOptionalCC"
then
    CC_NAME="CopyFooBar2"
    # THIS MUST BE A REAL EMAIL ADDRESS ##
    CC_ADDRESS="CopyFooBar2@google.com"
fi

{
  printf "This is a <b>TEST</b> to check & verify if sending email notifications"
  printf " is working well from the \"${0}\" shell script.\n"
} > "$tmpEMailBodyFile"

_SendEMailNotification_ "EmailTEST" "$emailSubject" "$tmpEMailBodyFile" "$emailBodyTitle"

[ -f "$tmpEMailBodyFile" ] && rm -f "$tmpEMailBodyFile"

#EOF#
