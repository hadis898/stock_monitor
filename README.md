![image](https://img.imgdd.com/f210f3.88da9bed-93d8-450f-b8fa-3c2aebf19077.png)
# 介绍
独角数卡 发卡价格库存监控 Python 脚本，主要用于对监测同行的发卡库存情况与价格变动，通过telegram bot进行通知提醒，便于及时掌握商品库和价格变动。

# 支持类型
万能监测，对所有网站都有效，不管你监测什么内容，只要更改关键词 匹配正则表达式就行。

# 部署说明
python版本
1. 安装依赖: pip install requests [如果pip安装报错，解决方法](https://www.upx8.com/4545)
2. 在 MONITOR_URLS 中添加要监控的商品链接和名称
3. 替换 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID
4. 运行命令: sudo python3 stock_monitor.py
5. ~~建议使用 systemd 管理进程， [systemd 使用教程](https://www.upx8.com/4537)~~ （已集成）

shell版本 （停止维护，一个py就够用了）
1. 运行脚本bash stock_monitor.sh
2. 功能和py脚本一样
# 参数配置

```
CHECK_INTERVAL = 180  # 检查间隔（秒）
STOCK_PATTERN = r'库存\((\d+)\)'  # 匹配库存的正则表达式
PRICE_PATTERN = r'价格\s*(\d+\.\d+)'  # 匹配价格的正则表达式
MAX_WORKERS = 5  # 并发线程数
```
# 更新日志
2024.12.13
1. 增加了异常类型捕获和处理
2. 对网络异常增加重试机制
3. 出现严重异常时仅记录日志，不推送Telegram通知

2024.12.09
1. 优化获取商品库存和价格的函数,处理异常情况。
2. 优化库存变化监控主函数,持续监控所有配置的商品。

2024.12.08
1. 增加了一个shell版本
2. 减少依赖

2024.12.07
1. 优化代码，改善用户体验
2. 新增 数字选项
3. 集成了systemd管理，一键配置启动
4. 检查systemd状态
5. 重启systemd
6. 移除systemd配置

2024.12.06
1. 集成了相关依赖
