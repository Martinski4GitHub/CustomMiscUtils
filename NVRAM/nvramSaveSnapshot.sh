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
# Last Modified: 2025-Sep-02 [Martinski W.]
# VERSION: 0.5.2
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
nvramShowFiltr0="([0-3]:.*|asd_.*|asdfile_.*|TM_EULA.*|ASUS.*EULA.*|Ate_.*|.*login_timestamp=)"
nvramShowFiltr1="(sys_uptime_now|rc_support|nc_setting_conf|buildinfo|setting_update_time)"
nvramShowFilter="^${nvramShowFiltr0}|^${nvramShowFiltr1}=|^$"

nvram show 2>/dev/null | grep -vE "$nvramShowFilter" | sort -u | sort -d -t '=' -k 1 > "$saveFilePath"

printf "\nNVRAM snapshot was saved to file:\n${saveFilePath}\n\n"

#EOF#
