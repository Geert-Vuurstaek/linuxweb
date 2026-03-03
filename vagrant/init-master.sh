#!/bin/bash
set -e

MASTER_IP=192.168.56.10
POD_CIDR=10.244.0.0/16
CRI_SOCKET="unix:///run/containerd/containerd.sock"

# Only run on master
if [ "$(hostname)" = "k8s-master" ]; then
  kubeadm init \
    --apiserver-advertise-address=${MASTER_IP} \
    --pod-network-cidr=${POD_CIDR} \
    --cri-socket ${CRI_SOCKET}

  mkdir -p /home/vagrant/.kube
  cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config

  # Install Flannel CNI
  su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"

  # Save join command for workers
  kubeadm token create --print-join-command > /vagrant/join-command.sh
  chmod +x /vagrant/join-command.sh
fi
