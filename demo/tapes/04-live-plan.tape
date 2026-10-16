# Live test, part 1: show what will be created in AWS (read-only).
# Run from the repo root:  vhs demo/tapes/04-live-plan.tape
Output "demo-videos/04-live-plan.mp4"

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

Type "# Live test: real AWS DynamoDB + IAM, no EKS (about $0). Who am I?"
Enter
Sleep 1s
Type "aws sts get-caller-identity --query Account --output text | sed 's/.*\(....\)$/account ****\1/'"
Enter
Sleep 3s
Type "# What will Terraform create? (plan only, nothing changes)"
Enter
Sleep 1s
Type "terraform -chdir=terraform/envs/live-test plan -no-color | grep -E '^  # |Plan:'"
Enter
Sleep 25s
