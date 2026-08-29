#!/usr/bin/env bash
# =============================================
# Ever 家园 - APK 打包脚本
# 用法: ./build.sh [版本号] [更新说明]
#   例: ./build.sh "新增记忆库模块"
#   例: ./build.sh 1.1.0 "全新UI"
# =============================================

set -e

# ---- 可配置项 ----
VPS_USER="ubuntu"
VPS_HOST="150.109.243.11"
VPS_PATH="/home/ubuntu/ever-agent/publish"
APK_OUT="build/app/outputs/flutter-apk/app-release.apk"

# ---- 颜色 ----
G='\033[0;32m'; Y='\033[1;33m'; N='\033[0m'

echo -e "${Y}=== Ever APK 打包 ===${N}"

# 1. 读取当前版本
CUR_VER=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//; s/ *//g')
CUR_VER_NUM=$(echo "$CUR_VER" | cut -d+ -f1)
CUR_BUILD=$(echo "$CUR_VER" | cut -d+ -f2)
echo -e "当前版本: ${G}${CUR_VER_NUM}+${CUR_BUILD}${N}"

# 2. 确定新版本
if [[ -n "$1" && "$1" == *.* ]]; then
  NEW_VER_NUM="$1"
else
  NEW_VER_NUM="$CUR_VER_NUM"
fi
NEW_BUILD=$((CUR_BUILD + 1))
NEW_VER="${NEW_VER_NUM}+${NEW_BUILD}"
echo -e "新版本: ${G}${NEW_VER}${N}"

# 3. 编译
if ! command -v flutter >/dev/null 2>&1; then
  if [ -d "$HOME/flutter/bin" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
    export FLUTTER_ROOT="$HOME/flutter"
  elif [ -d "/usr/lib/flutter/bin" ]; then
    export PATH="/usr/lib/flutter/bin:$PATH"
    export FLUTTER_ROOT="/usr/lib/flutter"
  else
    echo -e "${Y}未找到 flutter，请先安装 Flutter 环境${N}"
    exit 1
  fi
fi

echo -e "${Y}编译中... 可能需要几分钟${N}"
flutter build apk --release

# APK 输出路径兜底查找（不同版本可能在不同位置）
if [ ! -f "$APK_OUT" ]; then
  APK_OUT=$(find build -name "app-release.apk" 2>/dev/null | head -1)
  if [ -z "$APK_OUT" ]; then
    echo -e "${Y}编译失败，未找到 APK: $APK_OUT${N}"
    exit 1
  fi
  echo -e "APK 实际位置: ${G}$APK_OUT${N}"
fi

# 4. 更新 pubspec.yaml 版本号
sed -i.bak "s/^version: .*/version: ${NEW_VER}/" pubspec.yaml
rm -f pubspec.yaml.bak

# 5. 生成 version.json
NOTES="${2:-自动更新}"
cat > version.json <<EOF
{"version":"${NEW_VER_NUM}","build":${NEW_BUILD},"notes":"${NOTES}","url":"https://ever.phywn.top/latest.apk"}
EOF
echo -e "生成 version.json: ${G}$(cat version.json)${N}"

echo -e "${Y}=== 上传到 VPS ===${N}"
echo -e "将上传到 $VPS_USER@$VPS_HOST:$VPS_PATH"

# 检查是否已配置免密 SSH（key），否则提示用户准备输密码
if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$VPS_USER@$VPS_HOST" 'echo ok' >/dev/null 2>&1; then
  echo -e "\n${Y}[提示] 未检测到免密 SSH key，接下来上传时会要求输入 VPS 密码（$VPS_USER@$VPS_HOST）${N}"
  echo -e "${Y}       如需免密，可先在本地: ssh-keygen -t rsa 再: ssh-copy-id $VPS_USER@$VPS_HOST${N}\n"
fi

scp "$APK_OUT" "$VPS_USER@$VPS_HOST:$VPS_PATH/latest.apk"
scp version.json "$VPS_USER@$VPS_HOST:$VPS_PATH/version.json"

echo -e "${G}=== 完成！App 内检查更新即可拉到新版本 ${NEW_VER} ===${N}"
echo -e "本地 APK 位置: $APK_OUT"