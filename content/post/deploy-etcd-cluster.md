---
title: "CentOS7 搭建 Etcd 集群"
date: 2020-10-21T16:47:21+08:00
draft: false
tags: ["etcd", "k8s"]
categories: ["Kubernetes"]
---

### 搭建步骤

本次实验搭建包含3个节点的etcd集群，主机规划：

| 节点IP          | 主机名称  |
| --------------- | --------- |
| 192.168.209.130 | master-01 |
| 192.168.209.131 | master-02 |
| 192.168.209.132 | master-03 |



1. cfssl工具为etcd自签证书
2. 部署etcd集群（v3.4.13）
3. 启动etcd，校验状态

### 一、使用 cfssl 自签证书

**1. 下载 cfssl工具**

```powershell
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
mv cfssl_linux-amd64 /usr/local/bin/cfssl
mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
mv cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo
```

**2. 创建证书目录**

```powershell
mkdir -p /etc/etcd/ssl
cd /etc/etcd/ssl
```

**3. 生成证书**

1）etcd ca 配置

```powershell
[root@master-01 ssl]# cat << EOF | tee ca-config.json
{
    "signing":{
        "default":{
            "expiry":"87600h"
        },
        "profiles":{
            "etcd":{
                "expiry":"87600h",
                "usages":[
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
```

2）创建ca证书签名请求文件

```powershell
[root@master-01 ssl]# cat << EOF | tee ca-csr.json
{
    "CN":"etcd CA",
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hangzhou",
            "ST":"Hangzhou"
        }
    ]
}
EOF
```

3）创建etcd证书签名请求文件

```powershell
[root@master-01 ssl]# cat << EOF | tee server-csr.json
{
    "CN":"etcd",
    "hosts":[
        "192.168.209.130",
        "192.168.209.131",
        "192.168.209.132"
    ],
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hangzhou",
            "ST":"Hangzhou"
        }
    ]
}
EOF
```

4）初始化ca，生成ca证书和私钥，生成etcd证书

```powershell
[root@master-01 ssl]# ls
ca-config.json ca-csr.json server-csr.json
[root@master-01 ssl]# cfssl gencert -initca ca-csr.json | cfssljson -bare ca
2019/03/09 14:49:51 [INFO] generating a new CA key and certificate from CSR
2019/03/09 14:49:51 [INFO] generate received request
2019/03/09 14:49:51 [INFO] received CSR
2019/03/09 14:49:51 [INFO] generating key: rsa-2048
2019/03/09 14:49:51 [INFO] encoded CSR
2019/03/09 14:49:51 [INFO] signed certificate with serial number 131013203369168241950883398321469825148900357407
# 目录下会多出3个文件，ca.csr ca.pem ca-key.pem
[root@master-01 ssl]# ls 
ca-config.json ca.csr ca-csr.json ca-key.pem ca.pem server-csr.json

# 基于上步生成的 ca.pem ca-key.pem 创建etcd证书
[root@master-01 ssl]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=etcd server-csr.json | cfssljson -bare server
2019/03/09 14:53:18 [INFO] generate received request
2019/03/09 14:53:18 [INFO] received CSR
2019/03/09 14:53:18 [INFO] generating key: rsa-2048
2019/03/09 14:53:18 [INFO] encoded CSR
2019/03/09 14:53:18 [INFO] signed certificate with serial number 134668900301397848761520313578175582226195446437
2019/03/09 14:53:18 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable forwebsites. For more information see the Baseline Requirements for the Issuance and Managementof Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);specifically, section 10.2.3 ("Information Requirements").
[root@master-01 ssl]# ls *.pem
ca-key.pem ca.pem server-key.pem server.pem
```

5）拷贝证书至其他节点

```powershell
[root@master-01 ssl]# scp *.pem root@192.168.209.131:/etc/etcd/ssl/
[root@master-01 ssl]# scp *.pem root@192.168.209.132:/etc/etcd/ssl/
```

以上几步完成etcd证书生成。

### 二、部署 etcd 集群

**1. 下载etcd，解压缩并同步二进制文件到其他节点**

```powershell
[root@master-01 ~]# wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
[root@master-01 ~]# tar zxvf etcd-v3.4.13-linux-amd64.tar.gz 
[root@master-01 ~]# cd etcd-v3.4.13-linux-amd64
[root@master-01 etcd-v3.3.12-linux-amd64]# cp etcd etcdctl /usr/bin/
[root@master-01 etcd-v3.3.12-linux-amd64]# scp etcd etcdctl root@192.168.209.131:/usr/bin/
[root@master-01 etcd-v3.3.12-linux-amd64]# scp etcd etcdctl root@192.168.209.132:/usr/bin/
```

**2. 创建 etcd 数据目录**

```powershell
[root@master-01 ~]# mkdir /var/lib/etcd
```

**3. etcd 配置文件创建**

```powershell
[root@master-01 ~]# cat /etc/etcd/etcd.conf 
# configure file for etcd.service
#[Member]
ETCD_NAME="infra1" 
ETCD_DATA_DIR="/var/lib/etcd/infra1.etcd"
ETCD_LISTEN_PEER_URLS="https://192.168.209.130:2380"
ETCD_LISTEN_CLIENT_URLS="https://192.168.209.130:2379,http://127.0.0.1:2379"

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.209.130:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.209.130:2379,http://127.0.0.1:2379"
ETCD_INITIAL_CLUSTER="infra1=https://192.168.209.130:2380,infra2=https://192.168.209.131:2380,infra3=https://192.168.209.132:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"

#[Security]
ETCD_CERT_FILE="/etc/etcd/ssl/server.pem"
ETCD_KEY_FILE="/etc/etcd/ssl/server-key.pem"
ETCD_TRUSTED_CA_FILE="/etc/etcd/ssl/ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CERT_FILE="/etc/etcd/ssl/server.pem"
ETCD_PEER_KEY_FILE="/etc/etcd/ssl/server-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/etc/etcd/ssl/ca.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
```

> \# 配置字段说明
> 
> ETCD_NAME 节点名称
> 
> ETCD_DATA_DIR 数据目录
> 
> ETCD_LISTEN_PEER_URLS 集群通信监听地址
> 
> ETCD_LISTEN_CLIENT_URLS 客户端访问监听地址
> 
> ETCD_INITIAL_ADVERTISE_PEER_URLS 集群通告地址
> 
> ETCD_ADVERTISE_CLIENT_URLS 客户端通告地址
> 
> ETCD_INITIAL_CLUSTER 集群节点地址
> 
> ETCD_INITIAL_CLUSTER_TOKEN 集群Token
> 
> ETCD_INITIAL_CLUSTER_STATE 加入集群的当前状态，new是新集群，existing表示加入已有集群

**注意:**  master-02、master-03节点上需要修改 ETCD_NAME 和对应IP地址

**4. 创建etcd启动文件，后续通过systemctl控制**

```powershell
[root@master-01 ~]# cat /usr/lib/systemd/system/etcd.service
[Unit]
Description=Etcd
ServerAfter=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=-/etc/etcd/etcd.conf
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /usr/bin/etcd"
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

**5. 同步配置及启动文件到 mater02、master-03**

```powershell
[root@master-01 ~]# scp /etc/etcd/etcd.conf 192.168.209.132:/etc/etcd/
[root@master-01 ~]# scp /etc/etcd/etcd.conf 192.168.209.131:/etc/etcd/
[root@master-01 ~]# scp /usr/lib/systemd/system/etcd.service 192.168.209.131:/usr/lib/systemd/system/
[root@master-01 ~]# scp /usr/lib/systemd/system/etcd.service 192.168.209.132:/usr/lib/systemd/system/
```

**6. 启动etcd集群**

master-02、master-03 执行相同命令

```powershell
[root@master-01 ssl]# systemctl daemon-reload
[root@master-01 ssl]# systemctl enable etcd
[root@master-01 ssl]# systemctl start etcd
```

### 三、校验集群状态

```powershell
[root@master-01 ssl]# etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://192.168.209.130:2379,https://192.168.209.131:2379,https://192.168.209.132:2379" member list
1c8b07efb474fea, started, etcd-server-02, https://172.16.207.129:2380, http://127.0.0.1:2379,https://192.168.209.130:2379, false
504f425034d8a094, started, etcd-server-01, https://172.16.207.128:2380, http://127.0.0.1:2379,https://192.168.209.131:2379, false
76dd860060381dfa, started, etcd-server-03, https://172.16.207.130:2380, https://192.168.209.132:2379, false

[root@master-01 ssl]# etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://192.168.209.130:2379,https://192.168.209.131:2379,https://192.168.209.132:2379" endpoint health
https://192.168.209.130:2379 is healthy: successfully committed proposal: took = 42.168436ms
https://192.168.209.131:2379 is healthy: successfully committed proposal: took = 16.380644ms
https://192.168.209.132:2379 is healthy: successfully committed proposal: took = 19.300105ms

[root@master-01 ssl]# etcdctl put /testdir/testkey "hello world"
OK
[root@master-01 ssl]# etcdctl get /testdir/testkey
/testdir/testkey
hello world
```

如果状态与上面相同，说明 etcd 集群部署成功啦。

