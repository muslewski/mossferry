# Feature: ferry doctor against sandbox shims (no real ssh/mosh).
Output ../assets/demo-doctor.gif
Output build/demo-doctor.txt
Set Width 1000
Set Height 500
Hide
Type "export PS1='$ ' GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=true"
Enter
Type "clear"
Enter
Show
Type "ferry doctor"
Sleep 300ms
Enter
Sleep 4s
