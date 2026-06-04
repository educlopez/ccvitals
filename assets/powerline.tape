# ccvitals — VHS tape for assets/powerline.png
# Regenerate with:
#   vhs assets/powerline.tape
#   ffmpeg -y -sseof -0.3 -i assets/powerline-scratch.gif -update 1 -frames:v 1 assets/powerline.png
#   rm assets/powerline-scratch.gif

Output assets/powerline-scratch.gif

Set FontSize 16
Set Width 1300
Set Height 230
Set Padding 20
Set Theme "Catppuccin Mocha"

Hide
Type "clear && ./assets/powerline-preview.sh"
Enter
Sleep 3s
Show
Sleep 1s
