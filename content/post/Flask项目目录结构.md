---
title: "Flask 项目目录结构"
date: 2020-10-19T12:43:14+08:00
draft: false
tags: 
  - flask
categories: 
  - Flask
---

### Flask 项目目录结构

翻译原文：https://lepture.com/en/2018/structure-of-a-flask-project

> Flask 非常灵活，它没有一个固定的项目目录组织结构。这里写的只是我的一些建议。



#### 基于功能的结构

```csharp
project/
  __init__.py
  models/
    __init__.py
    base.py
    users.py
    posts.py
    ...
  routes/
    __init__.py
    home.py
    account.py
    dashboard.py
    ...
  templates/
    base.html
    post.html
    ...
  services/
    __init__.py
    google.py
    mail.py
    ...
```

一切都是按功能分组的。如果它的行为像模型，则将它放在 models 目录；如果它的行为像路由，则将它放入 routes 目录。在 `project/__init__.py`中创建一个`create_app`工厂函数，并且初始化所有应用 init_app：

```python
# project/__init__.py
from flask import Flask

def create_app():
  from . import models, routes, services
  app = Flask(__name__)
  models.init_app(app)
  routes.init_app(app)
  services.init_app(app)
  return app
```

在每个目录下的`__init__.py`中定义一个`init_app`函数，并且统一初始化进程：

```python
# project/models/__init__.py
from .base import db

def init_app(app):
    db.init_app(app)

# project/routes/__init__.py
from .users import user_bp
from .posts import posts_bp
# ...

def init_app(app):
    app.register_blueprint(user_bp)
    app.register_blueprint(posts_bp)    

# ...
```



#### 基于应用的机构

按照业务项目的应用程序来分组，例如：

```csharp
project/
  __init__.py
  db.py
  auth/
    __init__.py
    route.py
    models.py
    templates/
  blog/
    __init__.py
    route.py
    models.py
    templates/
...
```

每个目录都对应一个应用。Django 默认是使用这种方式来组织目录。当然这并不意味该方式是很好的，你需要按照项目来选择目录结构。某些时候，你将不得不使用一个混合模式。

初始化应用 init_app：

```python
# project/__init__.py
from flask import Flask

def create_app()
    from . import db, auth, blog
    app = Flask(__name__)
    db.init_app(app)
    auth.init_app(app)
    blog.init_app(app)
    return app
```



#### 配置

加载配置将是另一个问题，我不知道其他人是怎么做的，我只是分享我的解决方案。

1. 在项目目录下放一个 `settings.py` 文件，把它当作静态配置。
2. 从环境变量中加载配置。
3. 在 `create_app` 中更新配置。

这是一个配置的基础目录结构：

```csharp
conf/
  dev_config.py
  test_config.py
project/
  __init__.py
  settings.py
app.py
```

定义一个 `create_app` 来加载配置和环境变量：

```python
# project/__init__.py
import os
from flask import Flask

def create_app(config=None)
    app = Flask(__name__)
    # load default configuration
    app.config.from_object('project.settings')
    # load environment configuration
    if 'FLASK_CONF' in os.environ:
        app.config.from_envvar('FLASK_CONF')
    # load app sepcified configuration
    if config is not None:
        if isinstance(config, dict):
            app.config.update(config)
        elif config.endswith('.py'):
            app.config.from_pyfile(config)
    return app
```

`FLASK_CONF` 是一个包含配置的 python 文件（包含路径）。这可以是任何你想要的名称, 如项目叫做 `Expanse`，你可以叫它 `Expanse_CONF`。

我使用 `FLASK_CONF` 来加载生产环境的配置。

再一次说明，Flask 是非常灵活的，没有固定的模式。在 Flask 中你总是可以找到你所喜欢的。以上只是我的建议方案，不要被任何人蒙住眼睛。

