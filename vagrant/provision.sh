#!/bin/bash
set -euo pipefail

# --- Variables ---
K8S_VERSION="v1.29"
K8S_REPO="https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/"
USER="vagrant"

retry_apt_update() {
    local tries=0
    until apt-get update; do
        tries=$((tries + 1))
        if [ ${tries} -ge 5 ]; then
            echo "[ERROR] apt-get update failed after ${tries} attempts" >&2
            return 1
        fi
        echo "[WARN] apt-get update failed, retrying in 5s..." >&2
        sleep 5
    done
}

echo "[INFO] Installing prerequisites..."
retry_apt_update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# --- Disable swap (required by kubeadm) ---
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab
echo "[INFO] Swap disabled."

# --- Load required kernel modules and configure sysctl ---
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system
echo "[INFO] Kernel modules loaded and sysctl configured."

# --- Install containerd (CRI) ---
if ! command -v containerd &> /dev/null; then
    echo "[INFO] Installing containerd..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    retry_apt_update
    apt-get install -y containerd.io
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    # Zorg dat de CRI plugin niet uitgeschakeld is
    sed -i 's/disabled_plugins = \["io.containerd.grpc.v1.cri"\]/disabled_plugins = []/' /etc/containerd/config.toml
    systemctl enable --now containerd
    systemctl restart containerd
    echo "[INFO] containerd installed and configured for systemd cgroups."
fi

# --- Install Kubernetes binaries via pkgs.k8s.io (stable channel) ---
if ! command -v kubeadm &> /dev/null; then
    echo "[INFO] Installing kubeadm/kubelet/kubectl from pkgs.k8s.io..."
    rm -f /etc/apt/sources.list.d/kubernetes.list
    mkdir -p /etc/apt/keyrings
    curl -fsSL --retry 5 --retry-delay 5 ${K8S_REPO}Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_REPO} /" \
        > /etc/apt/sources.list.d/kubernetes.list
    retry_apt_update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

systemctl enable --now kubelet

NODE_IP=$(ip -4 -o addr show | awk '$4 ~ /^192\.168\.56\./ {split($4,a,"/"); print a[1]; exit}')
if [ -n "${NODE_IP}" ]; then
    cat <<EOF >/etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF
    systemctl daemon-reload
    systemctl restart kubelet
    echo "[INFO] kubelet configured with node-ip ${NODE_IP}."
else
    echo "[WARN] Could not detect host-only 192.168.56.x IP; kubelet node-ip not overridden."
fi

echo "[SUCCESS] Container runtime and Kubernetes components installed."