#!/usr/bin/env bash
#
# 把构建好的 IPA 发布到镜像仓库 Release（附件形式），方便国内下载。
#
# 依赖环境变量：
#   MIRROR_TOKEN   镜像仓库私人令牌，需要 projects 权限
#   MIRROR_OWNER   仓库拥有者（用户名或组织名）
#   MIRROR_REPO    仓库名
#   VERSION       版本号，例如 1.0.0
#
# 可选：
#   IPA_PATH      默认 dist/QingLong-<VERSION>.ipa
#   MIRROR_API     默认 https://镜像仓库.com/api/v5
#
set -euo pipefail

MIRROR_API="${MIRROR_API:-https://镜像仓库.com/api/v5}"
IPA_PATH="${IPA_PATH:-dist/QingLong-${VERSION}.ipa}"
TAG="v${VERSION}"

if [ ! -f "$IPA_PATH" ]; then
  echo "::error::IPA not found: $IPA_PATH"
  ls -R dist || true
  exit 1
fi

echo "==> 镜像仓库: ${MIRROR_OWNER}/${MIRROR_REPO}  tag=${TAG}  file=${IPA_PATH}"

# 1. 查询该 tag 是否已有 release
EXISTING_ID=$(curl -sS -X GET \
  "${MIRROR_API}/repos/${MIRROR_OWNER}/${MIRROR_REPO}/releases/tags/${TAG}" \
  -H "Content-Type: application/json" \
  | python3 -c "import sys,json;
try:
    d=json.load(sys.stdin); print(d.get('id') or '')
except Exception:
    print('')" || true)

if [ -z "$EXISTING_ID" ]; then
  echo "==> 创建镜像仓库 Release"
  EXISTING_ID=$(curl -sS -X POST \
    "${MIRROR_API}/repos/${MIRROR_OWNER}/${MIRROR_REPO}/releases" \
    -H "Content-Type: application/json" \
    -d "$(python3 - <<PY
import json
print(json.dumps({
  "access_token": "${MIRROR_TOKEN}",
  "tag_name": "${TAG}",
  "name": "青龙助手 iOS ${VERSION}",
  "body": "未签名 IPA，适用于 TrollStore / 巨魔环境。\n\n1. 下载附件中的 ipa\n2. 用 TrollStore 打开并安装\n3. 启动后填写青龙面板地址并登录",
  "target_commitish": "main",
  "prerelease": False,
  "release_type": 1
}, ensure_ascii=False))
PY
)" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
else
  echo "==> 复用已存在的镜像仓库 Release (id=${EXISTING_ID})"
fi

if [ -z "$EXISTING_ID" ]; then
  echo "::error::无法创建或获取镜像仓库 Release"
  exit 1
fi

# 2. 上传附件
echo "==> 上传附件"
RESP=$(curl -sS -X POST \
  "${MIRROR_API}/repos/${MIRROR_OWNER}/${MIRROR_REPO}/releases/${EXISTING_ID}/attach_files" \
  -F "access_token=${MIRROR_TOKEN}" \
  -F "file=@${IPA_PATH}")

echo "$RESP" | head -c 800
echo

if echo "$RESP" | grep -q '"browser_download_url"'; then
  URL=$(echo "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('browser_download_url',''))")
  echo "==> 上传成功：${URL}"
else
  echo "::warning::附件上传返回异常，请到镜像仓库 Release 页面确认。"
fi
