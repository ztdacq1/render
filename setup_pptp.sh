#!/bin/bash

# 检查是否是root
if [ "$EUID" -ne 0 ]; then
  echo "请用root权限运行！"
  exit 1
fi

# 检查系统
if [ -f /etc/centos-release ]; then
    OS_VERSION=$(cat /etc/centos-release | grep -oP '[0-9]+' | head -1)
    if [ "$OS_VERSION" != "7" ]; then
        echo "此脚本仅适用于 CentOS 7"
        exit 1
    fi
else
    echo "不支持的系统。"
    exit 1
fi

# 安装必要的软件包
yum install -y epel-release
yum install -y ppp pptpd iptables-services curl net-tools

# 配置pptpd
cat > /etc/pptpd.conf <<EOF
option /etc/ppp/options.pptpd
logwtmp
localip 192.168.0.1
remoteip 192.168.0.100-200
EOF

# 配置PPP选项
cat > /etc/ppp/options.pptpd <<EOF
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 114.114.114.114
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

# 生成或输入用户名密码
VPN_USER="vpnuser"
VPN_PASS=$(openssl rand -base64 8)

read -p "请输入VPN账号（默认: $VPN_USER）:" input_user
if [ ! -z "$input_user" ]; then
    VPN_USER=$input_user
fi

read -p "请输入VPN密码（默认随机生成）:" input_pass
if [ ! -z "$input_pass" ]; then
    VPN_PASS=$input_pass
fi

# 写入chap-secrets
echo "${VPN_USER} pptpd ${VPN_PASS} *" >> /etc/ppp/chap-secrets

# 开启内核转发
sed -i '/^net.ipv4.ip_forward/s/0/1/' /etc/sysctl.conf
sysctl -p

# 配置防火墙
firewall-cmd --permanent --add-port=1723/tcp
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p gre -j ACCEPT
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -p gre -j ACCEPT
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

# 设置iptables NAT转发
EXTERNAL_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
iptables -t nat -A POSTROUTING -o $EXTERNAL_IFACE -j MASQUERADE
service iptables save

# 启动并设置开机自启
systemctl enable pptpd
systemctl restart pptpd

# 获取公网IP
PUBLIC_IP=$(curl -s ifconfig.me)

# 完成提示
clear
echo "=================================="
echo " PPTP VPN 安装完成！"
echo "=================================="
echo "服务器IP: $PUBLIC_IP"
echo "VPN账号 : $VPN_USER"
echo "VPN密码 : $VPN_PASS"
echo "=================================="
echo "请确保安全组已放通：TCP 1723 和 GRE协议"
echo "祝使用愉快！"

exit 0
