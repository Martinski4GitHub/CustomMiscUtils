#!/bin/sh
###################################################################
# SQLite3_Trim_TEST.sh
# Creation Date: 2024-Oct-20 [Martinski W.]
# Last Modified: 2024-Oct-22 [Martinski W.]
###################################################################

VERSION="0.1.3"

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

_DaysToKeep_() { echo "$daysToKeepData" ; }

_SetSQLDBcmdsFile_()
{
   {
     echo "PRAGMA temp_store=1;"
     printf "PRAGMA cache_size=-%d000;\n" "$cacheSize"
     printf "PRAGMA analysis_limit=%d;\n" "$limitSize"
     echo "BEGIN TRANSACTION;"
     echo "DELETE FROM [dnsqueries] WHERE [Timestamp] < strftime('%s',datetime($timeNowSecs,'unixepoch','-$(_DaysToKeep_) day'));"
     echo "DELETE FROM [dnsqueries] WHERE [Timestamp] > $timeNowSecs;"
     "$doSrceFrom" && echo "DELETE FROM [dnsqueries] WHERE [SrcIP] = 'from';"
     echo "ANALYZE dnsqueries;"
     echo "END TRANSACTION;"
     "$vacuumOK" && echo "VACUUM;"
   } > "$sqLiteDBcmdFile"
}

_ShowSQLDBfileInfo_()
{
   local fileSize  fileInfo
   fileSize="$(ls -1lh "$1" | awk -F ' ' '{print $3}')"
   fileInfo="$(ls -1l "$1" | awk -F ' ' '{print $3,$4,$5,$6,$7}')"
   printf "[%s] %s\n" "$fileSize" "$fileInfo"
}

_TrimDatabase_()
{
   local timeNowSecs  numCount  maxCount  errorCheck

   if [ -s "$sqLiteDBlogFile" ]
   then
       cp -fp "$sqLiteDBlogFile" "${sqLiteDBlogFile}.BAK"
       rm -f "$sqLiteDBlogFile"
   fi
   touch "$sqLiteDBlogFile"

   TZ="$(cat /etc/TZ)"
   export TZ

   printf "[$(date +"$logTimeFormat")] BEGIN.\n" >> "$sqLiteDBlogFile"
   [ -s "$sqLiteDBaseFile" ] && _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBlogFile"
   printf "[$(date +"$logTimeFormat")] Trimming records older than [$daysToKeepData] days from database.\n" | tee -a "$sqLiteDBlogFile"
   echo "----------------------------------------------------------" >> "$sqLiteDBlogFile"

   numCount=0 ; maxCount=5
   timeNowSecs="$(date +'%s')"
   _SetSQLDBcmdsFile_
   trap '' HUP

   while ! "$sqLiteDBbinPath" "$sqLiteDBaseFile" < "$sqLiteDBcmdFile" >> "$sqLiteDBlogFile" 2>&1
   do
      numCount="$((numCount + 1))"
      errorCheck="$(tail -n1 "$sqLiteDBlogFile")"
      printf "[$(date +"$logTimeFormat")] TRY_COUNT=[$numCount]\n" | tee -a "$sqLiteDBlogFile"
      if echo "$errorCheck" | grep -qE "^(Error:|Parse error|Runtime error)"
      then
         echo "$errorCheck" ; foundError=true
         {
           echo "------------------------------------"
           cat "$sqLiteDBcmdFile"
           echo "=========================================================="
         } >> "$sqLiteDBlogFile"
         [ "$numCount" -gt 0 ] && limitSize=0
         [ "$numCount" -gt 1 ] && cacheSize=10
         [ "$numCount" -gt 2 ] && limitSize=1000
         [ "$numCount" -gt 3 ] && vacuumOK=false
         _SetSQLDBcmdsFile_
      fi
      [ "$numCount" -ge "$maxCount" ] && break
      sleep 1
   done

   ! "$doDebug" && rm -f "$sqLiteDBcmdFile"
   "$foundError" && resultStr="reported error(s)." || resultStr="completed successfully."
   printf "[$(date +"$logTimeFormat")] Database trim process ${resultStr}\n" | tee -a "$sqLiteDBlogFile"
   [ -s "$sqLiteDBaseFile" ] && _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBlogFile"
   printf "[$(date +"$logTimeFormat")] END.\n" >> "$sqLiteDBlogFile"
}

onceOK=true
doDebug=false
vacuumOK=true
cacheSize=20
limitSize=2000
foundError=false
doSrceFrom=true
daysToKeepData=30

trap 'exit 0' INT QUIT ABRT TERM

if [ $# -eq 0 ] || [ -z "$1" ]
then
   printf "\nNO parameter was provided. "
   printf "Using default value of [$daysToKeepData] days.\n\n"
else
   for PARAM in "$@"
   do
      case "$PARAM" in
          "debug") doDebug=true ;;
          "nolim") limitSize=0 ;;
          "cache") cacheSize=10 ;;
          "nosrc") doSrceFrom=false ;;
                *) if echo "$1" | grep -qE "^([1-9][0-9]{0,2})$"
                   then
                      daysToKeepData="$1"
                   else
                      printf "\nINVALID parameter was provided. "
                      printf "Using default value of [$daysToKeepData] days.\n\n"
                   fi
                   ;;
      esac
   done
fi

_TrimDatabase_
printf "\nLogfile [$sqLiteDBlogFile] was created.\n"

exit 0

#EOF#
