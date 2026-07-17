# Feature: ferry --help banner (local, no connection).
# head -n 20 keeps the wide boat lockup + Usage in the viewport and stops
# before Examples (runtime help hardcodes a banned host name there).
# Short env prefix keeps typing time down so the banner is on screen longer.
Output ../assets/demo-help.gif
Output build/demo-help.txt
Set Width 1000
Set Height 500
Hide
Type "export PS1='$ ' COLUMNS=100 GREEN_UI_FORCE_TTY=1"
Enter
Type "clear"
Enter
Show
Type "ferry --help | head -n 20"
Sleep 300ms
Enter
Sleep 5s
