# Live test, part 4: delete everything so the cost stays at $0.
# Run by a HUMAN from the repo root (the agent is not allowed to destroy):
#   vhs demo/tapes/07-live-destroy.tape
Output "demo-videos/07-live-destroy.mp4"

Set Shell "bash"
Set FontSize 18
Set Width 1400
Set Height 900
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "export PS1='\[\e[1;36m\]agentic-devops-platform\[\e[0m\] $ ' && clear"
Enter
Show

Type "# Clean up: delete the live test resources (a human runs this)"
Enter
Sleep 1s
Type "terraform -chdir=terraform/envs/live-test destroy -no-color"
Enter
Sleep 20s
Type "yes"
Enter
Sleep 40s
Type "# Nothing left running, nothing left to pay for."
Enter
Sleep 4s
