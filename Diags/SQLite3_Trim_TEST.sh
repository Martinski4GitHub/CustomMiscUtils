#!/bin/sh
###################################################################
# SQLite3_Trim_TEST.sh
# Creation Date: 2024-Oct-20 [Martinski W.]
# Last Modified: 2024-Oct-21 [Martinski W.]
###################################################################

VERSION="0.1.2"

if true
then readonly LOG_DIR_PATH="$HOME"
else readonly LOG_DIR_PATH="/tmp/var/tmp"
fi
readonly OPT_USB_PATH="/opt/share/uiDivStats.d"
readonly sqLiteDBbinPath="/opt/bin/sqlite3"
readonly sqLiteDBaseFile="${OPT_USB_PATH}/dnsqueries.db"
readonly sqLiteDBcmdFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Trim.SQL"
readonly sqLiteDBlogFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Trim.LOG"
readonly logTimeFormat="%Y-%m-%d %H:%M:%S"

_DaysToKeep_() { echo "$daysToKeep" ; }

_TrimDatabase_()
{
   local timeNowSecs  loopCount  errorCheck

   if [ -s "$sqLiteDBlogFile" ]
   then
       cp -fp "$sqLiteDBlogFile" "${sqLiteDBlogFile}.BAK"
       rm -f "$sqLiteDBlogFile"
   fi
   touch "$sqLiteDBlogFile"

   TZ="$(cat /etc/TZ)"
   export TZ
   timeNowSecs="$(date +'%s')"
   printf "\n[$(date +"$logTimeFormat")] Trimming records older than [$daysToKeep] days from database.\n" | tee -a "$sqLiteDBlogFile"

   {
     echo "PRAGMA cache_size=-20000;"
     echo "PRAGMA analysis_limit=1000;"
     echo "BEGIN TRANSACTION;"
     echo "DELETE FROM [dnsqueries] WHERE [Timestamp] < strftime('%s',datetime($timeNowSecs,'unixepoch','-$(_DaysToKeep_) day'));"
     echo "DELETE FROM [dnsqueries] WHERE [Timestamp] > $timeNowSecs;"
     echo "DELETE FROM [dnsqueries] WHERE [SrcIP] = 'from';"
     echo "ANALYZE dnsqueries;"
     echo "END TRANSACTION;"
     echo "VACUUM;"
   } > "$sqLiteDBcmdFile"

   loopCount=0
   foundError=false
   trap '' HUP

   while ! "$sqLiteDBbinPath" "$sqLiteDBaseFile" < "$sqLiteDBcmdFile" >> "$sqLiteDBlogFile" 2>&1
   do
      errorCheck="$(tail -n1 "$sqLiteDBlogFile")"
      if echo "$errorCheck" | grep -qE "^(Error:|Parse error|Runtime error)"
      then echo "$errorCheck" ; foundError=true ; break ; fi
      loopCount="$((loopCount + 1))"
      printf "LOOP_COUNT=[$loopCount]\n" | tee -a "$sqLiteDBlogFile"
      sleep 1
   done

   rm -f "$sqLiteDBcmdFile"
   "$foundError" && resultStr="reported error(s)." || resultStr="completed successfully."
   printf "[$(date +"$logTimeFormat")] Database trim process ${resultStr}\n\n" | tee -a "$sqLiteDBlogFile"
}

foundError=false
daysToKeep=30

trap 'exit 0' INT QUIT ABRT TERM

if [ $# -eq 0 ] || [ -z "$1" ] || \
   ! echo "$1" | grep -qE "^([1-9][0-9]{0,2})$"
then
    printf "\nNO parameter was provided or was INVALID."
    printf "\nUsing default value of [$daysToKeep] days.\n"
else
    daysToKeep="$1"
fi

_TrimDatabase_
printf "\nLogfile [$sqLiteDBlogFile] was created.\n"

exit 0

#EOF#
