#!/bin/sh
####################################################################
# FILENAME: DownloadCEMLibraryFile.lib.sh
# TAG: _LIB_DownloadCEMLibraryFile_SHELL_
# 
# Custom function to download the shared email library script.
# This function checks 2 separate website URLs to download the
# library script, just in the case the 1st one is unavailable.
#
# IMPORTANT NOTE:
# Variables with the "cem" or "CEM" prefix are reserved for
# the shared custom email library. You can modify the values
# but do *NOT* change the variable names.
#
# Creation Date: 2024-Jul-08 [Martinski W.]
# Last Modified: 2024-Jul-10 [Martinski W.]
####################################################################

if [ -z "${_LIB_DownloadCEMLibraryFile_SHELL_:+xSETx}" ]
then _LIB_DownloadCEMLibraryFile_SHELL_=0
else return 0
fi

CEM_DL_HELPER_VERSION="0.1.6"

CEM_LIB_BRANCH="master"
CEM_LIB_URL1="https://raw.githubusercontent.com/MartinSkyW/CustomMiscUtils/${CEM_LIB_BRANCH}/EMail"
CEM_LIB_URL2="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${CEM_LIB_BRANCH}/EMail"

CEM_LIB_LOCAL_DIR="/jffs/addons/shared-libs"
CEM_LIB_FILE_NAME="CustomEMailFunctions.lib.sh"
CEM_LIB_FILE_PATH="${CEM_LIB_LOCAL_DIR}/$CEM_LIB_FILE_NAME"

cemdlIsInteractive=false
if [ -t 0 ] && ! tty | grep -qwi "not"
then cemdlIsInteractive=true ; fi

_Print_CEMdl_()
{ "$cemdlIsInteractive" && printf "${1}" ; }

#-----------------------------------------------------------#
_DownloadLibraryScript_CEM_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then
       _Print_CEMdl_ "\n**ERROR**: NO parameters were provided to download library file.\n"
       return 1
   fi

   _DownloadLibScriptFile_()
   {
      if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] ; then return 1 ; fi

      curl -LSs --retry 4 --retry-delay 5 --retry-connrefused \
           "${1}/$CEM_LIB_FILE_NAME" -o "$CEM_LIB_FILE_PATH"

      if [ ! -s "$CEM_LIB_FILE_PATH" ] || \
         grep -Eiq "^404: Not Found" "$CEM_LIB_FILE_PATH"
      then
          [ -s "$CEM_LIB_FILE_PATH" ] && { echo ; cat "$CEM_LIB_FILE_PATH" ; }
          rm -f "$CEM_LIB_FILE_PATH"
          _Print_CEMdl_ "\n**ERROR**: Unable to download the library script [$CEM_LIB_FILE_NAME]\n"
          [ "$2" -lt "$urlDLMax" ] && _Print_CEMdl_ "Trying again with a different URL...\n"
          return 1
      else
          chmod 755 "$CEM_LIB_FILE_PATH"
          . "$CEM_LIB_FILE_PATH"
          [ "$2" -gt 1 ] && echo
          if [ "$2" -gt 1 ] || "$doDL_IsVerboseMode"
          then
              _Print_CEMdl_ "The email library script file [$CEM_LIB_FILE_NAME] was ${msgStr2}.\n"
          fi
          return 0
      fi
   }

   local msgStr1  msgStr2  retCode  urlDLCount  urlDLMax
   case "$2" in
        update) msgStr1="Updating" ; msgStr2="updated" ;;
       install) msgStr1="Installing" ; msgStr2="installed" ;;
             *) return 1 ;;
   esac

   mkdir -m 755 -p "$1"
   if [ ! -d "$1" ]
   then
       _Print_CEMdl_ "\n**ERROR**: Directory Path [$1] *NOT* FOUND.\n"
       return 1
   fi

   "$doDL_IsVerboseMode" && \
   _Print_CEMdl_ "\n${msgStr1} the shared library script file to support email notifications...\n"

   retCode=1 ; urlDLCount=0 ; urlDLMax=2
   for cemLibScriptURL in "$CEM_LIB_URL1" "$CEM_LIB_URL2"
   do
       urlDLCount="$((urlDLCount + 1))"
       if _DownloadLibScriptFile_ "$cemLibScriptURL" "$urlDLCount"
       then retCode=0 ; break ; fi
   done
   return "$retCode"
}

#-----------------------------------------------------------#
_CheckForLibraryScript_CEM_()
{
   local retCode=0
   local doDL_LibScriptMsge=""
   local doDL_LibScriptFlag=false
   local doDL_IsVerboseMode=true

   if [ $# -gt 0 ] && [ "$1" = "-quiet" ]
   then doDL_IsVerboseMode=false
   else doDL_IsVerboseMode=true
   fi

   if [ -f "$CEM_LIB_FILE_PATH" ]
   then
       . "$CEM_LIB_FILE_PATH"

       if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
           _CheckLibraryUpdates_CEM_ "$CEM_LIB_LOCAL_DIR" "$@"
       then
           retCode=1
           doDL_LibScriptFlag=true
           doDL_LibScriptMsge=update
       fi
   else
       retCode=1
       doDL_LibScriptFlag=true
       doDL_LibScriptMsge=install
   fi

   if "$doDL_LibScriptFlag"
   then
       _DownloadLibraryScript_CEM_ "$CEM_LIB_LOCAL_DIR" "$doDL_LibScriptMsge"
       retCode="$?"
   fi

   return "$retCode"
}

_LIB_DownloadCEMLibraryFile_SHELL_=1

#EOF#
