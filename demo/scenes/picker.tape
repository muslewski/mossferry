# Hero: global session picker — wide boat banner + fzf list + cycle navigation.
# COLUMNS=160 on the command line: picker header uses 40% of cols for the
# banner (≥52 → boat+figlet wide tier). ttyd overwrites shell COLUMNS from
# pixel size; the env-prefix survives into repo-session via the mosh stub.
Output ../assets/demo-picker.gif
Output build/demo-picker.txt
Set Width 1200
Set Height 640
Hide
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show
Type "COLUMNS=160 LINES=40 GREEN_UI_FORCE_TTY=1 ferry"
Sleep 400ms
Enter
Sleep 2500ms
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 700ms
Up
Sleep 700ms
Down
Sleep 900ms
Escape
Sleep 800ms
