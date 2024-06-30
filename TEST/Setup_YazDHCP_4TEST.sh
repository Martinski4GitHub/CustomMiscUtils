#!/bin/sh
###################################################################
# SetUp_YazDHCP_4TEST.sh
# To set up the modified YazDHCP files for test purposes ONLY.
#
# IMPORTANT NOTE:
# After running this script, the router DOES NOT need to be 
# rebooted to start testing the WebGUI page.
#
# Last Modified: Martinski W. [2024-June-29]
###################################################################
set -u

readonly theScriptFName="${0##*/}"
readonly ADDONS_DIR="/jffs/addons"
readonly SCRIPTS_DIR="/jffs/scripts"
readonly YAZDHCP_TITLE="YazDHCP"
readonly YAZDHCP_SCRIPT="YazDHCP"
readonly YAZDHCP_WEBGUI="Advanced_DHCP_Content.asp"
readonly YAZDHCP_ADDONS_DIR="${ADDONS_DIR}/YazDHCP.d"

YAZDHCP_GITHUB_URL="https://raw.githubusercontent.com/Martinski4GitHub/YazDHCP/develop"
readonly YAZDHCP_SCRIPT_URL="${YAZDHCP_GITHUB_URL}/${YAZDHCP_SCRIPT}.sh"
readonly YAZDHCP_WEBGUI_URL="${YAZDHCP_GITHUB_URL}/$YAZDHCP_WEBGUI"

readonly ORIG_YAZDHCP_SCRIPT="${SCRIPTS_DIR}/$YAZDHCP_SCRIPT"
readonly SAVE_YAZDHCP_SCRIPT="${ORIG_YAZDHCP_SCRIPT}.sh.SAVE.SH"
readonly TEST_YAZDHCP_SCRIPT="${ORIG_YAZDHCP_SCRIPT}.sh.TEST.SH"

readonly ORIG_YAZDHCP_WEBPAGE="${YAZDHCP_ADDONS_DIR}/$YAZDHCP_WEBGUI"
readonly SAVE_YAZDHCP_WEBPAGE="${ORIG_YAZDHCP_WEBPAGE}.SAVE.ASP"
readonly TEST_YAZDHCP_WEBPAGE="${ORIG_YAZDHCP_WEBPAGE}.TEST.ASP"

_ShowUsage_()
{
   cat <<EOF
--------------------------------------------------------------------
SYNTAX:

./$theScriptFName { setup | download }

EXAMPLE CALLS:

./$theScriptFName setup
    To download & set up new TEST files for ${YAZDHCP_TITLE}.

./$theScriptFName download
    Only to download new TEST files for ${YAZDHCP_TITLE}.
    All original existing files are left intact.
--------------------------------------------------------------------
EOF
}

_DownloadNewTestFiles_()
{
   if [ $# -eq 1 ] && [ "$1" = "FORCE" ]
   then
       rm -f "$TEST_YAZDHCP_SCRIPT" "$TEST_YAZDHCP_WEBPAGE"
   fi

   if [ ! -s "$TEST_YAZDHCP_SCRIPT" ]
   then
       curl -LSs --retry 3 --retry-delay 5 --retry-connrefused "$YAZDHCP_SCRIPT_URL" \
       -o "$TEST_YAZDHCP_SCRIPT" && chmod 644 "$TEST_YAZDHCP_SCRIPT"

       if [ ! -s "$TEST_YAZDHCP_SCRIPT" ]
       then
           echo "TEST $YAZDHCP_TITLE script file [$TEST_YAZDHCP_SCRIPT] is *NOT* FOUND."
           echo "Nothing to test. Exiting..."
           exit 1
       else
           echo "TEST $YAZDHCP_TITLE script file [$TEST_YAZDHCP_SCRIPT] was downloaded successfully."
       fi
   fi

   if [ ! -s "$TEST_YAZDHCP_WEBPAGE" ]
   then
       curl -LSs --retry 3 --retry-delay 5 --retry-connrefused "$YAZDHCP_WEBGUI_URL" \
       -o "$TEST_YAZDHCP_WEBPAGE" && chmod 644 "$TEST_YAZDHCP_WEBPAGE"

       if [ ! -s "$TEST_YAZDHCP_WEBPAGE" ]
       then
           echo "TEST $YAZDHCP_TITLE webpage file [$TEST_YAZDHCP_WEBPAGE] is *NOT* FOUND."
           echo "Nothing to test. Exiting..."
           exit 1
       else
           echo "TEST $YAZDHCP_TITLE webpage file [$TEST_YAZDHCP_WEBPAGE] was downloaded successfully."
       fi
   fi
   echo
}

_SaveOriginalFiles_()
{
   if [ ! -s "$SAVE_YAZDHCP_SCRIPT" ]
   then
       cp -fp "$ORIG_YAZDHCP_SCRIPT" "$SAVE_YAZDHCP_SCRIPT"
       chmod 644 "$SAVE_YAZDHCP_SCRIPT"
       echo "Original $YAZDHCP_TITLE script file [$SAVE_YAZDHCP_SCRIPT] was saved."
   fi

   if [ ! -s "$SAVE_YAZDHCP_WEBPAGE" ]
   then
       cp -fp "$ORIG_YAZDHCP_WEBPAGE" "$SAVE_YAZDHCP_WEBPAGE"
       chmod 644 "$SAVE_YAZDHCP_WEBPAGE"
       echo "Original $YAZDHCP_TITLE webpage file [$SAVE_YAZDHCP_WEBPAGE] was saved."
   fi
   echo
}

_RestoreOriginalFiles_()
{
   if [ -s "$SAVE_YAZDHCP_SCRIPT" ]
   then
       mv -f "$SAVE_YAZDHCP_SCRIPT" "$ORIG_YAZDHCP_SCRIPT"
       chmod 755 "$ORIG_YAZDHCP_SCRIPT"
       echo "Original $YAZDHCP_TITLE script file [$ORIG_YAZDHCP_SCRIPT] was restored."
   else
       echo "No saved $YAZDHCP_TITLE script file [$SAVE_YAZDHCP_SCRIPT] was found to restore."
   fi
   rm -f "$TEST_YAZDHCP_SCRIPT"

   if [ -s "$SAVE_YAZDHCP_WEBPAGE" ]
   then
       mv -f "$SAVE_YAZDHCP_WEBPAGE" "$ORIG_YAZDHCP_WEBPAGE"
       chmod 644 "$ORIG_YAZDHCP_WEBPAGE"
       echo "Original $YAZDHCP_TITLE webpage file [$ORIG_YAZDHCP_WEBPAGE] was restored."
   else
       echo "No saved $YAZDHCP_TITLE webpage file [$SAVE_YAZDHCP_WEBPAGE] was found to restore."
   fi
   rm -f "$TEST_YAZDHCP_WEBPAGE"
   echo
}

_SetUpFilesForTesting_()
{
   if diff -q "$ORIG_YAZDHCP_SCRIPT" "$TEST_YAZDHCP_SCRIPT"
   then
       echo "Files [$ORIG_YAZDHCP_SCRIPT] and [$TEST_YAZDHCP_SCRIPT] are a MATCH."
   else
       cp -fp "$TEST_YAZDHCP_SCRIPT" "$ORIG_YAZDHCP_SCRIPT"
       chmod 755 "$ORIG_YAZDHCP_SCRIPT"
       echo "TEST $YAZDHCP_TITLE script file [$TEST_YAZDHCP_SCRIPT] is ready."
   fi
   
   if diff -q "$ORIG_YAZDHCP_WEBPAGE" "$TEST_YAZDHCP_WEBPAGE"
   then
       echo "Files [$ORIG_YAZDHCP_WEBPAGE] and [$TEST_YAZDHCP_WEBPAGE] are a MATCH."
   else
       cp -fp "$TEST_YAZDHCP_WEBPAGE" "$ORIG_YAZDHCP_WEBPAGE"
       chmod 644 "$ORIG_YAZDHCP_WEBPAGE" 
       echo "TEST $YAZDHCP_TITLE webpage file [$TEST_YAZDHCP_WEBPAGE] is ready."
   fi
   echo
}

_RestartYazDHCP_()
{
   if [ $# -eq 1 ] && [ "$1" = "ORIG" ]
   then
       echo "Restarting $YAZDHCP_TITLE with original files..."
   else
       echo "Restarting $YAZDHCP_TITLE for testing purposes..."
   fi
   $ORIG_YAZDHCP_SCRIPT startup &
   echo "Please wait ~5 seconds for process to be completed..."
   sleep 5
   echo "Completed. You can now start testing $YAZDHCP_TITLE."
   echo
}

_PromptForYesOrNo_()
{
   read -n 3 -p "$1 [yY|nN] N? " YESorNO
   echo
   if echo "$YESorNO" | grep -qE '^([yY](es)?)$'
   then echo "YES" ; return 0
   else echo "NO" ; return 1
   fi
}

if [ ! -s "$ORIG_YAZDHCP_SCRIPT" ]
then
   echo "The $YAZDHCP_TITLE script file [$ORIG_YAZDHCP_SCRIPT] is *NOT* FOUND."
   echo "Exiting..."
   exit 1
fi

if [ ! -s "$ORIG_YAZDHCP_WEBPAGE" ]
then
   echo "The $YAZDHCP_TITLE webpage file [$ORIG_YAZDHCP_WEBPAGE] is *NOT* FOUND."
   echo "Exiting..."
   exit 1
fi

if [ $# -eq 0 ] || [ -z "$1" ]
then
   _ShowUsage_
else
   if [ "$1" != "setup" ] && \
      [ "$1" != "restore" ] && \
      [ "$1" != "download" ]
   then
       echo "**ERROR**: UNKNOWN Parameter [$1]."
       _ShowUsage_ ; exit 1
   fi

   if [ "$1" = "setup" ]
   then
       if _PromptForYesOrNo_ "Set up $YAZDHCP_TITLE for TESTING NEW version?"
       then
           ##OFF## _SaveOriginalFiles_
           _DownloadNewTestFiles_
           _SetUpFilesForTesting_
           _RestartYazDHCP_ TEST
       else 
           echo "Exiting..."
       fi
       exit 0
   fi

   if false && [ "$1" = "restore" ] ##OFF##
   then
       if _PromptForYesOrNo_ "Restore Original $YAZDHCP_TITLE files?"
       then
           _RestoreOriginalFiles_
           _RestartYazDHCP_ ORIG
       else
           echo "Exiting..."
       fi
       exit 0
   fi

   if [ "$1" = "download" ]
   then
       if _PromptForYesOrNo_ "Download new TEST versions of $YAZDHCP_TITLE files?"
       then _DownloadNewTestFiles_ FORCE
       else echo "Exiting..."
       fi
       exit 0
   fi
fi

#EOF#
