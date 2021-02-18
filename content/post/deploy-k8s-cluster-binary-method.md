---
title: "K8S 集群部署（二进制方式）"
date: 2020-10-26T15:55:05+08:00
draft: false
tags: ["k8s", "etcd"]
categories: ["Kubernetes"]
---

## 一、环境准备

**1. 软件环境**

| 软件       | 版本信息                                                     |
| ---------- | ------------------------------------------------------------ |
| 操作系统   | CentOS 7.6.1810                                              |
| Docker     | 19.03.13                                                     |
| Kubernetes | [1.19](https://dl.k8s.io/v1.19.3/kubernetes-server-linux-amd64.tar.gz) |
| etcd       | [v3.14.13](https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz) |
| flannel    | [v0.13.0](https://github.com/coreos/flannel/releases/download/v0.13.0/flannel-v0.13.0-linux-amd64.tar.gz) |

**2. 虚拟机信息**

| 主机名 | IP             | 需安装组件                                                   |
| ------ | -------------- | ------------------------------------------------------------ |
| master | 172.16.207.128 | kube-apiserver，kube-controller-manager，kube-scheduler，etcd |
| node1  | 172.16.207.129 | kubelet，kube-proxy，docker，flannel，etcd                   |
| node2  | 172.16.207.130 | kubelet，kube-proxy，docker，flannel，etcd                   |

**3. 操作系统初始化**

```powershell
# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 关闭 selinux
setenforce 0
sed -i 's/enforcing/disabled/' /etc/selinux/config

# 关闭swap
swapoff -a
sed -ri 's/.swap./#&/' /etc/fstab

# 设置主机名
hostnamectl set-hostname master

# 修改hosts文件
cat >> /etc/hosts <<EOF
172.16.207.128 master
172.16.207.129 node1
172.16.207.130 node2
EOF

# 将桥接的IPv4流量传递到iptables的链
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# 使修改生效
sysctl --system

# 时间同步
yum -y install ntpdate
ntpdate ntp1.aliyun.com
```

以上操作在 master 上执行，node1、node2 做相同的修改操作（注意hostname）。

**4. ssh 免登录设置**

进行此操作，方便后续从 master 拷贝文件到 node，不用重复输入密码。

```powershell
# 在 master 上执行命令
# 一路回车即可
ssh-keygen
ssh-copy-id 172.16.207.129
ssh-copy-id 172.16.207.130
```

## 二、部署 ETCD 集群

**1. 下载 cfssl 工具**

```powershell
[root@master ~]# ll
总用量 4
-rw-------. 1 root root 1200 10月 16 09:00 anaconda-ks.cfg
[root@master ~]# curl -o cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  9.8M  100  9.8M    0     0   153k      0  0:01:06  0:01:06 --:--:--  220k
[root@master ~]# curl -o cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 2224k  100 2224k    0     0   129k      0  0:00:17  0:00:17 --:--:--  202k
[root@master ~]# curl -o cfssl-certinfo https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 6440k  100 6440k    0     0   212k      0  0:00:30  0:00:30 --:--:--  232k
[root@master ~]# chmod +x cfssl*
[root@master ~]# mv cfssl* /usr/local/bin/
[root@master ~]# ls -lh /usr/local/bin/ | grep cfssl
-rwxr-xr-x 1 root root 9.9M 10月 26 16:44 cfssl
-rwxr-xr-x 1 root root 6.3M 10月 26 16:46 cfssl-certinfo
-rwxr-xr-x 1 root root 2.2M 10月 26 16:45 cfssljson
```

**2. 生成证书**

可以使用脚本生成 etcd 使用的证书，修改脚本中的 IP 地址即可。

```shell
# gen_cert.sh

cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "etcd": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
    "CN":"etcd CA",
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Beijing",
            "ST":"Beijing"
        }
    ]
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
#-----------------------
cat > server-csr.json <<EOF
{
    "CN":"etcd",
    "hosts":[
        "172.16.207.128",
        "172.16.207.129",
        "172.16.207.130",
        "172.16.207.131"
    ],
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Beijing",
            "ST":"Beijing"
        }
    ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=etcd server-csr.json | cfssljson -bare server
```

执行脚本：

```powershell
[root@master ~]# mkdir -p /opt/etcd/{bin,cfg,ssl}
[root@master ~]# cd /opt/etcd/ssl/
[root@master ssl]# vim gen_cert.sh
[root@master ssl]# sh gen_cert.sh
2020/10/26 17:02:23 [INFO] generating a new CA key and certificate from CSR
2020/10/26 17:02:23 [INFO] generate received request
2020/10/26 17:02:23 [INFO] received CSR
2020/10/26 17:02:23 [INFO] generating key: rsa-2048
2020/10/26 17:02:23 [INFO] encoded CSR
2020/10/26 17:02:23 [INFO] signed certificate with serial number 675033904732590831374734318307602699131099554295
2020/10/26 17:02:23 [INFO] generate received request
2020/10/26 17:02:23 [INFO] received CSR
2020/10/26 17:02:23 [INFO] generating key: rsa-2048
2020/10/26 17:02:24 [INFO] encoded CSR
2020/10/26 17:02:24 [INFO] signed certificate with serial number 407300634356389796425320963385412894041260983445
2020/10/26 17:02:24 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
[root@master ssl]# ls *.pem
ca-key.pem  ca.pem  server-key.pem  server.pem
```

将名称以`.pem`尾缀的证书拷贝到 node1 和 node2：

```powershell
[root@master ssl]# scp *.pem node1:/opt/etcd/ssl/
[root@master ssl]# scp *.pem node2:/opt/etcd/ssl/
```

**3. 部署**

1）下载 etcd，解压并拷贝到其他 node

```powershell
[root@master ~]# wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
[root@master ~]# tar zxvf etcd-v3.4.13-linux-amd64.tar.gz 
[root@master ~]# cd etcd-v3.4.13-linux-amd64
[root@master etcd-v3.4.13-linux-amd64]# cp etcd etcdctl /usr/local/bin/
[root@master etcd-v3.4.13-linux-amd64]# scp etcd etcdctl node1:/usr/local/bin/
[root@master etcd-v3.4.13-linux-amd64]# scp etcd etcdctl node2:/usr/local/bin/
```

2）创建 etcd 数据目录

```powershell
[root@master ~]# mkdir -p /var/lib/etcd
```

node1、node2 也要创建

3）创建 etcd 配置文件

```powershell
[root@master ~]# cd /opt/etcd/cfg/
[root@master cfg]# vim etcd.conf
[root@master cfg]#
[root@master cfg]# cat etcd.conf
#[Member]
ETCD_NAME="infra1"
ETCD_DATA_DIR="/var/lib/etcd/infra1.etcd"
ETCD_LISTEN_PEER_URLS="https://172.16.207.128:2380"
ETCD_LISTEN_CLIENT_URLS="https://172.16.207.128:2379,http://127.0.0.1:2379"

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://172.16.207.128:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://172.16.207.128:2379,http://127.0.0.1:2379"
ETCD_INITIAL_CLUSTER="infra1=https://172.16.207.128:2380,infra2=https://172.16.207.129:2380,infra3=https://172.16.207.130:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_ENABLE_V2="true"

#[Security]
ETCD_CERT_FILE="/opt/etcd/ssl/server.pem"
ETCD_KEY_FILE="/opt/etcd/ssl/server-key.pem"
ETCD_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CERT_FILE="/opt/etcd/ssl/server.pem"
ETCD_PEER_KEY_FILE="/opt/etcd/ssl/server-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
```

4）etcd 启动文件（systemd管理）

```powershell
[root@master cfg]# vim /usr/lib/systemd/system/etcd.service
[root@master cfg]# cat /usr/lib/systemd/system/etcd.service
[Unit]
Description=Etcd
ServerAfter=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=/opt/etcd/cfg/etcd.conf
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /usr/local/bin/etcd"
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

5）同步配置及启动文件到 node1、node2

```powershell
[root@master cfg]# pwd
/opt/etcd/cfg
[root@master cfg]# scp etcd.conf node1:/opt/etcd/cfg/
etcd.conf
[root@master cfg]# scp etcd.conf node2:/opt/etcd/cfg/
etcd.conf
[root@master cfg]# scp /usr/lib/systemd/system/etcd.service node1:/usr/lib/systemd/system/
etcd.service                                                                                             100%  383   335.9KB/s   00:00
[root@master cfg]# scp /usr/lib/systemd/system/etcd.service node2:/usr/lib/systemd/system/
etcd.service                                                                                             100%  383   267.7KB/s   00:00
```

***注意：***同步到node后，需修改配置文件中的 IP 和 ETCD_NAME

6）启动etcd

```powershell
[root@master ~]# systemctl daemon-reload
[root@master ~]# systemctl enable etcd
[root@master ~]# systemctl start etcd
```

7）查看集群状态

```powershell
[root@master ~]# etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379" endpoint health
https://172.16.207.128:2379 is healthy: successfully committed proposal: took = 15.663882ms
https://172.16.207.130:2379 is healthy: successfully committed proposal: took = 18.706924ms
https://172.16.207.129:2379 is healthy: successfully committed proposal: took = 18.657068ms

[root@master ~]# etcdctl put /testdir/testkey "hello etcd"
OK
[root@master ~]# etcdctl get /testdir/testkey "hello etcd"
/testdir/testkey
hello etcd
[root@master ~]# etcdctl del /testdir/testkey "hello etcd"
1
```

## 三、在 Node 上部署Docker

使用 yum 安装

```powershell
# 安装必要的一些系统工具
yum install -y yum-utils device-mapper-persistent-data lvm2
# 添加软件源信息
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
# 更新并安装 Docker-CE
yum makecache fast
yum -y install docker-ce
# 启动docker
systemctl start docker
```

## 四、部署 Flannel 网络

Falnnel 要用 etcd 存储自身一个子网信息，所以要保证能成功连接 Etcd，写入预定义子网段：

```powershell
# etcd 配置文件中增加对 v2 接口的支持
[root@node1 ~]# grep "ETCD_ENABLE" /opt/etcd/cfg/etcd.conf
ETCD_ENABLE_V2="true"
[root@node1 ~]# export ETCDCTL_API=2
[root@node1 ~]# cd /opt/etcd/ssl/
[root@node1 ssl]# /opt/etcd/bin/etcdctl --ca-file=ca.pem --cert-file=server.pem --key-file=server-key.pem --endpoints="https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379" set /coreos.com/network/config '{"Network": "172.17.0.0/16", "Backend": {"Type": "vxlan"}}'
{"Network": "172.17.0.0/16", "Backend": {"Type": "vxlan"}}
[root@node1 ssl]# /opt/etcd/bin/etcdctl --ca-file=ca.pem --cert-file=server.pem --key-file=server-key.pem --endpoints="https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379" get /coreos.com/network/config
{"Network": "172.17.0.0/16", "Backend": {"Type": "vxlan"}}
```



**注意：**由于部署时使用的是 etcd 和 flannel 的最新版本，存在兼容问题，需做如下操作：

- 修改 etcd 的配置文件，增加对v2接口的支持选项 ETCD_ENABLE_V2="true"（重启etcd服务）
- 在终端执行命令前，指定使用 v2 接口

**以下部署步骤在规划的每个 node 节点操作**

1. 解压二进制包

   ```powershell
   [root@node1 ~]# tar zxvf flannel-v0.13.0-linux-amd64.tar.gz
   [root@node1 ~]# mkdir /opt/kubernetes/{bin,cfg,ssl,logs} -p
   [root@node1 ~]# mv flanneld mk-docker-opts.sh /opt/kubernetes/bin/
   ```

2. 配置 flannel

   执行脚本 flannel.sh 完成配置操作

   ```powershell
   [root@node1 ~]# mkdir flannel
   [root@node1 ~]# cd flannel
   [root@node1 flannel]# vim flannel.sh
   [root@node1 flannel]# cat flannel.sh
   #!/bin/bash
   
   ETCD_ENDPOINTS=${1:-"http://127.0.0.1:2379"}
   
   cat <<EOF >/opt/kubernetes/cfg/flanneld
   FLANNEL_OPTIONS="--etcd-endpoints=${ETCD_ENDPOINTS} \
   -etcd-cafile=/opt/etcd/ssl/ca.pem \
   -etcd-certfile=/opt/etcd/ssl/server.pem \
   -etcd-keyfile=/opt/etcd/ssl/server-key.pem"
   EOF
   
   cat <<EOF >/usr/lib/systemd/system/flanneld.service
   [Unit]
   Description=Flanneld overlay address etcd agent
   After=network-online.target network.target
   Before=docker.service
   
   [Service]
   Type=notify
   EnvironmentFile=/opt/kubernetes/cfg/flanneld
   ExecStart=/opt/kubernetes/bin/flanneld --ip-masq \$FLANNEL_OPTIONS
   ExecStartPost=/opt/kubernetes/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/subnet.env
   Restart=on-failure
   
   [Install]
   WantedBy=multi-user.target
   EOF
   
   mv /usr/lib/systemd/system/docker.service /usr/lib/systemd/system/docker.service.bak
   
   cat <<EOF >/usr/lib/systemd/system/docker.service
   [Unit]
   Description=Docker Application Container Engine
   Documentation=https://docs.docker.com
   After=network-online.target firewalld.service
   Wants=network-online.target
   
   [Service]
   Type=notify
   EnvironmentFile=/run/flannel/subnet.env
   ExecStart=/usr/bin/dockerd \$DOCKER_NETWORK_OPTIONS
   ExecReload=/bin/kill -s HUP \$MAINPID
   LimitNOFILE=infinity
   LimitNPROC=infinity
   LimitCORE=infinity
   TimeoutStartSec=0
   Delegate=yes
   KillMode=process
   Restart=on-failure
   StartLimitBurst=3
   StartLimitInterval=60s
   
   [Install]
   WantedBy=multi-user.target
   EOF
   
   systemctl daemon-reload
   systemctl enable flanneld
   systemctl restart flanneld
   systemctl restart docker
   [root@node1 flannel]#
   [root@node1 flannel]# sh -x flannel.sh https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379
   + ETCD_ENDPOINTS=https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379
   + cat
   + cat
   + mv /usr/lib/systemd/system/docker.service /usr/lib/systemd/system/docker.service.bak
   + cat
   + systemctl daemon-reload
   + systemctl enable flanneld
   Created symlink from /etc/systemd/system/multi-user.target.wants/flanneld.service to /usr/lib/systemd/system/flanneld.service.
   + systemctl restart flanneld
   + systemctl restart docker
   [root@node1 flannel]# systemctl status docker
   [root@node1 flannel]# systemctl status flannel
   ```

3. 检测是否生效

   ```powershell
   # node1
   [root@node1 flannel]# ifconfig
   docker0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 172.17.66.1  netmask 255.255.255.0  broadcast 172.17.66.255
           ether 02:42:fe:58:17:03  txqueuelen 0  (Ethernet)
           RX packets 0  bytes 0 (0.0 B)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 0  bytes 0 (0.0 B)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   
   ens33: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
           inet 172.16.207.129  netmask 255.255.255.0  broadcast 172.16.207.255
           inet6 fe80::20c:29ff:fe20:ee59  prefixlen 64  scopeid 0x20<link>
           ether 00:0c:29:20:ee:59  txqueuelen 1000  (Ethernet)
           RX packets 636501  bytes 196057213 (186.9 MiB)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 593239  bytes 77977323 (74.3 MiB)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   
   flannel.1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
           inet 172.17.66.0  netmask 255.255.255.255  broadcast 172.17.66.0
           inet6 fe80::380d:d6ff:fe3a:2fc8  prefixlen 64  scopeid 0x20<link>
           ether 3a:0d:d6:3a:2f:c8  txqueuelen 0  (Ethernet)
           RX packets 4  bytes 336 (336.0 B)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 4  bytes 336 (336.0 B)
           TX errors 0  dropped 5 overruns 0  carrier 0  collisions 0
   
   lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
           inet 127.0.0.1  netmask 255.0.0.0
           inet6 ::1  prefixlen 128  scopeid 0x10<host>
           loop  txqueuelen 1000  (Local Loopback)
           RX packets 4281  bytes 252413 (246.4 KiB)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 4281  bytes 252413 (246.4 KiB)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   # node2
   [root@node2 flannel]# ifconfig
   docker0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
           inet 172.17.31.1  netmask 255.255.255.0  broadcast 172.17.31.255
           ether 02:42:96:b0:5d:87  txqueuelen 0  (Ethernet)
           RX packets 0  bytes 0 (0.0 B)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 0  bytes 0 (0.0 B)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   
   ens33: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
           inet 172.16.207.130  netmask 255.255.255.0  broadcast 172.16.207.255
           inet6 fe80::20c:29ff:fe22:ab4f  prefixlen 64  scopeid 0x20<link>
           ether 00:0c:29:22:ab:4f  txqueuelen 1000  (Ethernet)
           RX packets 425448  bytes 172365242 (164.3 MiB)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 376747  bytes 53642545 (51.1 MiB)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   
   flannel.1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1450
           inet 172.17.31.0  netmask 255.255.255.255  broadcast 172.17.31.0
           inet6 fe80::f484:69ff:fe3a:a49e  prefixlen 64  scopeid 0x20<link>
           ether f6:84:69:3a:a4:9e  txqueuelen 0  (Ethernet)
           RX packets 0  bytes 0 (0.0 B)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 0  bytes 0 (0.0 B)
           TX errors 0  dropped 5 overruns 0  carrier 0  collisions 0
   
   lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
           inet 127.0.0.1  netmask 255.0.0.0
           inet6 ::1  prefixlen 128  scopeid 0x10<host>
           loop  txqueuelen 1000  (Local Loopback)
           RX packets 3900  bytes 212224 (207.2 KiB)
           RX errors 0  dropped 0  overruns 0  frame 0
           TX packets 3900  bytes 212224 (207.2 KiB)
           TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
   ```
   
   确保 docker0 和 flannel.1 在同一个网段。测试不同节点互通：
   
   ```powershell
   [root@node2 flannel]# ping 172.17.66.1 -c 2
   PING 172.17.66.1 (172.17.66.1) 56(84) bytes of data.
   64 bytes from 172.17.66.1: icmp_seq=1 ttl=64 time=0.689 ms
   64 bytes from 172.17.66.1: icmp_seq=2 ttl=64 time=0.750 ms
   
   --- 172.17.66.1 ping statistics ---
   2 packets transmitted, 2 received, 0% packet loss, time 1000ms
   rtt min/avg/max/mdev = 0.689/0.719/0.750/0.040 ms
   ```
   
   如果能通说明Flannel部署成功。如果不通检查下日志：journalctl -u flannel -f

## 五、在 master 节点部署组件

**1. 生成证书**

使用脚本完成证书的创建。

```powershell
[root@master ~]# mkdir /opt/kubernetes/{bin,cfg,ssl,logs} -p
[root@master ~]# cd /opt/kubernetes/ssl/
[root@master ssl]# vim gen_cert.sh
[root@master ssl]# cat gen_cert.sh
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
#-----------------------
cat > server-csr.json <<EOF
{
    "CN": "kubernetes",
    "hosts": [
      "10.0.0.1",
      "127.0.0.1",
      "172.16.207.128",
      "172.16.207.129",
      "172.16.207.130",
      "172.16.207.131",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "BeiJing",
            "ST": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server
#-----------------------
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
#-----------------------
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
[root@master ssl]# sh gen_cert.sh
[root@master ssl]# ls *.pem
admin-key.pem  admin.pem  ca-key.pem  ca.pem  kube-proxy-key.pem  kube-proxy.pem  server-key.pem  server.pem
```

**2. 部署 apiserver 组件**

1）解压压缩包，复制用到的可执行文件到 `/opt/kubenetes/bin/`目录

```powershell
[root@master ~]# tar zxvf kubernetes-server-linux-amd64.tar.gz
[root@master ~]# cd kubernetes/server/bin
[root@master bin]# cp kube-apiserver kube-controller-manager kube-scheduler kubectl /opt/kubernetes/bin/
```

2）创建 token 文件，后面会用到

```powershell
[root@master bin]# head -c 16 /dev/urandom | od -An -t x | tr -d ' '
dbefc3df7404a01ba94eabbac49b3654
[root@master bin]# vim /opt/kubernetes/cfg/token.csv
[root@master bin]# cat /opt/kubernetes/cfg/token.csv
dbefc3df7404a01ba94eabbac49b3654,kubelet-bootstrap,10001,"system:node-bootstrapper"
```

第一列：随机字符串，自己可生成 第二列：用户名 第三列：UID 第四列：用户组

3）创建 apiserver 配置文件

使用脚本完成 apiserver 相关配置文件的创建和服务的启动。

```powershell
[root@master bin]# mkdir /root/k8s/master -p
[root@master bin]# cd /root/k8s/master/
[root@master master]# vim apiserver.sh
[root@master master]# cat apiserver.sh
#!/bin/bash

MASTER_ADDRESS=$1
ETCD_SERVERS=$2

cat <<EOF >/opt/kubernetes/cfg/kube-apiserver

KUBE_APISERVER_OPTS="--logtostderr=true \\
--v=4 \\
--log-dir=/opt/kubernetes/logs \\
--etcd-servers=${ETCD_SERVERS} \\
--bind-address=${MASTER_ADDRESS} \\
--secure-port=6443 \\
--advertise-address=${MASTER_ADDRESS} \\
--allow-privileged=true \\
--service-cluster-ip-range=10.0.0.0/24 \\
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \\
--authorization-mode=RBAC,Node \\
--kubelet-https=true \\
--enable-bootstrap-token-auth \\
--token-auth-file=/opt/kubernetes/cfg/token.csv \\
--service-node-port-range=30000-50000 \\
--tls-cert-file=/opt/kubernetes/ssl/server.pem  \\
--tls-private-key-file=/opt/kubernetes/ssl/server-key.pem \\
--client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--etcd-cafile=/opt/etcd/ssl/ca.pem \\
--etcd-certfile=/opt/etcd/ssl/server.pem \\
--etcd-keyfile=/opt/etcd/ssl/server-key.pem \\
--audit-log-maxage=30 \\
--audit-log-maxbackup=3 \\
--audit-log-maxsize=100 \\
--audit-log-path=/opt/kubernetes/logs/k8s-audit.log"
EOF

cat <<EOF >/usr/lib/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-apiserver
ExecStart=/opt/kubernetes/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl restart kube-apiserver
[root@master master]# sh -x apiserver.sh 172.16.207.128 https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379
+ MASTER_ADDRESS=172.16.207.128
+ ETCD_SERVERS=https://172.16.207.128:2379,https://172.16.207.129:2379,https://172.16.207.130:2379
+ cat
+ cat
+ systemctl daemon-reload
+ systemctl enable kube-apiserver
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-apiserver.service to /usr/lib/systemd/system/kube-apiserver.service.
+ systemctl restart kube-apiserver
[root@master master]# systemctl status kube-apiserver
[root@master master]# netstat -lntp | grep kube
tcp        0      0 172.16.207.128:6443     0.0.0.0:*               LISTEN      16536/kube-apiserve
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      16536/kube-apiserve
```

**3. 部署 scheduler 组件**

```powershell
[root@master master]# vim scheduler.sh
[root@master master]# cat scheduler.sh
#!/bin/bash

MASTER_ADDRESS=$1

cat <<EOF >/opt/kubernetes/cfg/kube-scheduler
KUBE_SCHEDULER_OPTS="--logtostderr=true \\
--v=4 \\
--log-dir=/opt/kubernetes/logs \\
--master=${MASTER_ADDRESS}:8080 \\
--leader-elect"
EOF

cat <<EOF >/usr/lib/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-scheduler
ExecStart=/opt/kubernetes/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
[root@master master]# sh -x scheduler.sh 127.0.0.1
+ MASTER_ADDRESS=127.0.0.1
+ cat
+ cat

# 启动 scheduler
[root@master master]# systemctl daemon-reload
[root@master master]# systemctl enable kube-scheduler
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-scheduler.service to /usr/lib/systemd/system/kube-scheduler.service.
[root@master master]# systemctl start kube-scheduler
[root@master master]# netstat -lnpt |grep kube
tcp        0      0 172.16.207.128:6443     0.0.0.0:*               LISTEN      16536/kube-apiserve
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      16536/kube-apiserve
tcp6       0      0 :::10251                :::*                    LISTEN      16597/kube-schedule
tcp6       0      0 :::10259                :::*                    LISTEN      16597/kube-schedule
```

**4. 部署 controller-manager 组件**

```powershell
[root@master master]# vim controller-manager.sh
[root@master master]# cat controller-manager.sh
cat <<EOF >/opt/kubernetes/cfg/kube-controller-manager
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=true \\
--v=4 \\
--log-dir=/opt/kubernetes/logs \\
--master=127.0.0.1:8080 \\
--leader-elect=true \\
--address=127.0.0.1 \\
--service-cluster-ip-range=10.0.0.0/24 \\
--cluster-name=kubernetes \\
--cluster-signing-cert-file=/opt/kubernetes/ssl/ca.pem \\
--cluster-signing-key-file=/opt/kubernetes/ssl/ca-key.pem  \\
--root-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-private-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--experimental-cluster-signing-duration=87600h0m0s"
EOF

cat <<EOF >/usr/lib/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-controller-manager
ExecStart=/opt/kubernetes/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
[root@master master]# sh -x controller-manager.sh
+ cat
+ cat
[root@master master]# systemctl daemon-reload
[root@master master]# systemctl enable kube-controller-manager
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service to /usr/lib/systemd/system/kube-controller-manager.service.
[root@master master]# systemctl start kube-controller-manager
[root@master master]# netstat -lntp | grep kube
tcp        0      0 172.16.207.128:6443     0.0.0.0:*               LISTEN      16536/kube-apiserve
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      16656/kube-controll
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      16536/kube-apiserve
tcp6       0      0 :::10251                :::*                    LISTEN      16597/kube-schedule
tcp6       0      0 :::10257                :::*                    LISTEN      16656/kube-controll
tcp6       0      0 :::10259                :::*                    LISTEN      16597/kube-schedule
```

master 所有组件都已经部署成功，通过 kubectl 工具查看当前集群组件状态：

```powershell
[root@master master]# cp /opt/kubernetes/bin/ckubectl /usr/local/bin/
[root@master master]# kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE             ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-2               Healthy   {"health":"true"}
etcd-0               Healthy   {"health":"true"}
etcd-1               Healthy   {"health":"true"}
```

## 六、在 Node 节点部署组件

Master apiserver 启用 TLS 认证后，Node 节点 kubelet 组件想要加入集群，必须使用 CA 签发的有效证书才能与 apiserver 通信，当 Node 节点很多时，签署证书是一件很繁琐的事情，因此有了 TLS Bootstrapping 机制，kubelet  会以一个低权限用户自动向 apiserver 申请证书，kubelet 的证书由 apiserver 动态签署。

**1. 将 kubelet-bootstrap 用户绑定到系统集群角色**

```powershell
[root@master ~]# kubectl create clusterrolebinding kubelet-bootstrap  --clusterrole=system:node-bootstrapper  --user=kubelet-bootstrap
clusterrolebinding.rbac.authorization.k8s.io/kubelet-bootstrap created
[root@master ~]# echo $?
0
[root@master ~]#
```

**2. 创建 kubeconfig 文件**

在生成 kubernetes 证书的目录下执行以下命令生成 kubeconfig 文件：

```powershell
[root@master ~]# mkdir /root/k8s/node -p
[root@master ~]# cd /root/k8s/node/
[root@master node]# cat /opt/kubernetes/cfg/token.csv
dbefc3df7404a01ba94eabbac49b3654,kubelet-bootstrap,10001,"system:node-bootstrapper"
[root@master node]# cat /opt/kubernetes/cfg/token.csv | awk -F ',' '{print $1}'
dbefc3df7404a01ba94eabbac49b3654
[root@master node]# vim kubeconfig.sh
[root@master node]# cat kubeconfig.sh
# 创建 TLS Bootstrapping Token
BOOTSTRAP_TOKEN=$(cat /opt/kubernetes/cfg/token.csv | awk -F ',' '{print $1}')

#----------------------

APISERVER=$1
SSL_DIR=$2

# 创建kubelet bootstrapping kubeconfig
export KUBE_APISERVER="https://$APISERVER:6443"

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=$SSL_DIR/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig

# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig

# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

#----------------------

# 创建kube-proxy kubeconfig文件

kubectl config set-cluster kubernetes \
  --certificate-authority=$SSL_DIR/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy \
  --client-certificate=$SSL_DIR/kube-proxy.pem \
  --client-key=$SSL_DIR/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
[root@master node]# sh -x kubeconfig.sh 172.16.207.128 /opt/kubernetes/ssl
[root@master node]# ls *config
bootstrap.kubeconfig  kube-proxy.kubeconfig

# 将生成的 2 个 kubeconfig 文件拷贝到 node 节点
[root@master node]# scp *config node1:/opt/kubernetes/cfg/
bootstrap.kubeconfig                                                                                                                          100% 2168     1.7MB/s   00:00
kube-proxy.kubeconfig                                                                                                                         100% 6274     5.8MB/s   00:00
[root@master node]# scp *config node2:/opt/kubernetes/cfg/
bootstrap.kubeconfig                                                                                                                          100% 2168     2.4MB/s   00:00
kube-proxy.kubeconfig                                                                                                                         100% 6274     6.6MB/s   00:00
[root@master node]#
```

**3. 部署 kubelet 组件**

将前面解压出来的 kubelet 和 kube-proxy 拷贝到 node 节点 /opt/kubernetes/bin 目录下：

```powershell
[root@master bin]# scp kubelet kube-proxy node1:/opt/kubernetes/bin/
kubelet                                                                                                                                       100%  105MB  51.9MB/s   00:02
kube-proxy                                                                                                                                    100%   37MB  49.8MB/s   00:00
[root@master bin]# scp kubelet kube-proxy node2:/opt/kubernetes/bin/
kubelet                                                                                                                                       100%  105MB  56.0MB/s   00:01
kube-proxy                                                                                                                                    100%   37MB  54.6MB/s   00:00
[root@master bin]#
```

创建 kubelet 配置文件：

```powershell
[root@node1 ~]# mkdir -p /root/k8s/node
[root@node1 ~]# cd /root/k8s/node/
[root@node1 node]# vim kubelet.sh
[root@node1 node]# cat kubelet.sh
#!/bin/bash

NODE_ADDRESS=$1
DNS_SERVER_IP=${2:-"10.0.0.2"}

cat <<EOF >/opt/kubernetes/cfg/kubelet

KUBELET_OPTS="--logtostderr=true \\
--v=4 \\
--log-dir=/opt/kubernetes/logs \\
--hostname-override=${NODE_ADDRESS} \\
--kubeconfig=/opt/kubernetes/cfg/kubelet.kubeconfig \\
--bootstrap-kubeconfig=/opt/kubernetes/cfg/bootstrap.kubeconfig \\
--config=/opt/kubernetes/cfg/kubelet.config \\
--cert-dir=/opt/kubernetes/ssl \\
--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google-containers/pause-amd64:3.0"

EOF

cat <<EOF >/opt/kubernetes/cfg/kubelet.config

kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: ${NODE_ADDRESS}
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS:
- ${DNS_SERVER_IP}
clusterDomain: cluster.local.
failSwapOn: false
authentication:
  anonymous:
    enabled: true
EOF

cat <<EOF >/usr/lib/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
After=docker.service
Requires=docker.service

[Service]
EnvironmentFile=/opt/kubernetes/cfg/kubelet
ExecStart=/opt/kubernetes/bin/kubelet \$KUBELET_OPTS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
[root@node1 node]# sh -x kubelet.sh 172.16.207.129
+ NODE_ADDRESS=172.16.207.129
+ DNS_SERVER_IP=10.0.0.2
+ cat
+ cat
+ cat
[root@node1 node]# ll /opt/kubernetes/cfg/
总用量 24
-rw------- 1 root root 2168 10月 27 14:24 bootstrap.kubeconfig
-rw-r--r-- 1 root root  236 10月 27 11:52 flanneld
-rw-r--r-- 1 root root  378 10月 27 14:37 kubelet
-rw-r--r-- 1 root root  267 10月 27 14:37 kubelet.config
-rw------- 1 root root 6274 10月 27 14:24 kube-proxy.kubeconfig

# 启动
[root@node1 node]# systemctl daemon-reload
[root@node1 node]# systemctl enable kubelet
Created symlink from /etc/systemd/system/multi-user.target.wants/kubelet.service to /usr/lib/systemd/system/kubelet.service.
[root@node1 node]# systemctl restart kubelet
[root@node1 node]# ps -ef | grep kubelet

# 复制脚本文件到另一个 node 节点
[root@node1 node]# scp -r /root/k8s node2:~
```

在 node2 节点执行：

```powershell
[root@node2 ~]# cd k8s/node/
[root@node2 node]# sh -x kubelet.sh 172.16.207.130
# 启动
[root@node2 node]# systemctl daemon-reload
[root@node2 node]# systemctl enable kubelet
Created symlink from /etc/systemd/system/multi-user.target.wants/kubelet.service to /usr/lib/systemd/system/kubelet.service.
[root@node2 node]# systemctl start kubelet
```

在 Master 审批 Node 加入集群：

```powershell
[root@master bin]# kubectl get csr
NAME                                                   AGE     SIGNERNAME                                    REQUESTOR           CONDITION
node-csr-3ZdP9nsg0zrO5CAjYSn12J0s4FYeFVJFVQtxSM-keUM   8m29s   kubernetes.io/kube-apiserver-client-kubelet   kubelet-bootstrap   Pending
node-csr-5AkYXWfhxcBluIgDbHNy3xov6KQGlzZ-mjmGJyN5iG0   2m28s   kubernetes.io/kube-apiserver-client-kubelet   kubelet-bootstrap   Pending
[root@master bin]# kubectl certificate approve node-csr-3ZdP9nsg0zrO5CAjYSn12J0s4FYeFVJFVQtxSM-keUM
certificatesigningrequest.certificates.k8s.io/node-csr-3ZdP9nsg0zrO5CAjYSn12J0s4FYeFVJFVQtxSM-keUM approved
[root@master bin]# kubectl certificate approve node-csr-5AkYXWfhxcBluIgDbHNy3xov6KQGlzZ-mjmGJyN5iG0
certificatesigningrequest.certificates.k8s.io/node-csr-5AkYXWfhxcBluIgDbHNy3xov6KQGlzZ-mjmGJyN5iG0 approved

# 等待一会儿，查看node
[root@master ~]# kubectl get nodes
NAME     STATUS   ROLES    AGE   VERSION
node1    Ready    <none>   53m   v1.19.3
node2    Ready    <none>   71m   v1.19.3
```

**4. 部署 kube-proxy 组件**

创建 kube-proxy 配置文件：

```powershell
[root@node1 node]# vim proxy.sh
[root@node1 node]# cat proxy.sh
#!/bin/bash

NODE_ADDRESS=$1

cat <<EOF >/opt/kubernetes/cfg/kube-proxy

KUBE_PROXY_OPTS="--logtostderr=true \\
--v=4 \\
--hostname-override=${NODE_ADDRESS} \\
--cluster-cidr=10.0.0.0/24 \\
--proxy-mode=ipvs \\
--kubeconfig=/opt/kubernetes/cfg/kube-proxy.kubeconfig"

EOF

cat <<EOF >/usr/lib/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=-/opt/kubernetes/cfg/kube-proxy
ExecStart=/opt/kubernetes/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
[root@node1 node]# sh proxy.sh 172.16.207.129
[root@node1 node]# systemctl daemon-reload
[root@node1 node]# systemctl enable kube-proxy
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-proxy.service to /usr/lib/systemd/system/kube-proxy.service.
[root@node1 node]# systemctl start kube-proxy
[root@node1 node]# ps -ef | grep kube-proxy
```

node2 部署方式一样。

## 七、运行一个测试示例

创建一个Nginx Web，测试集群是否正常工作

```powershell
[root@master ~]# kubectl create deployment nginx --image=nginx
deployment.apps/nginx created
[root@master ~]# kubectl get pods
NAME                     READY   STATUS              RESTARTS   AGE
nginx-6799fc88d8-9xd2l   0/1     ContainerCreating   0          8s
[root@master ~]# kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
nginx-6799fc88d8-9xd2l   1/1     Running   0          108s
[root@master ~]# kubectl get deployments
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   1/1     1            1           119s
[root@master ~]# kubectl expose deployment nginx --port=80 --type=NodePort
service/nginx exposed
[root@master ~]# kubectl get pod,svc
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-6799fc88d8-9xd2l   1/1     Running   0          4m1s

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
service/kubernetes   ClusterIP   10.0.0.1     <none>        443/TCP        18h
service/nginx        NodePort    10.0.0.203   <none>        80:36567/TCP   7s
```

浏览器中访问 ip:36567 打开页面，如果看到的是我们熟悉的 Nginx 页面，说明集群正常工作了。（ip 可以是任一 node 的 ip）。

-----

以上就是二进制方式部署 K8S 集群的详细过程，部署过程中遇到的2个问题：

1. flannel 启动失败

   最新版本etcd和flannel兼容问题导致

2. kubelet 自动申请证书，手动 approve 后，证书一直处于Approved 状态，没有 Issued

   证书签发是由 kube-controller-manager 完成，检查发现是 kube-controller-manager 配置文件参数 `--master`参数值不正确，应该为`--master=127.0.0.1:8080`，不能写操作系统通信网卡的 ip。

参考博客：[链接](https://www.cnblogs.com/supery007/p/12799830.html)