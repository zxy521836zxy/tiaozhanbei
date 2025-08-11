#!/bin/bash

# 设置静态 IP 和主机名
cat > /etc/sysconfig/network-scripts/ifcfg-ens33 <<EOF
TYPE=Ethernet
BOOTPROTO=static
IPADDR=192.168.1.20
NETMASK=255.255.255.0
GATEWAY=192.168.1.2
DNS1=8.8.8.8
DNS2=8.8.4.4
ONBOOT=yes
EOF

cat >> /etc/hosts <<EOF
192.168.1.10 master
192.168.1.20 elk
192.168.1.30 caldera
192.168.1.40 wazuh
192.168.1.20 cluster-endpoint
EOF

hostnamectl set-hostname elk

swapoff -a
sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

systemctl disable firewalld
systemctl stop firewalld

modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/profile

tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl -p /etc/sysctl.d/k8s.conf

# 时间同步
yum install -y ntp ntpdate
ntpdate cn.pool.ntp.org
systemctl start ntpd
systemctl enable ntpd

# 设置 yum 源
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
EOF

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

systemctl start docker
systemctl enable docker

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

systemctl daemon-reload
systemctl restart docker

yum install -y kubelet-1.23.17 kubeadm-1.23.17 kubectl-1.23.17
systemctl enable kubelet

# 创建自定义网络
docker network create --subnet=172.10.0.0/16 elk

# 拉取镜像
docker pull elasticsearch:7.12.1
docker pull mobz/elasticsearch-head:5
docker pull kibana:7.12.1
docker pull logstash:7.12.1

mkdir -p elasticsearch/data elasticsearch/config
chmod -R 777 elasticsearch

# 启动 Elasticsearch
cat > elasticsearch/config/elasticsearch.yml <<EOF
network.host: 0.0.0.0
discovery.type: single-node
EOF

docker run -d --name es \
  --net elk \
  -p 9200:9200 -p 9300:9300 \
  --privileged=true \
  -v $PWD/elasticsearch/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml \
  -v $PWD/elasticsearch/data:/usr/share/elasticsearch/data \
  elasticsearch:7.12.1

# 启动 Elasticsearch-Head
docker run -d --name es_admin --net elk -p 9100:9100 mobz/elasticsearch-head:5

# 修改 Head 配置
docker cp es_admin:/usr/src/app/Gruntfile.js ./
sed -i "/^[[:space:]]*options:/a\        hostname: '0.0.0.0'," Gruntfile.js
docker cp Gruntfile.js es_admin:/usr/src/app/
docker restart es_admin

# 替换 vendor.js 中的 JSON 头类型
# (确保文件位于当前目录下)
sed -i '6886s|"application/json;charset=UTF-8"|"application/json"|;7573s|"application/json;charset=UTF-8"|"application/json"|' vendor.js

# 启动 Kibana
mkdir -p kibana
docker run -d --name kibana --net elk -p 5601:5601 \
  -e "ELASTICSEARCH_HOSTS=http://es:9200" \
  -e "I18N_LOCALE=zh-CN" \
  -v $PWD/kibana:/usr/share/kibana/config \
  kibana:7.12.1

# 启动 Logstash
docker run -d --name logstash --net elk logstash:7.12.1
docker cp logstash:/usr/share/logstash ./
docker rm -f logstash

# 修改 Logstash 配置
sed -i 's|^http.host:.*|http.host: "0.0.0.0"|' logstash/config/logstash.yml
sed -i 's|^xpack.monitoring.elasticsearch.hosts:.*|xpack.monitoring.elasticsearch.hosts: [ "http://192.168.1.20:9200" ]|' logstash/config/logstash.yml

# 启动 Logstash 正式容器
docker run -d --name logstash \
  --net elk -p 5044:5044 -p 9600:9600 \
  -v $PWD/logstash/config:/usr/share/logstash/config \
  -v $PWD/logstash/pipeline:/usr/share/logstash/pipeline \
  logstash:7.12.1

# 验证
curl http://localhost:9200

