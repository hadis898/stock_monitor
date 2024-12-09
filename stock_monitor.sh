#!/bin/bash

# 库存监控脚本
# 功能：监控指定网站的商品库存和价格变化，并通过Telegram发送通知
# 版本：1.3
# 依赖：curl, systemctl

# Telegram机器人配置
TELEGRAM_BOT_TOKEN='TELEGRAM_BOT_TOKEN'  # 替换为您的电报 Token
TELEGRAM_CHAT_ID='TELEGRAM_CHAT_ID'  # 替换为您的电报聊天ID

# 监控参数配置
CHECK_INTERVAL=180    # 检查间隔，单位：秒(默认3分钟)
MAX_WORKERS=6         # 并发工作线程数（在Bash中主要用于日志控制）
LOG_FILE="stock_monitor.log"  # 日志文件路径

# 监控配置，可以多地址监控
declare -A MONITOR_URLS=(
    ["https://cloud.upx8.com/buy/1"]="云服务器（香港）"
    ["https://cloud.upx8.com/buy/2"]="云服务器（美国）"
)

# 日志记录函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $level: $message" | tee -a "$LOG_FILE"
}

# Telegram消息发送函数
send_telegram_message() {
    local message="$1"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    
    # 发送消息并记录结果
    local response=$(curl -s -X POST "$url" -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=${message}")
    if [[ $? -eq 0 ]]; then
        log "INFO" "Telegram通知发送成功"
    else
        log "ERROR" "Telegram通知发送失败: $response"
    fi
}

# 获取商品库存和价格函数
get_current_stock_and_price() {
    local url="$1"
    local product_name="$2"
    
    local page_content=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "$url")
    
    local stock=$(echo "$page_content" | grep -oP '库存\((\d+)\)' | sed -n 's/库存(\([0-9]\+\))/\1/p')
    
    local price=$(echo "$page_content" | grep -oP '¥\s*(\d+\.\d+)' | sed -n 's/¥\s*//p')
    
    if [[ -z "$stock" ]] || [[ -z "$price" ]]; then
        log "WARNING" "$product_name: 无法提取库存或价格信息"
        return 1
    fi
    
    echo "$stock,$price"
}

# 功能：持续监控所有配置的商品，检测库存和价格变化
monitor_stock_changes() {
    declare -A previous_stocks
    declare -A previous_prices
    
    log "INFO" "开始监控 ${#MONITOR_URLS[@]} 个商品"
    
    while true; do
        # 遍历所有监控的URL
        for url in "${!MONITOR_URLS[@]}"; do
            product_name="${MONITOR_URLS[$url]}"
            
            result=$(get_current_stock_and_price "$url" "$product_name")
            
            if [[ $? -eq 0 ]]; then
                IFS=',' read -r current_stock current_price <<< "$result"
                
                # 首次检查时记录初始状态
                if [[ -z "${previous_stocks[$url]}" ]] || [[ -z "${previous_prices[$url]}" ]]; then
                    previous_stocks[$url]="$current_stock"
                    previous_prices[$url]="$current_price"
                    log "INFO" "$product_name - 初始库存: $current_stock, 价格: $current_price"
                    continue
                fi
                
                # 检查库存或价格是否发生变化
                if [[ "$current_stock" != "${previous_stocks[$url]}" ]] || [[ "$current_price" != "${previous_prices[$url]}" ]]; then
                    # 准备变化通知信息
                    change_message="库存变化提醒\n\n"
                    change_message+="商品: $product_name\n"
                    change_message+="库存: ${previous_stocks[$url]} -> $current_stock\n"
                    change_message+="价格: ¥${previous_prices[$url]} -> ¥$current_price\n"
                    change_message+="链接: $url"
                    
                    # 记录日志并发送Telegram通知
                    log "INFO" "$change_message"
                    send_telegram_message "$change_message"
                    
                    # 更新前一状态
                    previous_stocks[$url]="$current_stock"
                    previous_prices[$url]="$current_price"
                fi
            fi
        done
        
        sleep "$CHECK_INTERVAL"
    done
}

# 功能：为脚本创建并启用systemd服务，实现开机自启和后台运行
setup_systemd_service() {
    local script_path=$(readlink -f "$0")
    local service_file="/etc/systemd/system/stock_monitor.service"
    
    # 创建systemd服务配置文件
    cat > "$service_file" << EOF
[Unit]
Description=Stock Monitor Service
After=network.target

[Service]
ExecStart=$script_path --run
WorkingDirectory=$(dirname "$script_path")
StandardOutput=inherit
StandardError=inherit
Restart=always
RestartSec=30s
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

    # 重载systemd配置，启用并启动服务
    systemctl daemon-reload
    systemctl enable stock_monitor.service
    systemctl start stock_monitor.service
    
    echo -e "\033[32m√ 已设置并启动Stock Monitor的Systemd服务\033[0m"
}

# 检查Systemd服务状态函数
# 功能：显示服务当前运行状态
check_systemd_status() {
    systemctl status stock_monitor.service
}

# 重启Systemd服务函数
# 功能：重新启动服务，用于加载配置变更
restart_systemd_service() {
    systemctl restart stock_monitor.service
    echo -e "\033[32m√ Stock Monitor服务已重新启动\033[0m"
}

# 移除Systemd服务函数
# 功能：停止并删除服务配置
remove_systemd_service() {
    systemctl stop stock_monitor.service
    systemctl disable stock_monitor.service
    rm -f /etc/systemd/system/stock_monitor.service
    systemctl daemon-reload
    echo -e "\033[32m√ 已移除Stock Monitor的Systemd服务配置\033[0m"
}

# 主函数 - 脚本入口
# 功能：处理命令行参数和交互菜单
main() {
    # 检查必需的系统命令
    for cmd in curl systemctl tee; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "错误：$cmd 未安装。请先安装该命令。"
            exit 1
        fi
    done

    # 参数解析
    if [[ "$1" == "--run" ]]; then
        # 直接运行监控
        monitor_stock_changes
    else
        # 交互式菜单
        while true; do
            echo -e "\033[34m\n选择操作：\033[0m"
            echo "1. 临时运行 - 测试功能"
            echo "2. 后台运行 - 配置Systemd服务"
            echo "3. 检查Systemd服务状态"
            echo "4. 重启Systemd服务"
            echo "5. 移除Systemd服务"
            echo "0. 退出"
            
            read -p "请选择操作（0-5）：" choice
            
            case $choice in
                1) 
                    monitor_stock_changes
                    ;;
                2) 
                    setup_systemd_service
                    ;;
                3) 
                    check_systemd_status
                    ;;
                4) 
                    restart_systemd_service
                    ;;
                5) 
                    remove_systemd_service
                    ;;
                0) 
                    echo -e "\033[31m√ 退出程序\033[0m"
                    exit 0
                    ;;
                *) 
                    echo "无效的选项。请输入0-5之间的数字。"
                    ;;
            esac
        done
    fi
}

# 执行主函数
main "$@"
