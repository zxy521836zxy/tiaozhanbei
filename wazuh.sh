
#!/bin/bash

set -e

# 1. 配置静态网络
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-ens33
TYPE=Ethernet
BOOTPROTO=static
IPADDR=192.168.1.40
NETMASK=255.255.255.0
GATEWAY=192.168.1.2
DNS1=8.8.8.8
DNS2=8.8.4.4
ONBOOT=yes
EOF

# 2. 主机名 & hosts 配置
hostnamectl set-hostname wazuh
cat <<EOF >> /etc/hosts

192.168.1.10 master
192.168.1.20 elk
192.168.1.30 caldera
192.168.1.40 wazuh
EOF

# 3. 使用阿里云 YUM 源
cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
curl -L -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

# 4. 禁用 swap
swapoff -a
sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

# 5. 关闭防火墙
systemctl disable firewalld --now

# 6. 内核参数
modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/profile

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

# 7. 时间同步
yum install -y ntp ntpdate
ntpdate cn.pool.ntp.org
systemctl enable --now ntpd

# 8. 安装 Docker
yum install -y yum-utils device-mapper-persistent-data lvm2

yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

cat <<EOF > /etc/yum.repos.d/docker-ce.repo
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://download.docker.com/linux/centos/7/x86_64/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF

yum install -y docker-ce-20.10.9-3.el7 docker-ce-cli-20.10.9-3.el7 docker-compose-plugin containerd.io

systemctl enable --now docker

# Docker 加速器 & Cgroup 驱动设置
cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker-0.unsee.tech",
    "https://docker.hlmirror.com"
  ]
}
EOF

systemctl daemon-reload
systemctl restart docker

# 9. 安装 Kubernetes 组件（可选）
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
EOF

yum install -y kubelet-1.23.17 kubeadm-1.23.17 kubectl-1.23.17
systemctl enable kubelet

echo "192.168.1.10 cluster-endpoint" >> /etc/hosts

# 10. 安装 Wazuh All-In-One via 官方脚本（Docker 方式）
curl -sO https://packages.wazuh.com/4.5/wazuh-install.sh
bash ./wazuh-install.sh -a

echo -e "\n✅ 部署完成，Wazuh + Docker + 网络配置已成功！"

