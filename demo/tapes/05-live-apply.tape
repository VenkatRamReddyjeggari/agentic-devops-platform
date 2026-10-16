# Live test, part 2: create the resources in AWS.
# Run by a HUMAN from the repo root (the agent is not allowed to apply):
#   vhs demo/tapes/05-live-apply.tape
Output "demo-videos/05-live-apply.mp4"

Set Shell "bash"
Set FontSize 18
Set Width 1400
Set Height 900
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "export PS1='\[\e[1;36m\]agentic-devops-platform\[\e[0m\] $ ' && terraform -chdir=terraform/envs/live-test init -input=false >/dev/null && clear"
Enter
Sleep 8s
Show

Type "# A human applies: create the tables and the least-privilege app role"
Enter
Sleep 1s
Type "terraform -chdir=terraform/envs/live-test apply -no-color"
Enter
Sleep 25s
Type "yes"
Enter
Sleep 45s
Type "terraform -chdir=terraform/envs/live-test output -no-color | sed -E 's/[0-9]{12}/************/'"
Enter
Sleep 6s
