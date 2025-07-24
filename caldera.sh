#!/bin/bash

set -e

# ========= 1. 网络 & 主机配置 =========
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-ens33
TYPE=Ethernet
BOOTPROTO=static
IPADDR=192.168.1.30
NETMASK=255.255.255.0
GATEWAY=192.168.1.2
DNS1=8.8.8.8
DNS2=8.8.4.4
ONBOOT=yes
EOF

cat <<EOF >> /etc/hosts

192.168.1.10 master
192.168.1.20 elk
192.168.1.30 caldera
192.168.1.40 wazuh
EOF

hostnamectl set-hostname caldera

# ========= 2. YUM 镜像源 & 防火墙 =========
cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
curl -L -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

systemctl disable --now firewalld

# ========= 3. Swap & 内核参数 =========
swapoff -a
sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/profile

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# ========= 4. 时间同步 =========
yum install -y ntp ntpdate
ntpdate cn.pool.ntp.org
systemctl enable --now ntpd

# ========= 5. Docker =========
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

systemctl daemon-reexec
systemctl restart docker

# ========= 6. Kubernetes 依赖（可选） =========
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

# ========= 7. 安装 Pyenv & Python 3.9.9 =========
yum install -y gcc gcc-c++ make zlib-devel bzip2-devel readline-devel sqlite-devel \
    openssl-devel xz-devel libffi-devel tk-devel patch git curl wget

curl https://pyenv.run | bash

echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(pyenv init --path)"' >> ~/.bash_profile
echo 'eval "$(pyenv init -)"' >> ~/.bash_profile
echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bash_profile
source ~/.bash_profile

# 设置环境变量用于构建
export LDFLAGS="-L/usr/lib64"
export CPPFLAGS="-I/usr/include"
export PKG_CONFIG_PATH="/usr/lib64/pkgconfig"

# 安装 Python（确保网络通畅）
pyenv install 3.9.9
pyenv global 3.9.9
python --version

# ========= 8. 安装 Caldera =========
cd ~
git clone https://github.com/mitre/caldera.git --recursive
cd caldera
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/

# ========= 9. Node.js（Caldera 插件编译需要） =========
curl -sL https://rpm.nodesource.com/setup_14.x | bash -
yum install -y nodejs

# ========= 10. 构建 & 启动 =========
python3 server.py --insecure --build
echo -e "\n🎯 Caldera 构建完成！现在你可以启动它："
echo "cd ~/caldera && source venv/bin/activate && python3 server.py --insecure"

