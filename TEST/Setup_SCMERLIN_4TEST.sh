#!/bin/sh
###################################################################
# SetUp_SCMERLIN_4TEST.sh
# To set up the modified scMerlin files for testing purposes.
#
# IMPORTANT NOTE:
# After running this script, the router must be rebooted to
# make sure the "startup" routine for the add-on completes
# the work of setting up the WebGUI page.
#
# Last Modified: Martinski W. [2024-June-25]
###################################################################
set -u

_SetUp_SCMERLIN_4Test_()
{
   SCMERLIN_WEBGUI="scmerlin_www.asp"
   ORIG_SCMERLIN_WEBPAGE="/jffs/addons/scmerlin.d/$SCMERLIN_WEBGUI"
   SAVE_SCMERLIN_WEBPAGE="${ORIG_SCMERLIN_WEBPAGE}.SAVE.ASP"
   TEST_SCMERLIN_WEBPAGE="${ORIG_SCMERLIN_WEBPAGE}.TEST.ASP"
   SCMERLIN_GITHUB_URL="https://raw.githubusercontent.com/Martinski4GitHub/scMerlin_TLC/master"
   SCMERLIN_WEBGUI_URL="${SCMERLIN_GITHUB_URL}/$SCMERLIN_WEBGUI"

   curl -LSs --retry 3 --retry-delay 5 --retry-connrefused "$SCMERLIN_WEBGUI_URL" \
        -o "$TEST_SCMERLIN_WEBPAGE" && chmod 644 "$TEST_SCMERLIN_WEBPAGE"

   if [ ! -s "$TEST_SCMERLIN_WEBPAGE" ]
   then
       echo "TEST scMerlin webpage file [$TEST_SCMERLIN_WEBPAGE] is *NOT* FOUND."
       echo "Nothing to test. Exiting..."
       return 1
   else
       echo "TEST scMerlin webpage file [$TEST_SCMERLIN_WEBPAGE] was downloaded OK."
   fi

   if [ ! -s "$SAVE_SCMERLIN_WEBPAGE" ]
   then
       cp -fp "$ORIG_SCMERLIN_WEBPAGE" "$SAVE_SCMERLIN_WEBPAGE"
       chmod 644 "$SAVE_SCMERLIN_WEBPAGE"
       echo "Original scMerlin webpage file [$SAVE_SCMERLIN_WEBPAGE] was saved."
       echo
   fi

   if diff -q "$ORIG_SCMERLIN_WEBPAGE" "$TEST_SCMERLIN_WEBPAGE"
   then
       echo "Files [$ORIG_SCMERLIN_WEBPAGE] and [$TEST_SCMERLIN_WEBPAGE] are a MATCH."
   else
       cp -fp "$TEST_SCMERLIN_WEBPAGE" "$ORIG_SCMERLIN_WEBPAGE"
       chmod 644 "$ORIG_SCMERLIN_WEBPAGE" 
       echo "TEST scMerlin webpage file [$TEST_SCMERLIN_WEBPAGE] is ready."
       echo
   fi
   echo
   echo "Router needs to be rebooted now..."
   echo
}

_SetUp_SCMERLIN_4Test_

#EOF#
