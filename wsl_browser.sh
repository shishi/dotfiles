#! /bin/sh

# firefox
# BROWSER="/mnt/c/Program Files/Mozilla Firefox/firefox.exe"

# chrome
# BROWSER="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" 

# vivaldi
BROWSER="/mnt/c/Users/shishi/AppData/Local/Vivaldi/Application/vivaldi.exe"

# if need file URI pattern
if echo $0 | grep -q "wsl_browser.sh"; then
  "$BROWSER" "file:////wsl$/Ubuntu${1}"
  exit 0
fi

"$BROWSER" $1
