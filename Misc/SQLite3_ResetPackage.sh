#!/bin/sh
###################################################################
# SQLite3_ResetPackage.sh
# To remove SQlite3 Entware package and associated dependencies,
# and then reinstall them just in case binaries are corrupted.
#
# Creation Date: 2025-Jun-10 [Martinski W.]
# Last Modified: 2025-Oct-31 [Martinski W.]
###################################################################
set -u

readonly VERSION=0.1.7
readonly OPKG_CMD="/opt/bin/opkg"
readonly SQLITE3_CMD="/opt/bin/sqlite3"
readonly LDLIB_CMD="/lib/ld-linux-aarch64.so.1"
if [ -z "$(which crontab)" ]
then readonly cronListCmd="cru l"
else readonly cronListCmd="crontab -l"
fi

printf "\nChecking SQLite3 Entware package...\n"
if [ ! -x "$OPKG_CMD" ]
then
    printf "\n**ERROR**: Entware is NOT found installed.\n"
    exit 1
fi
if [ ! -x "$SQLITE3_CMD" ] || \
   ! $OPKG_CMD list-installed | grep -q "^sqlite3"
then
    printf "\nSQlite3 Entware package is NOT found installed.\n"
    exit 0
fi

printf "\nCurrently installed SQLite3 Entware package:\n"
$OPKG_CMD list-installed | grep -E "^(sqlite3|libsqlite3)"
$SQLITE3_CMD -version
[ -x "$LDLIB_CMD" ] && "$LDLIB_CMD" --list "$SQLITE3_CMD"

for scriptFName in connmon ntpmerlin spdmerlin uiDivStat dn-vnstat
do
    scriptFPath="/jffs/scripts/$scriptFName"
    [ ! -s "$scriptFPath" ] && continue
    cronJobTags="$($cronListCmd l | grep "${scriptFPath} " | awk -F' ' '{print $NF}')"
    [ -z "$cronJobTags" ] && continue
    echo
    for theCronTag in $cronJobTags
    do
        theCronTag="$(echo "$theCronTag" | cut -d'#' -f2)"
        printf "Removing Cron Job [$theCronTag]...\n"
        cru d "$theCronTag" ; sleep 2
    done
done

printf "\nRemoving SQLite3 Entware package...\n"
sleep 3
$OPKG_CMD remove sqlite3-cli libsqlite3 --force-removal-of-dependent-packages
sleep 3

printf "\nReinstalling SQLite3 Entware package...\n"
$OPKG_CMD update
$OPKG_CMD install sqlite3-cli

printf "\nReinstalled SQLite3 Entware package:\n"
$OPKG_CMD list-installed | grep -E "^(sqlite3|libsqlite3)"
$SQLITE3_CMD -version
[ -x "$LDLIB_CMD" ] && "$LDLIB_CMD" --list "$SQLITE3_CMD"

printf "\nCompleted. As the final step, the router must be rebooted.\n"

printf "\nDo you want to reboot the router right now? [y|n]: "
read -r YESorNO
if echo "$YESorNO" | grep -qE "^([Yy](es)?|YES)$"
then
    printf "\nOK. Rebooting...\n\n"
    /sbin/service reboot
else
    echo "NO"
    printf "\nPlease reboot the router at your convenience.\n\n"
fi
exit 0

#EOF#
