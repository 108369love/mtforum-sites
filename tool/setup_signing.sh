#!/usr/bin/env bash
# 把你的发布签名写进 GitHub 仓库 Secret，让 CI 打出的 APK 能覆盖安装。
#
# fork 出来的仓库不继承原仓库的 Secret，所以别人复刻之后默认走的是仓库内缓存
# 的备用签名。如果你想让自己的构建有一张专属证书，跑一次这个脚本即可。
#
#   tool/setup_signing.sh                    # 自动识别当前仓库
#   tool/setup_signing.sh owner/repo         # 指定仓库
#   KEYSTORE=my.jks tool/setup_signing.sh    # 指定已有密钥
#
# 依赖：gh（已登录，且有仓库 admin 权限）、keytool（JDK 自带）。
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
KS="${KEYSTORE:-release.jks}"
ALIAS="${KEY_ALIAS:-mtforum}"

if [ -n "${KEYSTORE_PASSWORD:-}" ]; then
  PASS="$KEYSTORE_PASSWORD"
elif [ -f "$KS" ]; then
  echo "已存在 $KS，但没有设置 KEYSTORE_PASSWORD，无法读取密码。" >&2
  echo "请用：KEYSTORE_PASSWORD=你的密码 tool/setup_signing.sh $REPO" >&2
  exit 1
else
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  echo "生成新密钥：$KS（别名 $ALIAS）"
  keytool -genkeypair -keystore "$KS" -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=MT Forum Self Build, O=Local, C=CN"
fi

echo "上传 Secret 到 $REPO ..."
base64 -w0 "$KS" > "$KS.b64"
gh secret set ANDROID_KEYSTORE_BASE64 -R "$REPO" < "$KS.b64"
printf '%s' "$PASS"  | gh secret set ANDROID_KEYSTORE_PASSWORD -R "$REPO"
printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS       -R "$REPO"
printf '%s' "$PASS"  | gh secret set ANDROID_KEY_PASSWORD    -R "$REPO"
rm -f "$KS.b64"

printf '\n密码：%s\n别名：%s\n密钥：%s\n' "$PASS" "$ALIAS" "$KS"
echo "请把密码和 $KS 备份好 —— 丢了就没法再发同签名的更新。"
echo
echo "证书指纹："
keytool -list -v -keystore "$KS" -storepass "$PASS" -alias "$ALIAS" | grep "SHA256:"
