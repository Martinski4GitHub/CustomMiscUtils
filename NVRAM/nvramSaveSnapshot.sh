#!/bin/sh
#####################################################################
# nvramSaveSnapshot.sh
#
# To save a snapshot of current NVRAM settings (in human-readable
# format) into a time-stamped file so that we can diff & compare 
# snapshots from different dates or different installed firmware
# versions.
#
# NOTE:
# The *OPTIONAL* FIRST parameter indicates a file name prefix
# to use when creating the file. If no parameter is given the 
# default prefix is "SavedNVRAM"
#
# Example calls:
#
#    nvramSaveSnapshot.sh  BEFORE_InstallReset
#    nvramSaveSnapshot.sh  AFTER_InstallReset

#    nvramSaveSnapshot.sh  BEFORE_CustomSetup
#    nvramSaveSnapshot.sh  AFTER_CustomSetup
#--------------------------------------------------------------------
# Creation Date: 2021-Jan-24 [Martinski W.]
# Last Modified: 2024-Mar-19 [Martinski W.]
#####################################################################
set -u

#-----------------------------------------------------------------
# The NVRAM snapshot file is saved in the current directory from
# which this script is called to execute. Modify the following 
# variable if you want to save the file into a specific path.
#-----------------------------------------------------------------
saveDirPath="$(pwd)"

#-----------------------------------------------------------------
# OPTIONAL FIRST parameter indicates a file name prefix.
#-----------------------------------------------------------------
if [ $# -gt 0 ] && [ -n "$1" ]
then fileNamePrefix="$1"
else fileNamePrefix="SavedNVRAM"
fi

fileDateTime="%Y-%m-%d_%H-%M-%S"
savefileName="${fileNamePrefix}_$(date +"$fileDateTime").txt"
saveFilePath="${saveDirPath}/$savefileName"
filterStr="([0-3]:.*|ASUS_EULA_time=|TM_EULA_time=|sys_uptime_now=|asdfile_ip_chksum=|asdfile_dns_chksum=|buildinfo=|nc_setting_conf=|rc_support=)"

nvram show 2>/dev/null | grep -vE "^$filterStr" | sort -d -t '=' -k 1 > "$saveFilePath"

printf "\nNVRAM snapshot was saved to file:\n${saveFilePath}\n\n"

#EOF#
