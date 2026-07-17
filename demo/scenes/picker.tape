# Hero: global session picker — wide boat banner + fzf list + cycle navigation.
# COLUMNS=160 (hidden): picker header uses 40% of cols for the banner
# (≥52 → boat+figlet wide tier). vhs is a real pty so GREEN_UI_FORCE_TTY
# is not required; no env-var noise may appear in any visible frame.
Output ../assets/demo-picker.gif
Output build/demo-picker.txt
Set Width 1200
Set Height 640
Hide
Type "export PS1='$ ' COLUMNS=160 LINES=40"
Enter
Type "clear"
Enter
Show
Type "ferry"
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
