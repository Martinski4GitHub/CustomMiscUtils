#!/bin/sh
###################################################################
# SQLite3_Trim_TEST.sh
# Creation Date: 2024-Oct-20 [Martinski W.]
# Last Modified: 2024-Oct-24 [Martinski W.]
###################################################################

VERSION="0.1.5"

if true
then readonly LOG_DIR_PATH="$HOME"
else readonly LOG_DIR_PATH="/tmp/var/tmp"
fi
readonly OPT_USB_PATH="/opt/share/uiDivStats.d"
readonly sqLiteDBbinPath="/opt/bin/sqlite3"
readonly sqLiteDBaseFile="${OPT_USB_PATH}/dnsqueries.db"
readonly sqLiteDBCMDFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Cmds.SQL"
readonly sqLiteDBLOGFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Trim.LOG"
readonly sqLiteDBoldFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Oldest.LOG"
readonly logTimeFormat="%Y-%m-%d %H:%M:%S"
readonly _1_0_GB_="1073741824"
readonly _1_5_GB_="1610612736"
readonly _2_0_GB_="2147483648"
readonly maxTrimSize="$_2_0_GB_"

_DaysToKeep_() { echo "$daysToKeepData" ; }

_ShowSQLDBfileInfo_()
{
   [ ! -s "$1" ] && return 1
   local fileSize  fileInfo
   fileSize="$(ls -1lh "$1" | awk -F ' ' '{print $3}')"
   fileInfo="$(ls -1l "$1" | awk -F ' ' '{print $3,$4,$5,$6,$7}')"
   printf "[%sB] %s\n" "$fileSize" "$fileInfo"
}

_ShowMemInfo_()
{
   local infoType
   if [ $# -eq 0 ] || [ -z "$1" ]
   then infoType=1
   else infoType="$1"
   fi
   if [ "$infoType" -eq 1 ]
   then printf "free:\n" ; free
   elif [ "$infoType" -eq 2 ]
   then
      printf "---------\n MemInfo\n---------\n"
      grep -E '^Mem[TFA].*:[[:blank:]]+.*' /proc/meminfo
      grep -E '^(Buffers|Cached):[[:blank:]]+.*' /proc/meminfo
      grep -E '^Swap[TFC].*:[[:blank:]]+.*' /proc/meminfo
      grep -E '^(Active|Inactive)(\([af].*\))?:[[:blank:]]+.*' /proc/meminfo
      grep -E '^(Dirty|Writeback|AnonPages|Unevictable):[[:blank:]]+.*' /proc/meminfo
   fi
   echo "-------------------------------------------"
}

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
   } > "$sqLiteDBCMDFile"
}

_ShowSQLDBcmdsFile_()
{
  cat "$sqLiteDBCMDFile"
  echo "=========================================================="
}

_SetSQLDBcmdsOldest_()
{
   {
     echo ".mode csv"
     echo ".headers off"
     echo ".separator '|'"
     echo ".output $sqLiteDBTMPFile"
     printf "SELECT * FROM [dnsqueries] WHERE [Timestamp] < strftime('%%s',datetime($timeNowSecs,'unixepoch','-$(_DaysToKeep_) day')) "
     printf "ORDER BY [Timestamp] ASC LIMIT %d;\n" "$recordsLimit"
   } > "$sqLiteDBCMDFile"
}

_SQLiteShowTimeStamp_()
{
   [ ! -s "$1" ] && return 1
   local recordNum  lastRecordNum  numDigits  timeStamp
   local headRecordStr  tailRecordStr
   
   _GetRecordTimeStamp_()
   {
      timeStamp="$(echo "$1" | awk -F '|' '{print $2}')"
      printf "TimeStamp: %s\n" "$(date -d @$timeStamp +'%Y-%b-%d %I:%M:%S %p %Z (%a)')"
   }

   dos2unix "$1"
   recordNum=0
   lastRecordNum="$(cat "$1" | wc -l)"
   numDigits="$(echo "$lastRecordNum" | wc -m)"
   numDigits="$((numDigits - 1))"

   if "$showTotalOnly" && [ "$lastRecordNum" -gt 0 ]
   then
       _PrintSepLine_
       headRecordStr="$(head -n1 "$1")"
       tailRecordStr="$(tail -n1 "$1")"
       printf "Record #%d: [%s]\n" 1 "$headRecordStr"
       _GetRecordTimeStamp_ "$headRecordStr"
       printf "...\n"
       printf "Record #%d: [%s]\n" "$lastRecordNum" "$tailRecordStr"
       _GetRecordTimeStamp_ "$tailRecordStr"
       _PrintSepLine_
       oldestRecsFound=true
       return 0
   fi

   while read -r recordLINE
   do
      [ -z "$recordLINE" ] && continue
      recordNum="$((recordNum + 1))"
      [ "$recordNum" -eq 1 ] && _PrintSepLine_ || echo
      printf "Record #%02d: [%s]\n" "$recordNum" "$recordLINE"
      _GetRecordTimeStamp_ "$recordLINE"
   done < "$1"

   [ "$recordNum" -gt 0 ] && _PrintSepLine_
   return 0
}

_ShowOldestRecords_()
{
   local timeNowSecs  foundError  foundLocked
   local sqLiteDBTMPFile  showBookends  retCode

   _PrintSepLine_()
   { echo "--------------------------------------------------------------------" ; }

   if [ $# -eq 0 ] || [ -z "$1" ]
   then showBookends=true
   else showBookends=false
   fi
   sqLiteDBTMPFile="${LOG_DIR_PATH}/uiDivStats_SQLDB_Oldest.TMP"

   rm -f "$sqLiteDBoldFile" "$sqLiteDBTMPFile" "$sqLiteDBCMDFile"
   touch "$sqLiteDBoldFile"

   TZ="$(cat /etc/TZ)"
   export TZ

   if "$showBookends"
   then
      printf "[$(date +"$logTimeFormat")] BEGIN.\n" >> "$sqLiteDBoldFile"
      _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBoldFile"
   fi
   printf "[$(date +"$logTimeFormat")] Get records older than [$daysToKeepData] days from database.\n" | tee -a "$sqLiteDBoldFile"

   retCode=0
   foundError=false
   foundLocked=false
   timeNowSecs="$(date +'%s')"
   _SetSQLDBcmdsOldest_
   trap '' HUP

   if ! "$sqLiteDBbinPath" "$sqLiteDBaseFile" < "$sqLiteDBCMDFile" >> "$sqLiteDBoldFile" 2>&1
   then
       foundError=true; retCode=1
       errorCheck="$(tail -n1 "$sqLiteDBoldFile")"
       echo "$errorCheck"
   fi

   if "$foundError"
   then resultStr="reported error(s)."
   elif "$foundLocked"
   then resultStr="found locked database."
   else
      resultStr="completed successfully."
      if [ -s "$sqLiteDBTMPFile" ]
      then
         oldestRecsFound=true
         _SQLiteShowTimeStamp_ "$sqLiteDBTMPFile" | tee -a "$sqLiteDBoldFile"
      else
         oldestRecsFound=false
         printf "[$(date +"$logTimeFormat")] No records older than [$daysToKeepData] days were found.\n" | tee -a "$sqLiteDBoldFile"
         _PrintSepLine_ | tee -a "$sqLiteDBoldFile"
      fi
   fi
   "$testDebug" && _ShowSQLDBcmdsFile_ >> "$sqLiteDBoldFile"
   ! "$testDebug" && rm -f "$sqLiteDBCMDFile" "$sqLiteDBTMPFile"

   if "$showBookends"
   then
      printf "[$(date +"$logTimeFormat")] Database process ${resultStr}\n" | tee -a "$sqLiteDBoldFile"
      printf "[$(date +"$logTimeFormat")] END.\n" >> "$sqLiteDBoldFile"
   fi
   return "$retCode"
}

_LogOldestRecords_()
{
   recordsLimit=-1
   getOldestRecs=true
   showTotalOnly=true
   _ShowOldestRecords_ OK
   [ -s "$sqLiteDBoldFile" ] && cat "$sqLiteDBoldFile" >> "$sqLiteDBLOGFile"
   rm -f "$sqLiteDBoldFile"
   
}

_TrimDatabase_()
{
   local timeNowSecs  dbFileSize  triesCount  maxTriesCount  resultStr
   local errorCheck  errorCount  maxErrorCount  foundError  foundLocked

   if [ -s "$sqLiteDBLOGFile" ]
   then
       cp -fp "$sqLiteDBLOGFile" "${sqLiteDBLOGFile}.BAK"
       rm -f "$sqLiteDBLOGFile" "$sqLiteDBCMDFile"
   fi
   touch "$sqLiteDBLOGFile"

   TZ="$(cat /etc/TZ)"
   export TZ

   printf "[$(date +"$logTimeFormat")] BEGIN.\n" >> "$sqLiteDBLOGFile"
   _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBLOGFile"
   printf "[$(date +"$logTimeFormat")] Trimming records older than [$daysToKeepData] days from database.\n" | tee -a "$sqLiteDBLOGFile"
   echo "----------------------------------------------------------" >> "$sqLiteDBLOGFile"
   _LogOldestRecords_ 
   _ShowMemInfo_ 1 >> "$sqLiteDBLOGFile"

   foundError=false
   foundLocked=false
   triesCount=0 ; maxTriesCount=10
   errorCount=0 ; maxErrorCount=5
   dbFileSize=0

   [ -s "$sqLiteDBaseFile" ] && \
   dbFileSize="$(ls -1l "$sqLiteDBaseFile" | awk -F ' ' '{print $3}')"
   if [ "$dbFileSize" -ge "$maxTrimSize" ]
   then vacuumOK=false ; cacheSize=10 ; fi
   timeNowSecs="$(date +'%s')"
   _SetSQLDBcmdsFile_
   trap '' HUP

   while [ "$((triesCount++))" -lt "$maxTriesCount" ] && [ "$errorCount" -lt "$maxErrorCount" ]
   do
      if "$sqLiteDBbinPath" "$sqLiteDBaseFile" < "$sqLiteDBCMDFile" >> "$sqLiteDBLOGFile" 2>&1
      then foundError=false ; foundLocked=false ; break ; fi
      errorCheck="$(tail -n1 "$sqLiteDBLOGFile")"
      echo "-----------------------------------" >> "$sqLiteDBLOGFile"
      printf "[$(date +"$logTimeFormat")] TRY_COUNT=[$triesCount]\n" | tee -a "$sqLiteDBLOGFile"
      if echo "$errorCheck" | grep -qE "^(Error:|Parse error|Runtime error)"
      then
         echo "$errorCheck"
         if echo "$errorCheck" | grep -qE "^Runtime error .*: database is locked"
         then foundLocked=true ; continue ; fi
         errorCount="$((errorCount + 1))" ; foundError=true ; foundLocked=false
         _ShowMemInfo_ 2 >> "$sqLiteDBLOGFile"
         _ShowSQLDBcmdsFile_ >> "$sqLiteDBLOGFile"
         if "$vacuumOK"
         then [ "$errorCount" -eq 1 ] && vacuumOK=false
         else [ "$errorCount" -eq 1 ] && limitSize=0
         fi
         if [ "$limitSize" -gt 0 ]
         then [ "$errorCount" -eq 2 ] && limitSize=0
         else [ "$errorCount" -eq 2 ] && cacheSize=5
         fi
         if [ "$cacheSize" -gt 5 ]
         then [ "$errorCount" -eq 3 ] && cacheSize=5
         else [ "$errorCount" -eq 3 ] && limitSize=1000
         fi
         if [ "$limitSize" -eq 1000 ]
         then maxErrorCount=4
         else [ "$errorCount" -eq 4 ] && limitSize=1000
         fi
         _SetSQLDBcmdsFile_
      fi
      [ "$triesCount" -ge "$maxTriesCount" ] && break
      [ "$errorCount" -ge "$maxErrorCount" ] && break
      sleep 1
   done

   if "$foundError"
   then resultStr="reported error(s)."
   elif "$foundLocked"
   then resultStr="found locked database."
   else
      resultStr="completed successfully."
      printf "[$(date +"$logTimeFormat")] TRY_COUNT=[$triesCount]\n" | tee -a "$sqLiteDBLOGFile"
      _ShowSQLDBcmdsFile_ >> "$sqLiteDBLOGFile"
   fi
   ! "$testDebug" && rm -f "$sqLiteDBCMDFile"

   _ShowMemInfo_ 1 >> "$sqLiteDBLOGFile"
   printf "[$(date +"$logTimeFormat")] Database trim process ${resultStr}\n" | tee -a "$sqLiteDBLOGFile"
   "$oldestRecsFound" && _LogOldestRecords_
   _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBLOGFile"
   printf "[$(date +"$logTimeFormat")] END.\n" >> "$sqLiteDBLOGFile"
}

runDebug=false
testDebug=false
vacuumOK=true
cacheSize=20
limitSize=2000
doSrceFrom=true
getOldestRecs=false
oldestRecsFound=false
recordsLimit=10
showTotalOnly=false
daysToKeepData=30
paramsError=false

if [ $# -eq 0 ] || [ -z "$1" ]
then
   printf "\nNO parameter was provided. "
   printf "Using default value of [$daysToKeepData] days.\n\n"
else
   for PARAM in "$@"
   do
      case "$PARAM" in
          "cache") cacheSize=10 ;;
          "novac") vacuumOK=false ;;
          "total") showTotalOnly=true
                   recordsLimit=-1 ;;
         "oldest") getOldestRecs=true ;;
                *) if echo "$PARAM" | grep -qE "^([0-9][0-9]{0,2})$"
                   then
                      daysToKeepData="$PARAM"
                   else
                      printf "\nINVALID parameter [$PARAM] was provided. Exiting...\n\n"
                      exit 0
                   fi
                   ;;
      esac
   done
fi

if ! "$getOldestRecs" && [ "$daysToKeepData" -lt 1 ]
then
   printf "\nINVALID parameter [$daysToKeepData] for days was provided. Exiting...\n\n"
   exit 0
fi

trap 'exit 0' INT QUIT ABRT TERM

"$getOldestRecs" && { _ShowOldestRecords_ ; exit 0 ; }
_TrimDatabase_
printf "\nLogfile [$sqLiteDBLOGFile] was created.\n"
exit 0

#EOF#
