#!/bin/sh
###############################################################
# Last Modified: Martinski W. [2025-Apr-02]
###############################################################
set -u

WEB_PAGE_DIR="$(readlink -f /www/user)"
TEMP_MENU_TREE="/tmp/menuTree.js"
DIV_WEBGUI_DIR="/opt/share/diversion/webui"
DIV_WEBGUI_PAGE="${DIV_WEBGUI_DIR}/index.asp"
DIV_WEBGUI_DLPGE="${DIV_WEBGUI_PAGE}.DLPGE"

_Remove_WebGUI_Page_()
{
   theWebUIFileStr="$(grep -oF 'Diversion Ad-Blocking' "${WEB_PAGE_DIR}"/user*.asp)"
   if [ -z "$theWebUIFileStr" ]
   then echo "**ERROR**: Diversion WebUI page NOT found." ; return 1
   fi
   theWebFilePath="$(echo "$theWebUIFileStr" | head -n1 | awk -F ':' '{print $1}')"
   if [ -z "$theWebFilePath" ]
   then echo "**ERROR**: Diversion WebUI file NOT found." ; return 1
   fi
   theWebUIPage="${theWebFilePath##*/}"
   if [ -s "$TEMP_MENU_TREE" ] && \
      grep -qE "\{url: \"$theWebUIPage\", tabName: \"Diversion\"" "$TEMP_MENU_TREE"
   then
       echo "Replacing [$theWebUIPage] WebUI tab for Diversion..."
       rm -f "${WEB_PAGE_DIR}/$theWebUIPage"
       sed -i "\\~$theWebUIPage~d" "$TEMP_MENU_TREE"
       echo "Completed."
       return 0
   else
       echo "**ERROR**: Diversion WebUI tab NOT found."
       return 1
   fi
}

_Download_WebGUI_Page_()
{
   curl -LSs --retry 4 --retry-delay 5 --retry-connrefused \
   https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/develop/Misc/webguiDiversion.asp \
   -o "$DIV_WEBGUI_DLPGE" && chmod 666 "$DIV_WEBGUI_DLPGE"
   if [ ! -s "$DIV_WEBGUI_DLPGE" ] || grep -iq "^404: Not Found" "$DIV_WEBGUI_DLPGE"
   then
       rm -f "$DIV_WEBGUI_DLPGE"
       echo "**ERROR**: Unable to download the Diversion WebUI page."
       return 1
   fi
   echo "Downloaded modified Diversion WebUI page."
   mv -f "$DIV_WEBGUI_DLPGE" "$DIV_WEBGUI_PAGE"
   return 0
}

if _Download_WebGUI_Page_
then
   _Remove_WebGUI_Page_
   sh "${DIV_WEBGUI_DIR}/process.div" mount &
fi

#EOF#
