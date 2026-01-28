# custom_functions.sh

x_install_command() {
    echo "正在安装 k 命令..."
    
	sed -i '/^alias k=/d' ~/.bashrc > /dev/null 2>&1
	sed -i '/^alias k=/d' ~/.profile > /dev/null 2>&1
	sed -i '/^alias k=/d' ~/.bash_profile > /dev/null 2>&1
	cp -f ./kejilion.sh ~/kejilion.sh > /dev/null 2>&1
	cp -f ~/kejilion.sh /usr/local/bin/k > /dev/null 2>&1
    chmod +x /usr/local/bin/k > /dev/null 2>&1
    
    echo "k 命令安装完成。请重新打开终端。"
}



x_new_rules_port() {
    install iptables
    
    if [ -f "/etc/iptables/rules.v4" ]; then
        cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak
        echo "当前防火墙规则已备份到 /etc/iptables/rules.v4.bak"
    fi

    cat <<'EOF' > /etc/iptables/rules.v4
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A INPUT -p udp -m udp --dport 443 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 5522 -j ACCEPT
COMMIT
EOF

    iptables-restore < /etc/iptables/rules.v4
    
    save_iptables_rules

    echo "防火墙策略已更新并持久化。仅开放主要端口: SSH(22), HTTP(80), HTTPS(443), SSH(5522)"
}



x_show_auth_menu() {
    clear
    echo -e "${gl_huang}============= 选择证书验证模式 =============${gl_bai}"
    echo " 1) Cloudflare API Token 验证 (推荐)"
    echo " 2) Cloudflare Global API Key 验证"
    echo " 3) HTTP 验证 (standalone，不支持泛域名)"
    echo " 4) 腾讯云 DNSPod DNS 验证"
    echo " 5) 阿里云 Aliyun DNS 验证"
    echo " 0) 返回主菜单"
    echo -e "${gl_huang}============================================${gl_bai}"
}



x_configure_auth() {
    local auth_mode=$1
    local dns_plugin=""
    local credentials_file=""
    local CERTS_DIR="/home/web/certs"

    sudo mkdir -p "$CERTS_DIR"

    case "$auth_mode" in
        1|2) dns_plugin="dns-cloudflare" ;;
        4)   dns_plugin="dns-dnspod" ;;
        5)   dns_plugin="dns-aliyun" ;;
    esac

    if [ -n "$dns_plugin" ]; then
        credentials_file="${CERTS_DIR}/${dns_plugin}.ini"
    fi
    
    case "$auth_mode" in
        1) # Cloudflare API Token
            read -rp "请输入 Cloudflare API Token: " CF_Token
            
            echo "dns_cloudflare_api_token = $CF_Token" | sudo tee "$credentials_file" > /dev/null
            sudo chmod 600 "$credentials_file"
            
            echo -e "${gl_lv}Cloudflare API Token 已写入 ${credentials_file}。${gl_bai}"
            ;;
        2) # Cloudflare Global API Key
            read -rp "请输入 Cloudflare 邮箱: " CF_Email
            read -rp "请输入 Global API Key: " CF_Key
            
            # 写入凭证文件
            cat <<EOF | sudo tee "$credentials_file" > /dev/null
dns_cloudflare_email = $CF_Email
dns_cloudflare_api_key = $CF_Key
EOF
            sudo chmod 600 "$credentials_file"
            
            echo -e "${gl_lv}Cloudflare Global API Key 已写入 ${credentials_file}。${gl_bai}"
            ;;
        4) # 腾讯云 DNSPod
            read -rp "请输入 DNSPod ID: " DNSPOD_ID
            read -rp "请输入 DNSPod Token: " DNSPOD_TOKEN
            
            cat <<EOF | sudo tee "$credentials_file" > /dev/null
dns_dnspod_id = $DNSPOD_ID
dns_dnspod_token = $DNSPOD_TOKEN
EOF
            sudo chmod 600 "$credentials_file"
            
            echo -e "${gl_lv}DNSPod 凭证已写入 ${credentials_file}。${gl_bai}"
            ;;
        5) # 阿里云 Aliyun
            read -rp "请输入 Aliyun Access Key ID: " ALIYUN_ID
            read -rp "请输入 Aliyun Access Key Secret: " ALIYUN_SECRET
            
            cat <<EOF | sudo tee "$credentials_file" > /dev/null
dns_aliyun_access_key_id = $ALIYUN_ID
dns_aliyun_access_key_secret = $ALIYUN_SECRET
EOF
            sudo chmod 600 "$credentials_file"
            
            echo -e "${gl_lv}Aliyun 凭证已写入 ${credentials_file}。${gl_bai}"
            ;;
    esac
}



x_reload_services() {
    echo -e "${gl_lv}正在重载 Nginx 和 3X-UI 以应用新证书...${gl_bai}"
    
    if sudo docker ps -q -f name=nginx | grep -q .; then
        sudo docker exec nginx nginx -s reload
        echo -e "${gl_lv}Nginx 已重载。${gl_bai}"
    fi
    
    local COMPOSE_DIR="/home/docker/3x-ui"
    if [ -d "$COMPOSE_DIR" ] && sudo docker ps -q -f name=3x-ui | grep -q .; then
        cd "$COMPOSE_DIR" && sudo docker compose restart 3x-ui
        echo -e "${gl_lv}3X-UI 已重启。${gl_bai}"
    fi
    cd ~
}



x_issue_certificate() {
    local domain=$1
    local auth_mode=$2
    local force_renew=${3:-false}
    local CERTS_DIR="/home/web/certs"
    local LOG_FILE="${CERTS_DIR}/cert_renew.log"
    local EMAIL="${CERT_EMAIL}"
    local certbot_image=""
    local certbot_args=()
    local dns_plugin=""
    local credentials_file=""

    echo -e "${gl_lv}[PROCESS] 正在处理: $domain${gl_bai}"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${gl_hong}错误: 您输入的 '$domain' 似乎不是一个有效的域名格式。请重新输入。${gl_bai}"
        return 1
    fi

    case "$auth_mode" in
        1|2) # Cloudflare
            certbot_image="certbot/dns-cloudflare"
            dns_plugin="dns-cloudflare"
            ;;
        3) # HTTP
            certbot_image="certbot/certbot"
            ;;
        4) # DNSPod
            certbot_image="certbot/dns-dnspod"
            dns_plugin="dns-dnspod"
            ;;
        5) # Aliyun
            certbot_image="certbot/dns-aliyun"
            dns_plugin="dns-aliyun"
            ;;
        *)
            echo -e "${gl_hong}内部错误: 无效的验证模式 $auth_mode${gl_bai}"
            return 1
            ;;
    esac

    if [ -n "$dns_plugin" ]; then
        credentials_file="${CERTS_DIR}/${dns_plugin}.ini"
        certbot_args+=(--${dns_plugin}-credentials "/etc/letsencrypt/${dns_plugin}.ini" --${dns_plugin}-propagation-seconds 60)
    fi

    echo -e "${gl_lv}正在尝试拉取 Certbot 镜像: $certbot_image ...${gl_bai}"
    if ! sudo docker pull "$certbot_image:latest"; then
        echo -e "${gl_hong}错误：Certbot 镜像拉取失败！${gl_bai}"
        echo -e "${gl_huang}原因：网络连接 Docker Hub 超时。${gl_bai}"
        echo -e "${gl_lv}建议：${gl_bai}"
        echo -e "1. 检查您的 VPS 网络连接和防火墙设置。"
        echo -e "2. 尝试配置 Docker 镜像加速器（主菜单选项 9）。"
        return 1
    fi

    if [[ "$auth_mode" == "3" ]]; then
        local stopped_nginx=false
        if sudo docker ps -q -f name=nginx | grep -q .; then
            echo -e "${gl_huang}80端口被占用，临时停止 nginx...${gl_bai}"
            sudo docker stop nginx 2>/dev/null || true
            stopped_nginx=true
        fi

        sudo docker run --rm \
            -v "/etc/letsencrypt:/etc/letsencrypt" \
            -p 80:80 \
            "$certbot_image" certonly \
            --standalone \
            -d "$domain" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            --key-type ecdsa \
            ${force_renew:+--force-renewal} 2>&1 | tee -a "$LOG_FILE"

        if [[ "$stopped_nginx" == true ]]; then
            echo -e "${gl_lv}恢复 nginx...${gl_bai}"
            sudo docker start nginx 2>/dev/null || true
        fi
    else
        if [ ! -f "$credentials_file" ]; then
            echo -e "${gl_hong}错误: 凭证文件 ${credentials_file} 不存在。请先运行选项 7 配置凭证。${gl_bai}"
            return 1
        fi

        sudo docker run --rm \
            -v "/etc/letsencrypt:/etc/letsencrypt" \
            -v "$credentials_file:/etc/letsencrypt/$dns_plugin.ini:ro" \
            "$certbot_image" certonly \
            --$dns_plugin \
            -d "$domain" -d "*.$domain" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            --key-type ecdsa \
            ${force_renew:+--force-renewal} "${certbot_args[@]}" 2>&1 | tee -a "$LOG_FILE"
    fi

    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        sudo mkdir -p "${CERTS_DIR}"
        sudo cp -f "/etc/letsencrypt/live/$domain/fullchain.pem" "${CERTS_DIR}/${domain}_cert.pem"
        sudo cp -f "/etc/letsencrypt/live/$domain/privkey.pem" "${CERTS_DIR}/${domain}_key.pem"
        echo -e "${gl_lv}[SUCCESS] 证书处理完成: $domain${gl_bai}"
        
        x_reload_services
        return 0
    else
        send_stats "域名证书申请失败"
        echo -e "${gl_hong}证书申请失败，请检查端口、解析、防火墙等问题。${gl_bai}"
        return 1
    fi
}



x_configure_initial_settings() {
    if [ -z "$CERT_EMAIL" ] || [ "$CERT_EMAIL" == "your_email@example.com" ]; then
        echo -e "\n${gl_huang}===================================================${gl_bai}"
        echo -e "${gl_lv}     SSL 证书邮箱配置向导     ${gl_bai}"
        echo -e "${gl_huang}===================================================${gl_bai}"
        
        read -e -p "请输入您的证书通知邮箱 (仅首次，回车自动生成随机邮箱): " user_email
        
        if [[ -z "$user_email" ]]; then
            # 自动生成随机邮箱
            RANDOM_STRING=$(head /dev/urandom | tr -dc a-z0-9 | head -c 10)
            CERT_EMAIL="${RANDOM_STRING}@gmail.com"
            echo -e "${gl_lv}邮箱已自动生成并设置为: $CERT_EMAIL${gl_bai}"
        elif [[ "$user_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
            # 用户输入有效邮箱
            CERT_EMAIL="$user_email"
            echo -e "${gl_lv}邮箱已设置为: $CERT_EMAIL${gl_bai}"
        else
            # 用户输入无效邮箱
            RANDOM_STRING=$(head /dev/urandom | tr -dc a-z0-9 | head -c 10)
            CERT_EMAIL="${RANDOM_STRING}@gmail.com"
            echo -e "${gl_hong}邮箱格式无效，已自动生成随机邮箱: $CERT_EMAIL${gl_bai}"
        fi
        
        echo -e "${gl_huang}===================================================${gl_bai}"
    fi
}

# =================================================================
# 菜单功能函数
# =================================================================

x_install_3x_ui() {
    install_docker
    
    local COMPOSE_DIR="/home/docker/3x-ui"
    local COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
    
    echo -e "${gl_lv}正在准备 3X-UI 容器环境...${gl_bai}"
    
    sudo mkdir -p "${COMPOSE_DIR}"
    sudo mkdir -p /home/web/certs
    
    cat <<'EOF' | sudo tee "${COMPOSE_FILE}" > /dev/null
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: always
    network_mode: host
    volumes:
      - /home/docker/3x-ui/db:/etc/x-ui
      - /home/web/certs:/root/cert:ro
    environment:
      - XRAY_VMESS_AEAD_FORCED=false
      - XUI_ENABLE_FAIL2BAN=false
      - XUI_ENABLE_HTTPS=false
EOF
    
    echo -e "${gl_lv}正在启动 3X-UI 容器...${gl_bai}"
    cd "${COMPOSE_DIR}"
    if sudo docker compose up -d; then
        echo -e "${gl_lv}3X-UI 容器已启动。${gl_bai}"
        echo -e "${gl_huang}注意: 3X-UI 使用 host 网络模式，面板端口默认为 2053。${gl_bai}"
    else
        echo -e "${gl_hong}错误：3X-UI 容器启动失败。${gl_bai}"
    fi
    
    cd ~
}



x_install_x-ui-yg() {
    install_docker
    
    local COMPOSE_DIR="/home/docker/x-ui-yg"
    local COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
    local DATA_DIR="/home/docker/x-ui-yg/data"
    local INIT_LOG="${DATA_DIR}/init.log"
    
    echo -e "${gl_lv}正在准备 x-ui-yg 容器环境...${gl_bai}"
    
    sudo mkdir -p "${COMPOSE_DIR}"
    sudo mkdir -p "${DATA_DIR}"
    sudo mkdir -p /home/web/certs
    
    cat <<'EOF' | sudo tee "${COMPOSE_FILE}" > /dev/null
services:
  x-ui-yg:
    image: shaogme/x-ui-yg:alpine
    container_name: x-ui-yg
    restart: always
    network_mode: host
    volumes:
      - /home/docker/x-ui-yg/data:/usr/local/x-ui
      - /home/web/certs:/root/cert
    environment:
      - TZ=Asia/Shanghai
      - XUI_USER=
      - XUI_PASS=
      - XUI_PORT=
      - XUI_PATH=
EOF
    
    echo -e "${gl_lv}正在启动 x-ui-yg 容器...${gl_bai}"
    cd "${COMPOSE_DIR}"

    if sudo docker compose up -d; then
        echo -e "${gl_lv}x-ui-yg 容器已启动。${gl_bai}"
        echo -e "${gl_lv}正在读取初始化信息 (init.log)...${gl_bai}"

        # 等待 init.log 生成（最多 10 秒）
        for i in {1..10}; do
            if [ -f "$INIT_LOG" ]; then

                # 解析 init.log（唯一事实来源）
                XUI_USER=$(grep -E '^XUI_USER' "$INIT_LOG" | awk -F':' '{print $2}' | xargs)
                XUI_PASS=$(grep -E '^XUI_PASS' "$INIT_LOG" | awk -F':' '{print $2}' | xargs)
                XUI_PORT=$(grep -E '^XUI_PORT' "$INIT_LOG" | awk -F':' '{print $2}' | xargs)
                XUI_PATH=$(grep -E '^XUI_PATH' "$INIT_LOG" | awk -F':' '{print $2}' | xargs)

                SERVER_IP=$(hostname -I | awk '{print $1}')

                echo -e "${gl_lv}========== x-ui-yg 初始化信息 ==========${gl_bai}"
                echo -e "用户名: ${XUI_USER}"
                echo -e "密码:   ${XUI_PASS}"
                echo -e "端口:   ${XUI_PORT}"
                echo -e "路径:   ${XUI_PATH}"
                echo -e "${gl_lv}========================================${gl_bai}"

                if [ -n "$SERVER_IP" ] && [ -n "$XUI_PORT" ] && [ -n "$XUI_PATH" ]; then
                    echo -e "${gl_lv}面板访问地址：${gl_bai}"
                    echo -e "${gl_huang}http://${SERVER_IP}:${XUI_PORT}${XUI_PATH}${gl_bai}"
                fi

                break
            fi
            sleep 1
        done

        if [ ! -f "$INIT_LOG" ]; then
            echo -e "${gl_huang}可手动查看：${INIT_LOG}${gl_bai}"
        fi
    else
        echo -e "${gl_hong}错误：x-ui-yg 容器启动失败。${gl_bai}"
    fi
    
    cd ~
}



x_apply_ssl() {
    install_docker
    x_configure_initial_settings

    while true; do
        x_show_auth_menu
        read -p "请输入你的选择 (0-5): " auth_choice

        case "$auth_choice" in
            1|2|4|5)
                x_configure_auth "$auth_choice"
                read -rp "请输入要申请的域名 (多个用空格分隔): " -a domains
                [[ ${#domains[@]} -eq 0 ]] && echo -e "${gl_hong}错误：未输入域名！${gl_bai}" && sleep 1 && continue
                
                local success=0
                for domain in "${domains[@]}"; do
                    if x_issue_certificate "$domain" "$auth_choice"; then
                        success=1
                    fi
                done
                
                if [[ $success -eq 1 ]]; then
                    yuming="${domains[0]}"
                    # 成功时才显示证书信息
                    install_ssltls_text
                    ssl_ps
                fi
                
                break_end
                return
                ;;
            3)
                read -rp "请输入要申请的域名 (多个用空格分隔): " -a domains
                [[ ${#domains[@]} -eq 0 ]] && echo -e "${gl_hong}错误：未输入域名！${gl_bai}" && sleep 1 && continue
                
                local success=0
                for domain in "${domains[@]}"; do
                    if x_issue_certificate "$domain" "3"; then
                        success=1
                    fi
                done
                
                if [[ $success -eq 1 ]]; then
                    yuming="${domains[0]}"
                    install_ssltls_text
                    ssl_ps
                fi
                
                break_end
                return
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效输入，请重新选择！${gl_bai}"; sleep 1 ;;
        esac
    done
}




x_view_status() {
    echo -e "${gl_lv}--- Docker服务及容器运行总览 ---${gl_bai}"
    sudo docker ps -a

    if [ $(sudo docker ps -a -q -f name=3x-ui) ]; then
        echo -e "\n${gl_lv}--- 3X-UI面板信息 ---${gl_bai}"
        
        LOG_OUTPUT=$(sudo docker logs 3x-ui 2>&1 | tail -n 50)
        
        # 提取 Web server 端口号，只保留数字
        WEB_PORT=$(echo "$LOG_OUTPUT" | grep "Web server running HTTP" | awk -F':' '{print $NF}' | head -n1)
        
        # 提取 admin 登录 IP
        ADMIN_IP=$(echo "$LOG_OUTPUT" | grep "admin logged in successfully, Ip Address" | awk -F'Ip Address: ' '{print $2}' | head -n1)
        
        if [[ -n "$WEB_PORT" && -n "$ADMIN_IP" ]]; then
            echo -e "${gl_lv}面板地址: ${gl_huang}http://${ADMIN_IP}:${WEB_PORT}${gl_bai}"
        else
            echo -e "${gl_hong}无法从日志中提取 IP 或端口，请查看容器日志。${gl_bai}"
        fi
    fi
}



x_kejilion_update() {

send_stats "脚本更新"
cd ~
while true; do
	clear
	echo "更新日志"
	echo "------------------------"
	echo "全部日志: ${gh_proxy}raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion_sh_log.txt"
	echo "------------------------"

	curl -s ${gh_proxy}raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion_sh_log.txt | tail -n 30
	local sh_v_new=$(curl -s ${gh_proxy}raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion | grep -o 'sh_v="[0-9.]*"' | cut -d '"' -f 2)

	if [ "$sh_v" = "$sh_v_new" ]; then
		echo -e "${gl_lv}你已经是最新版本！${gl_huang}v$sh_v${gl_bai}"
		send_stats "脚本已经最新了，无需更新"
	else
		echo "发现新版本！"
		echo -e "当前版本 v$sh_v        最新版本 ${gl_huang}v$sh_v_new${gl_bai}"
	fi


	local cron_job="kejilion"
	local existing_cron=$(crontab -l 2>/dev/null | grep -F "$cron_job")

	if [ -n "$existing_cron" ]; then
		echo "------------------------"
		echo -e "${gl_lv}自动更新已开启，每天凌晨2点脚本会自动更新！${gl_bai}"
	fi

	echo "------------------------"
	echo "1. 现在更新            2. 开启自动更新            3. 关闭自动更新"
	echo "------------------------"
	echo "0. 返回主菜单"
	echo "------------------------"
	read -e -p "请输入你的选择: " choice
	case "$choice" in
		1)
			clear
			local country=$(curl -s ipinfo.io/country)
			if [ "$country" = "CN" ]; then
				curl -sS -O ${gh_proxy}raw.githubusercontent.com/Rcftngqmgq/sh/main/cn/kejilion && chmod +x kejilion
			else
				curl -sS -O ${gh_proxy}raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion && chmod +x kejilion
			fi
			canshu_v6
			CheckFirstRun_true
			yinsiyuanquan2
			cp -f ~/kejilion /usr/local/bin/x > /dev/null 2>&1
			echo -e "${gl_lv}脚本已更新到最新版本！${gl_huang}v$sh_v_new${gl_bai}"
			send_stats "脚本已经最新$sh_v_new"
			break_end
			~/kejilion
			exit
			;;
		2)
			clear
			local country=$(curl -s ipinfo.io/country)
			local ipv6_address=$(curl -s --max-time 1 ipv6.ip.sb)
			if [ "$country" = "CN" ]; then
				SH_Update_task="curl -sS -O https://gh.kejilion.pro/raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion && chmod +x kejilion && sed -i 's/canshu=\"default\"/canshu=\"CN\"/g' ./kejilion"
			elif [ -n "$ipv6_address" ]; then
				SH_Update_task="curl -sS -O https://gh.kejilion.pro/raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion && chmod +x kejilion && sed -i 's/canshu=\"default\"/canshu=\"V6\"/g' ./kejilion"
			else
				SH_Update_task="curl -sS -O https://raw.githubusercontent.com/Rcftngqmgq/sh/main/kejilion && chmod +x kejilion"
			fi
			check_crontab_installed
			(crontab -l | grep -v "kejilion") | crontab -
			# (crontab -l 2>/dev/null; echo "0 2 * * * bash -c \"$SH_Update_task\"") | crontab -
			(crontab -l 2>/dev/null; echo "$(shuf -i 0-59 -n 1) 2 * * * bash -c \"$SH_Update_task\"") | crontab -
			echo -e "${gl_lv}自动更新已开启，每天凌晨2点脚本会自动更新！${gl_bai}"
			send_stats "开启脚本自动更新"
			break_end
			;;
		3)
			clear
			(crontab -l | grep -v "kejilion") | crontab -
			echo -e "${gl_lv}自动更新已关闭${gl_bai}"
			send_stats "关闭脚本自动更新"
			break_end
			;;
		*)
			kejilion_sh
			;;
	esac
done

}



send_stats() {
    return
}



x_all_in_one() {
    root_use
    send_stats "一条龙调优"
    echo "一条龙系统调优"
    echo "------------------------------------------------"
    echo "将对以下内容进行操作与优化"
    echo "1. 优化系统更新源，更新系统到最新"
    echo "2. 清理系统垃圾文件"
    echo -e "3. 设置虚拟内存${gl_huang}1G${gl_bai}"
    echo -e "4. 设置SSH端口号为${gl_huang}22${gl_bai}"
    echo -e "5. 启动fail2ban防御SSH暴力破解"
    echo -e "6. 开放主要端口：SSH(22), HTTP(80), HTTPS(443), 5522)"
    echo -e "7. 开启${gl_huang}BBR${gl_bai}加速"
    echo -e "8. 设置时区到${gl_huang}上海${gl_bai}"
    echo -e "9. 自动优化DNS地址${gl_huang}海外: 1.1.1.1 8.8.8.8  国内: 223.5.5.5 ${gl_bai}"
    echo -e "10. 设置网络为${gl_huang}ipv4优先${gl_bai}"
    echo -e "11. 安装基础工具${gl_huang}docker wget sudo tar unzip socat btop nano vim${gl_bai}"
    echo -e "12. Linux系统内核参数优化切换到${gl_huang}均衡优化模式${gl_bai}"
    echo "------------------------------------------------"
    read -e -p "确定一键保养吗？(Y/N): " choice

    case "$choice" in
        [Yy])
            clear
            send_stats "一条龙调优启动"
            echo "------------------------------------------------"
            switch_mirror false true
            linux_update
            echo -e "[${gl_lv}OK${gl_bai}] 1/12. 更新系统到最新"

            echo "------------------------------------------------"
            linux_clean
            echo -e "[${gl_lv}OK${gl_bai}] 2/12. 清理系统垃圾文件"

            echo "------------------------------------------------"
            add_swap 1024
            echo -e "[${gl_lv}OK${gl_bai}] 3/12. 设置虚拟内存${gl_huang}1G${gl_bai}"

            echo "------------------------------------------------"
			local new_port=5522
			new_ssh_port
			echo -e "[${gl_lv}OK${gl_bai}] 4/12. 设置SSH端口号为${gl_huang}5522${gl_bai}"

            echo "------------------------------------------------"
            f2b_install_sshd
            cd ~
            f2b_status
            echo -e "[${gl_lv}OK${gl_bai}] 5/12. 启动fail2ban防御SSH暴力破解"

            echo "------------------------------------------------"
            x_new_rules_port
            echo -e "[${gl_lv}OK${gl_bai}] 6/12. 开放主要端口: SSH(22), HTTP(80), HTTPS(443), SSH(5522)"

            echo "------------------------------------------------"
            bbr_on
            echo -e "[${gl_lv}OK${gl_bai}] 7/12. 开启${gl_huang}BBR${gl_bai}加速"

            echo "------------------------------------------------"
            set_timedate Asia/Shanghai
            echo -e "[${gl_lv}OK${gl_bai}] 8/12. 设置时区到${gl_huang}上海${gl_bai}"

            echo "------------------------------------------------"
            auto_optimize_dns
            echo -e "[${gl_lv}OK${gl_bai}] 9/12. 自动优化DNS地址"

            echo "------------------------------------------------"
            prefer_ipv4
            echo -e "[${gl_lv}OK${gl_bai}] 10/12. 设置网络为${gl_huang}ipv4优先${gl_bai}"

            echo "------------------------------------------------"
            install_docker
            install wget sudo tar unzip socat btop nano vim
            echo -e "[${gl_lv}OK${gl_bai}] 11/12. 安装基础工具"

            echo "------------------------------------------------"
            optimize_balanced
            echo -e "[${gl_lv}OK${gl_bai}] 12/12. Linux系统内核参数优化"
            echo -e "${gl_lv}一条龙系统调优已全部完成！${gl_bai}"

            ;;
        [Nn])
            echo "已取消"
            ;;
        *)
            echo "无效的选择，请输入 Y 或 N。"
            ;;
    esac
}


# =================================================================
# 菜单功能函数
# =================================================================
