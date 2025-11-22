#!/bin/sh
###################################################################################
# Show_GuestNetwork_Info.sh
#
# To show Guest Network Pro information using built-in commands and
# NVRAM variables (data is available ONLY in newer F/W versions).
#--------------------------------------------------------------------
# Creation Date: 2025-Aug-23 [Martinski W.]
# Last Modified: 2025-Sep-01 [Martinski W.]
###################################################################################
set -u

readonly VERSION="0.4.1"
readonly VLAN_List="$(nvram get vlan_rl | sed 's/></\n/g;s/</\n/g;s/>$//g;s/>/,/g' | sed '/^$/d')"

#----------------------------------------------------------------------#
_Show_NVRAM_sdn_rl_INFO_()
{
    local nvramValue="$(nvram get sdn_rl)"

    printf "\nUsing 'sdn_rl' NVRAM var as primary source of info:"
    printf "\n---------------------------------------------------\n"
    if [ -z "$nvramValue" ]
    then
        echo "NVRAM value *NOT* found." ; return 1
    fi
    printf "SDNidx  VLANidx  NETidx  APGidx  SDN_TYPE  SDN_Enabled  VLAN_ID  SSID\n"

    while read -r SDN_IDX SDN_TYPE SDN_Enabled VLAN_IDX NET_IDX APG_IDX theREST && [ -n "$SDN_IDX" ]
    do
        SSID="$(nvram get "apg${APG_IDX}_ssid")"
        VLAN_ID="$(echo "$VLAN_List" | grep -E "^${VLAN_IDX},[1-9]+" | cut -d',' -f2)"
        [ -z "$SSID" ] && SSID="UNKNOWN" ; [ -z "$VLAN_ID" ] && VLAN_ID="NONE"
        [ "$SDN_TYPE" = "Customized" ] && SDN_TYPE="Custom"
        printf "%3d%6s%3d%5s%3d%5s%3d" "$SDN_IDX" '' "$VLAN_IDX" '' "$NET_IDX" '' "$APG_IDX"
        printf "%5s%-7s%3s%4s%9s%5s%4s%s\n" '' "$SDN_TYPE" '' "$SDN_Enabled" '' "$VLAN_ID" '' "$SSID"
    done <<EOT
$(echo "$nvramValue" | sed 's/></\n/g;s/</\n/g;s/>$//g;s/>/ /g' | sed '/^$/d')
EOT
}

#----------------------------------------------------------------------#
_Show_NVRAM_subnet_rl_INFO_()
{
    local nvramValue="$(nvram get subnet_rl)"

    printf "\nUsing 'subnet_rl' NVRAM var as primary source of info:"
    printf "\n------------------------------------------------------\n"
    if [ -z "$nvramValue" ]
    then
        echo "NVRAM value *NOT* found." ; return 1
    fi
    printf "NETidx  IFACE_ID  VLAN_ID  Network_Address  Network_Mask    DHCP_Enabled  DHCP_IP_Start    DHCP_IP_End     DHCP_Lease  SSID\n"

    while read -r NET_IDX IFACE_ID GW_Addr NET_Mask DHCP_Enabled DHCP_IP_Start DHCP_IP_End DHCP_Lease theREST && [ -n "$NET_IDX" ]
    do
        SSID="$(nvram get "apg${NET_IDX}_ssid")"
        VLAN_ID="$(echo "$VLAN_List" | grep -E "^${NET_IDX},[1-9]+" | cut -d',' -f2)"
        [ -z "$SSID" ] && SSID="UNKNOWN" ; [ -z "$VLAN_ID" ] && VLAN_ID="NONE"
        printf "%3d%7s%-5s%3s%5s%4s%-15s%2s%-15s" "$NET_IDX" '' "$IFACE_ID" '' "$VLAN_ID" '' "$GW_Addr" '' "$NET_Mask"
        printf "%4s%2d%9s%-15s%2s%-15s%2s%7d%4s%s\n" '' "$DHCP_Enabled" '' "$DHCP_IP_Start" '' "$DHCP_IP_End" '' "$DHCP_Lease" '' "$SSID"
    done <<EOT
$(echo "$nvramValue" | sed 's/></\n/g;s/</\n/g;s/>$//g;s/>/ /g' | sed '/^$/d')
EOT
}

#----------------------------------------------------------------------#
_Show_CMD_get_mtlan_INFO_()
{
    local endSepStr="------------------------------"
    local NET_ENABLED  NET_TYPE  IFaceNAME  IFaceNAMEbr
    local SDN_IDX  APG_IDX  NET_IDX  GW_Addr  NET_Addr  NET_Mask
    local DHCP_Enabled  DHCP_IP_Start  DHCP_IP_End  DHCP_Lease

    _GetBracketedInfo_() { echo "$1" | awk -F'[][]' '{print $2}' ; }

    _ShowNetworkInfo_()
    {
        SSID="$(nvram get "apg${APG_IDX}_ssid")"
        VLAN_ID="$(echo "$VLAN_List" | grep -E "^${NET_IDX},[1-9]+" | cut -d',' -f2)"
        [ -z "$SSID" ] && SSID="UNKNOWN" ; [ -z "$VLAN_ID" ] && VLAN_ID="NONE"
        printf "%3d%6s%-3s%4s%-3s%3s%-5s%2s%-5s" "$SDN_IDX" '' "$APG_IDX" '' "$NET_IDX" '' "$IFaceNAME" '' "$IFaceNAMEbr"
        printf "%1s%5s%3s%-7s%4s%-4s%3s%-15s%1s%-15s" '' "$VLAN_ID" '' "$NET_TYPE" '' "$NET_ENABLED" '' "$NET_Addr" '' "$NET_Mask"
        printf "%3s%2d%7s%-15s%1s%-15s%2s%7d%2s%s\n" '' "$DHCP_Enabled" '' "$DHCP_IP_Start" '' "$DHCP_IP_End" '' "$DHCP_Lease" '' "$SSID"
    }

    printf "\nUsing 'get_mtlan' command as primary source of info:"
    printf "\n----------------------------------------------------\n"
    if [ -z "$(which get_mtlan)" ]
    then
        echo "F/W built-in command 'get_mtlan' *NOT* found." ; return 1
    fi
    printf "SDNidx APGidx NETidx IFname BRname VLAN_ID NETtype IFenabled "
    printf "Network_Address Network_Mask   DHCPenabled DHCP_IP_Start   DHCP_IP_End     DHCPlease SSID\n"

    while read -r theLINE 
    do
        if echo "$theLINE" | grep -q "^$endSepStr"
        then
            _ShowNetworkInfo_ ; continue
        fi

        case "$theLINE" in
            "|-enable:["*)
                NET_ENABLED="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-name:["*)
                NET_TYPE="$(_GetBracketedInfo_ "$theLINE")"
                [ "$NET_TYPE" = "Customized" ] && NET_TYPE="Custom";;
            "|-idx:["*)
                NET_IDX="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-ifname:["*)
                IFaceNAME="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-br_ifname:["*)
                IFaceNAMEbr="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-addr:["*)
                GW_Addr="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-subnet:["*)
                NET_Addr="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-netmask:["*)
                NET_Mask="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-dhcp_enable:["*)
                DHCP_Enabled="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-dhcp_min:["*)
                DHCP_IP_Start="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-dhcp_max:["*)
                DHCP_IP_End="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-dhcp_lease:["*)
                DHCP_Lease="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-sdn_idx:["*)
                SDN_IDX="$(_GetBracketedInfo_ "$theLINE")" ;;
            "|-apg_idx:["*)
                APG_IDX="$(_GetBracketedInfo_ "$theLINE")" ;;
            *) ;; #IGNORED#
       esac
    done <<EOT
$(get_mtlan)
EOT
}

_Show_NVRAM_sdn_rl_INFO_
_Show_NVRAM_subnet_rl_INFO_
_Show_CMD_get_mtlan_INFO_
echo

#EOF#
