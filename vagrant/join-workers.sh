#!/bin/bash
set -e

CRI_SOCKET="unix:///run/containerd/containerd.sock"
MAX_WAIT=300 # seconds
WAITED=0

# Wacht tot join-command.sh beschikbaar is met timeout
while [ ! -f /vagrant/join-command.sh ]; do
	if [ ${WAITED} -ge ${MAX_WAIT} ]; then
		echo "join-command.sh niet ontvangen binnen ${MAX_WAIT}s" >&2
		exit 1
	fi
	echo "Wachten op join-command.sh van master..."
	sleep 5
	WAITED=$((WAITED + 5))
done

# Voer de join command uit met expliciete CRI socket
bash /vagrant/join-command.sh --cri-socket ${CRI_SOCKET}
