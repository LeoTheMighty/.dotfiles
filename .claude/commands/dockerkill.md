Force quit all Docker processes and helpers so Docker can be reopened cleanly. This is useful when Docker is hung or out of space and won't respond to normal commands.

Run the following commands in sequence using the Bash tool. Report the output of each step to the user.

1. Send quit signal to Docker Desktop via AppleScript:
```
osascript -e 'quit app "Docker Desktop"' 2>/dev/null; osascript -e 'quit app "Docker"' 2>/dev/null; echo "Sent quit signal to Docker Desktop"
```

2. Force kill all Docker-related processes:
```
pkill -9 -f "Docker" 2>/dev/null; pkill -9 -f "com.docker" 2>/dev/null; pkill -9 -f "docker" 2>/dev/null; echo "Killed Docker processes"
```

3. Wait briefly then verify nothing is left:
```
sleep 2 && (pgrep -fl -i docker || echo "All Docker processes terminated successfully")
```

4. If `com.docker.vmnetd` is the only remaining process, that's fine — it's a privileged system helper managed by launchd that respawns automatically and won't block Docker from reopening.

5. Inform the user that Docker has been fully killed and they can now reopen it.
