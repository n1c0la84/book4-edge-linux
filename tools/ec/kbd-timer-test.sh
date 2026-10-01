#!/bin/bash
# Does resending the SAME backlight command restart the EC's timer?
# Don't touch the keyboard during the test (the driver resends on key presses).
#   bash tools/ec/kbd-timer-test.sh
set -u
T=$(dirname "$0")/kbd-backlight.py
sudo -v || exit 1
clock() { # print t=N every second for $1 seconds, starting at $2
    for i in $(seq "$2" $(( $2 + $1 - 1 ))); do printf '\r  t=%2ds ' "$i"; sleep 1; done; }

echo "TEST A: level 3, timeout 10 at t=0, the SAME command again at t=7."
echo "        Note the time the light goes off: t=10 -> identical command ignored, t=17 -> timer restarted."
sudo python3 $T 3 10 >/dev/null; clock 7 0
sudo python3 $T 3 10 >/dev/null; printf '\r  t= 7s  (resent 3 10)\n'; clock 15 7; echo
sleep 3
echo "TEST B: level 3, timeout 10 at t=0, then timeout 11 (different command) at t=7."
echo "        Light off at t=10 -> commands don't restart the timer; t=18 -> a changed command does."
sudo python3 $T 3 10 >/dev/null; clock 7 0
sudo python3 $T 3 11 >/dev/null; printf '\r  t= 7s  (sent 3 11)\n'; clock 15 7; echo
echo "done - tell me the two times"
