# Live test, part 3: run the live test suite against real AWS.
# Run from the repo root, with Python 3.12 + app/requirements-dev.txt available:
#   PYTHON=/path/to/python3.12 vhs demo/tapes/06-live-tests.tape
Output "demo-videos/06-live-tests.mp4"

Set Shell "bash"
Set FontSize 17
Set Width 1400
Set Height 900
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "export PS1='\[\e[1;36m\]agentic-devops-platform\[\e[0m\] $ ' && clear"
Enter
Show

Type "# Everything runs as the app's least-privilege role, like a pod with IRSA."
Enter
Type "# It must be ALLOWED its own table and DENIED everything else."
Enter
Sleep 1s
Type "bash scripts/live-test.sh"
Enter
Sleep 30s
