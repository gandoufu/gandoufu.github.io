---
title: "Docker 基础命令"
date: 2020-09-28T14:13:03+08:00
draft: false
tags: 
  - docker
categories: 
  - Docker
---

#### 镜像

- docker search
- docker search -s 200
  - 搜索 star 数多于 200 的镜像
- docker pull
- docker images
- docker images -a
- docker images -qa
  - 仅显示镜像 ID
- docker images centos
  - 查看某一个具体的镜像
- docker images --digests
- docker images -a --no-trunc
- docker rmi
- docker rmi -f
  - 强制删除镜像



#### 容器

- docker run -it
- docker run -d
  - daemon 形式启动，容器中要有进程运行，否则容器启动后会立即退出
- docker ps
  - 查看运行状态的容器
- docker ps -a
  - 查看所有容器（包含停止状态的）
- docker ps -aq
- docker ps -l
  - 上一个运行的容器
- docker ps -n 3
  - 上 3 次运行的容器
- docker pause
- docker unpause

- docker start
- docker restart
- docker stop
- docker kill
  - 强制停止容器
- docker rm
- docker rm -f
- docker rm -f $(docker ps -qa)
- docker ps -aq | xargs docker rm
- docker top
  - 查看容器中的进程信息
- docker stats
  - docker 容器资源使用统计
- docker diff
  - 检查一个容器文件系统更改情况

#### 退出容器

当处于容器中时，有 2 种方式退出容器：

1. exit

   退出，并停止容器

2. ctrl + q + p

   退出，但不停止容器



#### 进入容器

- docker attach 
- docker exec -it container_id /bin/sh



#### 拷贝文件

- docker cp container_id:/path/of/file /path/to/target



#### 查看日志

- docker logs container_id
- docker logs -f container_id
  - 实时跟踪日志，类似 tail -f
- docker logs --tail 10 container_id
  - 查看最后 10 行日志
- docker logs -f -t --since="2020-09-10" --tail=100 cotainer_id
  - 查看指定日期之后的日志，只显示最后 100 条
- docker logs --since="2020-09-10T09:30:25" --until "2020-09-10T10:30:00" container_id
  - 查看指定时间段的日志



#### docker commit

以某个镜像启动容器后，在容器内做一些个性化的修改，然后可以通过 docker commit 命令生成新的镜像。

- docker commit -m "注释信息" -a "作者" container_id 要创建的目标镜像名:[标签名]



#### 容器数据卷

启动容器时，可以使用`-v`选项关联宿主机的 volume，实现宿主机和容器内文件内共享。

- docker run -d -it -v 宿主机文件夹路径:容器内文件夹路径 镜像ID



