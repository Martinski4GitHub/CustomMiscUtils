#!/bin/sh
###################################################################
# SQLite3_Trim_TEST.sh
# Creation Date: 2024-Oct-20 [Martinski W.]
# Last Modified: 2024-Oct-23 [Martinski W.]
###################################################################

VERSION="0.1.4"

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
readonly _1_0_GB_="1073741824"
readonly _1_5_GB_="1610612736"
readonly _2_0_GB_="2147483648"
readonly maxTrimSize="$_2_0_GB_"

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

_ShowSQLDBcmdsFile_()
{
  cat "$sqLiteDBcmdFile"
  echo "=========================================================="
}

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
   echo "----------------------------------------"
}

_TrimDatabase_()
{
   local timeNowSecs  dbFileSize  triesCount  maxTriesCount  resultStr
   local errorCheck  errorCount  maxErrorCount  foundError  foundLocked

   if [ -s "$sqLiteDBlogFile" ]
   then
       cp -fp "$sqLiteDBlogFile" "${sqLiteDBlogFile}.BAK"
       rm -f "$sqLiteDBlogFile"
   fi
   touch "$sqLiteDBlogFile"

   TZ="$(cat /etc/TZ)"
   export TZ

   printf "[$(date +"$logTimeFormat")] BEGIN.\n" >> "$sqLiteDBlogFile"
   _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBlogFile"
   printf "[$(date +"$logTimeFormat")] Trimming records older than [$daysToKeepData] days from database.\n" | tee -a "$sqLiteDBlogFile"
   echo "----------------------------------------------------------" >> "$sqLiteDBlogFile"
   _ShowMemInfo_ 1 >> "$sqLiteDBlogFile"

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
      if "$sqLiteDBbinPath" "$sqLiteDBaseFile" < "$sqLiteDBcmdFile" >> "$sqLiteDBlogFile" 2>&1
      then foundError=false ; foundLocked=false ; break ; fi
      errorCheck="$(tail -n1 "$sqLiteDBlogFile")"
      echo "-----------------------------------" >> "$sqLiteDBlogFile"
      printf "[$(date +"$logTimeFormat")] TRY_COUNT=[$triesCount]\n" | tee -a "$sqLiteDBlogFile"
      if echo "$errorCheck" | grep -qE "^(Error:|Parse error|Runtime error)"
      then
         echo "$errorCheck"
         if echo "$errorCheck" | grep -qE "^Runtime error .*: database is locked"
         then foundLocked=true ; continue ; fi
         errorCount="$((errorCount + 1))" ; foundError=true ; foundLocked=false
         _ShowMemInfo_ 2 >> "$sqLiteDBlogFile"
         _ShowSQLDBcmdsFile_ >> "$sqLiteDBlogFile"
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
      printf "[$(date +"$logTimeFormat")] TRY_COUNT=[$triesCount]\n" | tee -a "$sqLiteDBlogFile"
      _ShowSQLDBcmdsFile_ >> "$sqLiteDBlogFile"
   fi
   ! "$doDebug" && rm -f "$sqLiteDBcmdFile"

   _ShowMemInfo_ 1 >> "$sqLiteDBlogFile"
   printf "[$(date +"$logTimeFormat")] Database trim process ${resultStr}\n" | tee -a "$sqLiteDBlogFile"
   _ShowSQLDBfileInfo_ "$sqLiteDBaseFile" | tee -a "$sqLiteDBlogFile"
   printf "[$(date +"$logTimeFormat")] END.\n" >> "$sqLiteDBlogFile"
}

doDebug=false
vacuumOK=true
cacheSize=20
limitSize=2000
doSrceFrom=true
daysToKeepData=30

if [ $# -eq 0 ] || [ -z "$1" ]
then
   printf "\nNO parameter was provided. "
   printf "Using default value of [$daysToKeepData] days.\n\n"
else
   for PARAM in "$@"
   do
      case "$PARAM" in
          "debug") doDebug=true ;;
          "cache") cacheSize=10 ;;
          "novac") vacuumOK=false ;;
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

trap 'exit 0' INT QUIT ABRT TERM
_TrimDatabase_
printf "\nLogfile [$sqLiteDBlogFile] was created.\n"
exit 0

#EOF#
