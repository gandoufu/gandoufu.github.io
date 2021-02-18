---
title: "K8S 集群部署（kubeadm）"
date: 2020-11-02T14:24:12+08:00
draft: false
tags: ["k8s", "kubeadm"]
categories: ["Kubernetes"]
---

### 一、虚拟机信息

| 主机名 | IP             | 操作系统        |
| ------ | -------------- | --------------- |
| master | 172.16.207.128 | CentOS 7.6.1810 |
| node1  | 172.16.207.129 | CentOS 7.6.1810 |
| node2  | 172.16.207.130 | CentOS 7.6.1810 |



### 二、 系统配置

```powershell
# 1) 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld
# 2) 关闭 selinux
setenforce 0
sed -i 's/enforcing/disabled/' /etc/selinux/config
# 3) 关闭 swap
swapoff -a
sed -ri 's/.swap./#&/' /etc/fstab
# 4) 设置主机名
hostnamectl set-hostname <hostname>
# 5) 修改 hosts 文件
cat >> /etc/hosts <<EOF
172.16.207.128 master
172.16.207.129 node1
172.16.207.130 node2
EOF
# 6) 将桥接的IPv4流量传递到iptables的链
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system  # 生效
# 7) 时间同步
yum -y install ntpdate
ntpdate ntp1.aliyun.com
```



### 三、安装 docker/kubeadm/kubelet

**1. 安装 Docker**

```powershell
# - 安装必要的一些系统工具
yum install -y yum-utils device-mapper-persistent-data lvm2
# - 添加软件源信息
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
# - 更新并安装 Docker-CE
yum makecache fast
yum -y install docker-ce
# - 设置开机自启动并启动docker
systemctl enable docker && systemctl start docker
```

**2. 安装kubeadm/kubelet**

在所有机器上执行：

```powershell
# - 添加阿里云yum软件源（Kubernetes）
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
# - 安装kubelet/kubeadm/kubectl
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet
```



### 四、部署 Kubernetes Master

在 master 节点执行：

```powershell
kubeadm init \
--apiserver-advertise-address=172.16.207.128 \
--image-repository registry.aliyuncs.com/google_containers \
--service-cidr=10.96.0.0/12 \
--pod-network-cidr=10.244.0.0/16
```

执行完成后，会有以下输出内容：

```powershell
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 172.16.207.128:6443 --token eunb1i.50ucn2fzzg190iag \
    --discovery-token-ca-cert-hash sha256:3c6557ea889195eb1a807dd868501cde732355a5ac1ca9b625611e0f295c0d9f
```

按照输出信息操作，使用 kubectl 工具获取 node 节点信息：

```powershell
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```



### 五、将 Node 加入到 K8S 集群中

在 Node 机器上执行命令：

```powershell
kubeadm join 172.16.207.128:6443 --token eunb1i.50ucn2fzzg190iag \
    --discovery-token-ca-cert-hash sha256:3c6557ea889195eb1a807dd868501cde732355a5ac1ca9b625611e0f295c0d9f
```

注：注：加入后，在 master 上执行 kubectl get nodes，node 状态还是NotReady状态，需要部署CNI网络插件。



### 六、测试 Kubernetes 集群

在 Master 执行：

```powershell
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
# 查看到 node 节点中的端口
kubectl get pod,svc
```

使用 node 的 `ip:port` 访问 web 页面，可以看到 Nginx 页面，部署 OK。

