#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# 检查并自动安装依赖
def check_and_install_dependencies():
    try:
        import requests
    except ImportError:
        print("正在安装 requests 依赖...")
        import sys
        import subprocess
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
        print("requests 依赖安装成功！")

check_and_install_dependencies()

import requests
import re
import time
import logging
import traceback
from typing import Optional, List, Dict
from concurrent.futures import ThreadPoolExecutor, as_completed

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN = 'TELEGRAM_BOT_TOKEN'  # 替换为您的电报 Token
TELEGRAM_CHAT_ID = 'TELEGRAM_CHAT_ID'  # 替换为您的电报聊天ID

# 监控配置，可以多地址监控
MONITOR_URLS = [
    {'url': 'https://cloud.upx8.com/buy/1', 'name': '云服务器（香港）'},
    {'url': 'https://cloud.upx8.com/buy/2', 'name': '云服务器（美国）'},
]
CHECK_INTERVAL = 180  # 检查间隔（秒）
STOCK_PATTERN = r'库存\((\d+)\)'  # 根据你网站实际内容 匹配库存的正则表达式
PRICE_PATTERN = r'¥\s*(\d+\.\d+)'  #根据你网站实际内容 匹配价格的正则表达式
MAX_WORKERS = 6  # 并发线程数

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s: %(message)s',
    handlers=[
        logging.FileHandler('stock_monitor.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)

class StockMonitor:
    def __init__(self, telegram_bot_token: str, telegram_chat_id: str):
        self.bot_token = telegram_bot_token
        self.chat_id = telegram_chat_id
        self.stock_states: Dict[str, Optional[int]] = {}
        self.price_states: Dict[str, Optional[float]] = {}
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
        })

    def get_current_stock_and_price(self, url: str, product_name: str) -> Dict[str, Optional[int]]:
        """
        获取当前商品库存数量和价格
        """
        try:
            response = self.session.get(url, timeout=10)
            response.raise_for_status()

            stock_match = re.search(STOCK_PATTERN, response.text)
            price_match = re.search(PRICE_PATTERN, response.text)

            stock = int(stock_match.group(1)) if stock_match else None
            price = float(price_match.group(1)) if price_match else None

            if not stock_match:
                logging.warning(f"{product_name} 未找到库存信息")
            if not price_match:
                logging.warning(f"{product_name} 未找到价格信息")

            return {'stock': stock, 'price': price}
        except requests.RequestException as e:
            logging.error(f"{product_name} 获取页面失败: {e}")
            return {'stock': None, 'price': None}

    def send_telegram_message(self, message: str):
        try:
            url = f'https://api.telegram.org/bot{self.bot_token}/sendMessage'
            params = {
                'chat_id': self.chat_id,
                'text': message
            }
            response = requests.post(url, data=params, timeout=10)
            response.raise_for_status()
            logging.info(f"Telegram通知发送成功: {message}")
        except requests.RequestException as e:
            logging.error(f"发送Telegram通知失败: {e}")

    def check_stock_changes(self, monitored_urls: List[Dict[str, str]]):
        """
        并发检查多个URL的库存和价格变化
        """
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = [
                (item, executor.submit(self.get_current_stock_and_price, item['url'], item['name']))
                for item in monitored_urls
            ]

            for url_info, future in futures:
                try:
                    current_info = future.result()
                    current_stock = current_info['stock']
                    current_price = current_info['price']

                    previous_stock = self.stock_states.get(url_info['url'])
                    previous_price = self.price_states.get(url_info['url'])

                    if previous_stock is None or previous_price is None:
                        self.stock_states[url_info['url']] = current_stock
                        self.price_states[url_info['url']] = current_price
                        logging.info(f"{url_info['name']} 价格: ¥{current_price}, 初始库存: {current_stock}")

                    elif current_stock != previous_stock or current_price != previous_price:
                        change_info = f"商品库存变化提醒\n" \
                                      f"商品: {url_info['name']}\n" \
                                      f"库存: {previous_stock} -> {current_stock}\n" \
                                      f"价格: ¥{previous_price} -> ¥{current_price}\n" \
                                      f"链接: {url_info['url']}"
                        logging.info(change_info)
                        self.send_telegram_message(change_info)

                        self.stock_states[url_info['url']] = current_stock
                        self.price_states[url_info['url']] = current_price

                except Exception as e:
                    error_info = f"{url_info['name']} 检查过程发生异常:\n{traceback.format_exc()}"
                    logging.error(error_info)
                    self.send_telegram_message(error_info)

    def monitor(self, monitored_urls: List[Dict[str, str]]):
        """
        持续监控商品库存和价格变化
        """
        logging.info(f"开始监控 {len(monitored_urls)} 个商品的库存变化")
        while True:
            try:
                self.check_stock_changes(monitored_urls)
                time.sleep(CHECK_INTERVAL)
            except Exception as e:
                error_info = f"监控过程发生异常:\n{traceback.format_exc()}"
                logging.error(error_info)
                self.send_telegram_message(error_info)
                time.sleep(CHECK_INTERVAL)


def main():
    monitor = StockMonitor(
        telegram_bot_token=TELEGRAM_BOT_TOKEN,
        telegram_chat_id=TELEGRAM_CHAT_ID
    )
    try:
        monitor.monitor(MONITOR_URLS)
    except KeyboardInterrupt:
        logging.info("程序被手动终止")


if __name__ == '__main__':
    main()
