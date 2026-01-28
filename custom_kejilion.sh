# custom_kejilion.sh

kejilion_sh() {
while true; do
clear
echo -e "${gl_kjlan}"
echo "╦╔═╔═╗ ╦╦╦  ╦╔═╗╔╗╔ ╔═╗╦ ╦"
echo "╠╩╗║╣  ║║║  ║║ ║║║║ ╚═╗╠═╣"
echo "╩ ╩╚═╝╚╝╩╩═╝╩╚═╝╝╚╝o╚═╝╩ ╩"
echo -e "科技X一键科学脚本工具 v$sh_v"
echo -e "命令行输入${gl_huang}k${gl_kjlan}可快速启动脚本${gl_bai}"
echo -e "${gl_kjlan}------------------------------------------------------------------------${gl_bai}"
echo -e "${gl_kjlan}1.   ${gl_bai}系统信息查询		${gl_kjlan}7.   ${gl_bai}WARP管理"
echo -e "${gl_kjlan}2.   ${gl_bai}系统更新			${gl_kjlan}8.   ${gl_bai}测试脚本合集"
echo -e "${gl_kjlan}3.   ${gl_bai}系统清理			${gl_kjlan}9.   ${gl_bai}甲骨文云脚本合集"
echo -e "${gl_kjlan}4.   ${gl_bai}基础工具			${gl_huang}10.  ${gl_bai}LDNMP建站"
echo -e "${gl_kjlan}5.   ${gl_bai}BBR管理			${gl_kjlan}11.  ${gl_bai}应用市场"
echo -e "${gl_kjlan}6.   ${gl_bai}Docker管理			${gl_kjlan}13.  ${gl_bai}系统工具"
echo -e "${gl_kjlan}------------------------------------------------------------------------${gl_bai}"
echo -e "${gl_kjlan}21.   ${gl_bai}安装Nginx容器		${gl_kjlan}31.	${gl_bai}ROOT私钥登录模式"
echo -e "${gl_kjlan}22.   ${gl_bai}安装3X-UI容器		${gl_kjlan}66.  ${gl_bai}一条龙调优"
echo -e "${gl_kjlan}23.   ${gl_bai}安装x-ui-yg容器	${gl_kjlan}77.  ${gl_bai}安装快捷键k"
echo -e "${gl_kjlan}24.   ${gl_bai}申请SSL证书"
echo -e "${gl_kjlan}25.   ${gl_bai}查看容器状态"
echo -e "${gl_kjlan}------------------------------------------------------------------------${gl_bai}"
echo -e "${gl_kjlan}00.   ${gl_bai}脚本更新			${gl_kjlan}0.  ${gl_bai}退出脚本"
echo -e "${gl_kjlan}------------------------------------------------------------------------${gl_bai}"
read -e -p "请输入你的选择: " choice

case $choice in
  1) linux_info ;;
  2) clear ; send_stats "系统更新" ; linux_update ;;
  3) clear ; send_stats "系统清理" ; linux_clean ;;
  4) linux_tools ;;
  5) linux_bbr ;;
  6) linux_docker ;;
  7) clear ; send_stats "warp管理" ; install wget
	wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh ; bash menu.sh [option] [lisence/url/token]
	;;
  8) linux_test ;;
  9) linux_Oracle ;;
  10) linux_ldnmp ;;
  11) linux_panel ;;
  13) linux_Settings ;;
  # 自定义功能
  21) clear ; ldnmp_install_status_one ; nginx_install_all ;;
  22) x_install_3x_ui ;;
  23) x_install_x-ui-yg ;;
  24) x_apply_ssl ;;
  25) x_view_status ;;
  31) sshkey_panel ;;
  66) x_all_in_one ;;
  77) x_install_command ;;
  00) x_kejilion_update ;;
  0) clear ; exit ;;
  *) echo "无效的输入!" ;;
esac
	break_end
done
}
