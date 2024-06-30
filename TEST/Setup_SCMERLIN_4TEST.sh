#!/bin/sh
###################################################################
# SetUp_SCMERLIN_4TEST.sh
# To set up the modified scMerlin files for test purposes ONLY.
#
# IMPORTANT NOTE:
# After running this script, the router MUST BE rebooted to
# make sure the "startup" routine for the add-on completes
# the work of setting up the WebGUI page.
#
# Last Modified: Martinski W. [2024-June-29]
###################################################################
set -u

readonly theScriptFName="${0##*/}"
readonly ADDONS_DIR="/jffs/addons"
readonly SCRIPTS_DIR="/jffs/scripts"
readonly SCMERLIN_TITLE="scMerlin"
readonly SCMERLIN_SCRIPT="scmerlin"
readonly SCMERLIN_WEBGUI="scmerlin_www.asp"
readonly SCMERLIN_ADDONS_DIR="${ADDONS_DIR}/scmerlin.d"

SCMERLIN_GITHUB_URL="https://raw.githubusercontent.com/Martinski4GitHub/scMerlin_TLC/master"
readonly SCMERLIN_SCRIPT_URL="${SCMERLIN_GITHUB_URL}/${SCMERLIN_SCRIPT}.sh"
readonly SCMERLIN_WEBGUI_URL="${SCMERLIN_GITHUB_URL}/${SCMERLIN_WEBGUI}.TEST.ASP"

readonly ORIG_SCMERLIN_SCRIPT="${SCRIPTS_DIR}/$SCMERLIN_SCRIPT"
readonly SAVE_SCMERLIN_SCRIPT="${ORIG_SCMERLIN_SCRIPT}.sh.SAVE.SH"
readonly TEST_SCMERLIN_SCRIPT="${ORIG_SCMERLIN_SCRIPT}.sh.TEST.SH"

readonly ORIG_SCMERLIN_WEBPAGE="${SCMERLIN_ADDONS_DIR}/$SCMERLIN_WEBGUI"
readonly SAVE_SCMERLIN_WEBPAGE="${ORIG_SCMERLIN_WEBPAGE}.SAVE.ASP"
readonly TEST_SCMERLIN_WEBPAGE="${ORIG_SCMERLIN_WEBPAGE}.TEST.ASP"

_ShowUsage_()
{
   cat <<EOF
--------------------------------------------------------------------
SYNTAX:

./$theScriptFName { setup | download }

EXAMPLE CALLS:

./$theScriptFName setup
    To download & set up new TEST files for ${SCMERLIN_TITLE}.

./$theScriptFName download
    Only to download new TEST files for ${SCMERLIN_TITLE}.
    All original existing files are left intact.
--------------------------------------------------------------------
EOF
}

_DownloadNewTestFiles_()
{
   if [ $# -eq 1 ] && [ "$1" = "FORCE" ]
   then
       rm -f "$TEST_SCMERLIN_SCRIPT" "$TEST_SCMERLIN_WEBPAGE"
   fi

   if [ ! -s "$TEST_SCMERLIN_SCRIPT" ]
   then
       curl -LSs --retry 3 --retry-delay 5 --retry-connrefused "$SCMERLIN_SCRIPT_URL" \
       -o "$TEST_SCMERLIN_SCRIPT" && chmod 644 "$TEST_SCMERLIN_SCRIPT"

       if [ ! -s "$TEST_SCMERLIN_SCRIPT" ]
       then
           echo "TEST $SCMERLIN_TITLE script file [$TEST_SCMERLIN_SCRIPT] is *NOT* FOUND."
           echo "Nothing to test. Exiting..."
           exit 1
       else
           echo "TEST $SCMERLIN_TITLE script file [$TEST_SCMERLIN_SCRIPT] was downloaded successfully."
       fi
   fi

   if [ ! -s "$TEST_SCMERLIN_WEBPAGE" ]
   then
       curl -LSs --retry 3 --retry-delay 5 --retry-connrefused "$SCMERLIN_WEBGUI_URL" \
       -o "$TEST_SCMERLIN_WEBPAGE" && chmod 644 "$TEST_SCMERLIN_WEBPAGE"

       if [ ! -s "$TEST_SCMERLIN_WEBPAGE" ]
       then
           echo "TEST $SCMERLIN_TITLE webpage file [$TEST_SCMERLIN_WEBPAGE] is *NOT* FOUND."
           echo "Nothing to test. Exiting..."
           exit 1
       else
           echo "TEST $SCMERLIN_TITLE webpage file [$TEST_SCMERLIN_WEBPAGE] was downloaded successfully."
       fi
   fi
   echo
}

_SaveOriginalFiles_()
{
   if [ ! -s "$SAVE_SCMERLIN_SCRIPT" ]
   then
       cp -fp "$ORIG_SCMERLIN_SCRIPT" "$SAVE_SCMERLIN_SCRIPT"
       chmod 644 "$SAVE_SCMERLIN_SCRIPT"
       echo "Original $SCMERLIN_TITLE script file [$SAVE_SCMERLIN_SCRIPT] was saved."
   fi

   if [ ! -s "$SAVE_SCMERLIN_WEBPAGE" ]
   then
       cp -fp "$ORIG_SCMERLIN_WEBPAGE" "$SAVE_SCMERLIN_WEBPAGE"
       chmod 644 "$SAVE_SCMERLIN_WEBPAGE"
       echo "Original $SCMERLIN_TITLE webpage file [$SAVE_SCMERLIN_WEBPAGE] was saved."
   fi
   echo
}

_RestoreOriginalFiles_()
{
   if [ -s "$SAVE_SCMERLIN_SCRIPT" ]
   then
       mv -f "$SAVE_SCMERLIN_SCRIPT" "$ORIG_SCMERLIN_SCRIPT"
       chmod 755 "$ORIG_SCMERLIN_SCRIPT"
       echo "Original $SCMERLIN_TITLE script file [$ORIG_SCMERLIN_SCRIPT] was restored."
   else
       echo "No saved $SCMERLIN_TITLE script file [$SAVE_SCMERLIN_SCRIPT] was found to restore."
   fi
   rm -f "$TEST_YAZDHCP_SCRIPT"

   if [ -s "$SAVE_SCMERLIN_WEBPAGE" ]
   then
       mv -f "$SAVE_SCMERLIN_WEBPAGE" "$ORIG_SCMERLIN_WEBPAGE"
       chmod 644 "$ORIG_SCMERLIN_WEBPAGE"
       echo "Original $SCMERLIN_TITLE webpage file [$ORIG_SCMERLIN_WEBPAGE] was restored."
   else
       echo "No saved $SCMERLIN_TITLE webpage file [$SAVE_SCMERLIN_WEBPAGE] was found to restore."
   fi
   rm -f "$TEST_YAZDHCP_WEBPAGE"
   echo
}

_SetUpFilesForTesting_()
{
   if diff -q "$ORIG_SCMERLIN_SCRIPT" "$TEST_SCMERLIN_SCRIPT"
   then
       echo "Files [$ORIG_SCMERLIN_SCRIPT] and [$TEST_SCMERLIN_SCRIPT] are a MATCH."
   else
       cp -fp "$TEST_SCMERLIN_SCRIPT" "$ORIG_SCMERLIN_SCRIPT"
       chmod 755 "$ORIG_SCMERLIN_SCRIPT"
       echo "TEST $SCMERLIN_TITLE script file [$TEST_SCMERLIN_SCRIPT] is ready."
   fi
   
   if diff -q "$ORIG_SCMERLIN_WEBPAGE" "$TEST_SCMERLIN_WEBPAGE"
   then
       echo "Files [$ORIG_SCMERLIN_WEBPAGE] and [$TEST_SCMERLIN_WEBPAGE] are a MATCH."
   else
       cp -fp "$TEST_SCMERLIN_WEBPAGE" "$ORIG_SCMERLIN_WEBPAGE"
       chmod 644 "$ORIG_SCMERLIN_WEBPAGE" 
       echo "TEST $SCMERLIN_TITLE webpage file [$TEST_SCMERLIN_WEBPAGE] is ready."
   fi
   echo
}

_RestartRouterMsg_()
{
   echo
   echo "Router MUST BE REBOOTED BEFORE testing can be done."
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

if [ ! -s "$ORIG_SCMERLIN_SCRIPT" ]
then
   echo "The $SCMERLIN_TITLE script file [$ORIG_SCMERLIN_SCRIPT] is *NOT* FOUND."
   echo "Exiting..."
   exit 1
fi

if [ ! -s "$ORIG_SCMERLIN_WEBPAGE" ]
then
   echo "The $SCMERLIN_TITLE webpage file [$ORIG_SCMERLIN_WEBPAGE] is *NOT* FOUND."
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
       if _PromptForYesOrNo_ "Set up $SCMERLIN_TITLE for TESTING NEW version?"
       then
           ##OFF## _SaveOriginalFiles_
           _DownloadNewTestFiles_ FORCE
           _SetUpFilesForTesting_
           _RestartRouterMsg_
       else 
           echo "Exiting..."
       fi
       exit 0
   fi

   if false && [ "$1" = "restore" ] ##OFF##
   then
       if _PromptForYesOrNo_ "Restore Original $SCMERLIN_TITLE files?"
       then
           _RestoreOriginalFiles_
           _RestartRouterMsg_
       else
           echo "Exiting..."
       fi
       exit 0
   fi

   if [ "$1" = "download" ]
   then
       if _PromptForYesOrNo_ "Download new TEST versions of $SCMERLIN_TITLE files?"
       then _DownloadNewTestFiles_ FORCE
       else echo "Exiting..."
       fi
       exit 0
   fi
fi

#EOF#
