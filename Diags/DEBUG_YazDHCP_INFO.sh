#!/bin/sh
###########################################################
# DEBUG_YazDHCP_INFO.sh
# Last Modified: 2025-Oct-19 [Martinski W.]
#----------------------------------------------------------
set -u
readonly VERSION="0.5.2"

readonly MACaddr_RegEx="([a-fA-F0-9]{2}([:][a-fA-F0-9]{2}){5})"
readonly allNetIFaces0RegExp="(wl[0-3][.][1-3]|br[0-9][0-9]?)"
readonly allNetIFaces1RegExp="${allNetIFaces0RegExp}[[:blank:]]* Link encap:"
readonly allNetIFaces2RegExp="dev[[:blank:]]* ${allNetIFaces0RegExp}[[:blank:]]* proto kernel"
readonly nvramFindRegExp="(lan_ifname|lan_ipaddr|lan_netmask|dhcp_enable_x|dhcp_start|dhcp_end|dhcp_staticlist)"

_GetDebugDataYazDHCP_()
{
   echo "========================================================"
   date +'%Y-%b-%d %I:%M:%S %p %Z'
   theScriptPATH="/jffs/scripts/YazDHCP"
   grep "^SCRIPT_BRANCH=" "$theScriptPATH"
   grep "^readonly SCRIPT_VERSION=" "$theScriptPATH"
   grep "^readonly SCRIPT_VERSTAG=" "$theScriptPATH"
   echo "F/W: $(nvram get firmver).$(nvram get buildno).$(nvram get extendno)"
   echo "========================================================"
   configsPATH="/jffs/configs"
   ls -1lA "$configsPATH"/dnsmasq*
   echo "--------------------------------------------------------"
   printf "DNSMasq*.conf.add\n"
   for theFile in $(ls -1 "$configsPATH"/dnsmasq* 2>/dev/null)
   do
       echo "++++++++++++++++++++++++++++++++++++++++++++++"
       echo "$theFile"
       echo "----------------------------------------------"
       grep -E "^(dhcp-hostsfile|dhcp-optsfile|addn-hosts)=" "$theFile"
   done
   echo "========================================================"
   theAddonsPATH="/jffs/addons/YazDHCP.d"
   ls -1lA "$theAddonsPATH"
   echo "========================================================"
   printf "DHCP_GuestNetInfo.conf\n----------------------\n"
   [ -s "$theAddonsPATH/DHCP_GuestNetInfo.conf" ] && \
   cat "$theAddonsPATH/DHCP_GuestNetInfo.conf"
   echo "========================================================"
   printf "GuestNetworkSubnetInfo.js\n-------------------------\n"
   [ -s "$theAddonsPATH/GuestNetworkSubnetInfo.js" ] && \
   cat "$theAddonsPATH/GuestNetworkSubnetInfo.js"
   echo "========================================================"
   printf "DHCP_clients\n------------\n"
   [ -s $theAddonsPATH/DHCP_clients ] && \
   cat $theAddonsPATH/DHCP_clients
   echo "========================================================"
   printf "Hostnames\n"
   for theFile in $(ls -1 "$theAddonsPATH"/.hostnames* 2>/dev/null)
   do
       echo "++++++++++++++++++++++++++++++++++++++++++++++"
       echo "$theFile"
       echo "----------------------------------------------"
       cat "$theFile"
   done
   echo "========================================================"
   printf "StaticList\n"
   for theFile in $(ls -1 "$theAddonsPATH"/.staticlist* 2>/dev/null)
   do
       echo "++++++++++++++++++++++++++++++++++++++++++++++"
       echo "$theFile"
       echo "----------------------------------------------"
       cat "$theFile"
   done
   echo "========================================================"
   printf "OptionsList\n"
   for theFile in $(ls -1 "$theAddonsPATH"/.optionslist* 2>/dev/null)
   do
       echo "++++++++++++++++++++++++++++++++++++++++++++++"
       echo "$theFile"
       echo "----------------------------------------------"
       cat "$theFile"
   done
   echo "========================================================"
   for theFile in $(ls -1 /etc/dnsmasq* 2>/dev/null)
   do
       echo "++++++++++++++++++++++++++++++++++++++++++++++"
       echo "$theFile"
       echo "----------------------------------------------"
       grep -E "^dhcp-range=.*,.*" "$theFile"
       echo "----------------------------------------------"
       grep -E "^dhcp-option=.*,(3|option:router),.*" "$theFile"
       echo "----------------------------------------------"
       grep -E "^no-dhcp-interface=.*" "$theFile"
       echo "----------------------------------------------"
       grep -E "^(addn-hosts|dhcp-optsfile|dhcp-hostsfile)=.*" "$theFile"
   done
   echo "========================================================"
   printf "IP Routes:\n-------------\n"
   ip route show | grep -E "$allNetIFaces2RegExp"
   echo "========================================================"
   printf "IF Config:\n-------------\n"
   ifconfig | grep -E -A1 "^$allNetIFaces1RegExp"
   echo "========================================================"
   printf "NVRAM:\n------\n"
   nvram show 2>/dev/null | grep -E "^${nvramFindRegExp}=" | sort -u
   echo "========================================================"
   top -b -n1 | grep "PID  PPID USER" | grep -v grep
   top -b -n1 | grep "dnsmasq --log" | grep -v grep
   top -b -n1 | grep "dnsmasq -C /etc/" | grep -v grep
   echo "========================================================"
}

theTAG="DEBUG"
addLOG=false
if [ $# -gt 0 ]
then
   if [ "$1" = "dolog" ]
   then
       addLOG=true
   elif [ "$1" = "nolog" ]
   then
       addLOG=false
   elif echo "$1" | grep -qE "^(before|after)$"
   then
       theTAG="$(echo "$1" | tr 'a-z' 'A-Z')"
   else
       printf "\nUNKNOWN Parameter [$*].\n"
       printf "Use either 'before' or 'after' parameter.\n"
       printf "Setting a 'DEBUG' tag for now.\n\n"
   fi
fi
logFILE="$HOME/YazDHCP_${theTAG:0:5}_$(date +'%Y%m%d_%H%M%S').LOG"

if ! "$addLOG"
then _GetDebugDataYazDHCP_
else _GetDebugDataYazDHCP_ | tee "$logFILE"
fi

if [ -s "$logFILE" ]
then
   cp -fp "$logFILE" "${logFILE}.ORIG.TXT"
   theMACs="$(grep -E "$MACaddr_RegEx" "$logFILE")"
   for macLINE in $theMACs
   do
       theMAC="$(echo "$macLINE" | grep -oE "$MACaddr_RegEx" | sort -u)"
       [ -z "$theMAC" ] && continue
       newMAC="$(echo "$theMAC" | awk -F':' '{printf "XX:XX:XX:%s:%s:%s" $6,$4,$5}')"
       sed -i "s/${theMAC}/${newMAC}/g" "$logFILE"
   done
   printf "\nDebug file '$logFILE' was created.\n\n"
fi

#EOF#
