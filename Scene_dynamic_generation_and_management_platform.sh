#!/bin/bash

# 配置网卡（需确认实际网卡名是否为 ens33）
cat > /etc/sysconfig/network-scripts/ifcfg-ens33 <<EOF
TYPE=Ethernet
BOOTPROTO=static
IPADDR=192.168.1.10
NETMASK=255.255.255.0
GATEWAY=192.168.1.2
DNS1=8.8.8.8
DNS2=8.8.4.4
ONBOOT=yes
EOF

# 添加主机映射
cat >> /etc/hosts <<EOF
192.168.1.10 master
192.168.1.20 elk
192.168.1.30 caldera
192.168.1.40 wazuh

EOF

# 替换为阿里云 CentOS 镜像
cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
curl -L -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum makecache

# 设置主机名
hostnamectl set-hostname master

# 禁用 swap
swapoff -a
sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

# 关闭防火墙
systemctl disable --now firewalld

# 启用 br_netfilter 模块
modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/profile

# 写入 sysctl 设置
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# 安装时间同步
yum install -y ntp ntpdate
ntpdate cn.pool.ntp.org
systemctl enable --now ntpd

# 添加 Kubernetes 镜像源
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
EOF

# 安装 Docker 依赖并添加源
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 或使用 Docker 官方源
cat > /etc/yum.repos.d/docker-ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://download.docker.com/linux/centos/7/x86_64/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF

# 安装 Docker 和 containerd.io（确保 containerd.io 匹配版本）
yum install -y docker-ce-20.10.9-3.el7 docker-ce-cli-20.10.9-3.el7 docker-compose-plugin containerd.io

# 配置 Docker
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker-0.unsee.tech",
    "https://docker.hlmirror.com"
  ]
}
EOF

# 启动 Docker
systemctl daemon-reexec
systemctl enable --now docker

# 安装 Kubernetes 组件（确保版本可用）
yum install -y kubelet-1.23.17 kubeadm-1.23.17 kubectl-1.23.17
systemctl enable kubelet

# 初始化 Master 节点
kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --control-plane-endpoint=cluster-endpoint \
  --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.17 \
  --service-cidr=10.96.0.0/12 \
  --pod-network-cidr=172.20.0.0/16

# 保存 join 命令
kubeadm token create --ttl 0 --print-join-command > /root/key.txt

# 配置 kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chmod 600 $HOME/.kube/config

# 下载 Calico 网络插件并修改子网段
curl -O https://docs.projectcalico.org/v3.15/manifests/calico.yaml
sed -i '/^[[:space:]]*#*[[:space:]]*- name: CALICO_IPV4POOL_CIDR/,+1{
    s/^#*//
    s|value:.*|value: "172.20.0.0/16"|
}' calico.yaml

# 应用 Calico
kubectl apply -f calico.yaml

# 查看 Pod 状态
kubectl get pod -A

