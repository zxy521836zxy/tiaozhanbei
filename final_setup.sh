# 创建 SSH 密钥
ssh-keygen











# 安装 sshpass
sudo yum install -y sshpass

# 将 SSH 密钥拷贝到各节点
sshpass -p 'admin' ssh-copy-id -o StrictHostKeyChecking=no root@master
sshpass -p 'admin' ssh-copy-id -o StrictHostKeyChecking=no root@wazuh
sshpass -p 'admin' ssh-copy-id -o StrictHostKeyChecking=no root@elk
sshpass -p 'admin' ssh-copy-id -o StrictHostKeyChecking=no root@caldera

# ===== Wazuh 节点配置 =====
ssh wazuh

sudo yum install -y sshpass

mkdir -p $HOME/.kube
scp root@master:/etc/kubernetes/admin.conf /root/.kube/config
chmod 600 $HOME/.kube/config

kubectl apply -f calico.yaml

sshpass -p 'admin' scp -o StrictHostKeyChecking=no root@master:/root/key.txt /root/key.txt
chmod 777 key.txt
./key.txt

exit

# ===== ELK 节点配置 =====
ssh elk

sudo yum install -y sshpass

mkdir -p $HOME/.kube
scp root@master:/etc/kubernetes/admin.conf /root/.kube/config
chmod 600 $HOME/.kube/config

kubectl apply -f calico.yaml

sshpass -p 'admin' scp -o StrictHostKeyChecking=no root@master:/root/key.txt /root/key.txt
chmod 777 key.txt
./key.txt

exit

# ===== Caldera 节点配置 =====
ssh caldera

sudo yum install -y sshpass

mkdir -p $HOME/.kube
scp root@master:/etc/kubernetes/admin.conf /root/.kube/config
chmod 600 $HOME/.kube/config

kubectl apply -f calico.yaml

sshpass -p 'admin' scp -o StrictHostKeyChecking=no root@master:/root/key.txt /root/key.txt
chmod 777 key.txt
./key.txt

exit

# ===== 下载并执行 k8m 工具 =====
yum install -y wget

wget https://github.com/weibaohui/k8m/releases/download/v0.0.145/k8m-linux-amd64.zip

 unzip k8m-linux-amd64.zip
 
chmod 777 ./*

./k8m-linux-amd64
