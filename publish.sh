#!/bin/bash
# 把 hanshino-cave-autodig 發佈到 Factorio Mod Portal。
#
# 這個腳本「預設什麼都不做」——沒有加 --yes 就只印出即將執行的動作。
# 發佈是公開且幾乎不可逆的動作（模組名稱一旦佔用就無法更名），所以請確認後再加 --yes。
#
# 用法：
#   ./publish.sh --init            # 預覽「首次發佈」會做什麼
#   ./publish.sh --init --yes      # 真的首次發佈（只會成功一次）
#   ./publish.sh --release --yes    # 上傳新版本（info.json 的 version 要先遞增）
#   ./publish.sh --details --yes    # 只更新 Portal 上的標題／簡介／說明／標籤
#
# API key 取得：https://factorio.com/profile → 建立 API key，勾選需要的 usage：
#   --init     需要  ModPortal: Publish Mods
#   --release  需要  ModPortal: Upload Mods
#   --details  需要  ModPortal: Edit Mods
# 三個可以是同一把 key（勾三個 usage），也可以分開。
#
# key 從環境變數讀，不要寫進檔案也不要貼到聊天室：
#   export FACTORIO_MOD_API_KEY=...
# 或放進專案根目錄的 .env（chmod 600）再 source：
#   set -a; source ../.env; set +a
set -euo pipefail
cd "$(dirname "$0")"

MODE=""
CONFIRM=0
for a in "$@"; do
  case "$a" in
    --init)    MODE=init ;;
    --release) MODE=release ;;
    --details) MODE=details ;;
    --yes)     CONFIRM=1 ;;
    *) echo "未知參數: $a"; exit 2 ;;
  esac
done
[ -z "$MODE" ] && { echo "要指定 --init / --release / --details 其中一個"; exit 2; }

NAME=$(jq -r '.name' src/info.json)
VERSION=$(jq -r '.version' src/info.json)
TITLE=$(jq -r '.title' src/info.json)
ZIP="dist/${NAME}_${VERSION}.zip"

# Portal 上的中介資料。改這裡，不要改 src/info.json（那份是遊戲讀的）。
#
# 分類注意：Mod Portal 的合法 category 只有這幾種（見 wiki.factorio.com/Mod_details_API）：
# no-category / content / overhaul / tweaks / utilities / scenarios / mod-packs /
# localizations / internal —— 沒有 "helper-mods" 這個值。這個 mod 是「不改變玩法、
# 只是把手動操作自動化」的工具，對應到官方定義最接近的是 utilities
# （"Providing the player with new tools or adjusting the game interface, without
# fundamentally changing gameplay."）。"helper-mods" 這種望文生義的名稱不是 portal
# 承認的分類，填了會被 API 拒絕 —— 送出前請再次確認這裡是 utilities。
CATEGORY="utilities"
LICENSE="default_gnulgplv3"       # 與 locale-mod 一致；條文見 repo 根目錄的 LICENSE
                                  # 檔（package.sh 會把它一起打包進 zip）
SOURCE_URL=""                     # 有 git repo 再填
SUMMARY="Removes the repetitive clicking of manual digging in The Cave, without speeding anything up: mining speed, reach, and every dig's consequences are exactly the same as clicking it yourself."
DESCRIPTION_FILE="portal-description.md"

echo "模組名稱 : $NAME        （發佈後無法更名）"
echo "顯示標題 : $TITLE"
echo "版本     : $VERSION"
echo "zip      : $ZIP"
echo "分類     : $CATEGORY"
echo "授權     : $LICENSE"
echo "動作     : $MODE"
echo

if [ "$MODE" != "details" ]; then
  [ -f "$ZIP" ] || { echo "找不到 $ZIP —— 先跑 ./package.sh"; exit 1; }
  # zip 內最外層資料夾必須正好等於 <name>_<version>
  # 用 awk 而非 head：head 會提早關閉管線讓 unzip 收到 SIGPIPE，在 pipefail 下會誤判失敗
  TOP=$(unzip -Z1 "$ZIP" | awk -F/ 'NR==1{print $1}')
  [ "$TOP" = "${NAME}_${VERSION}" ] || { echo "zip 最外層是 '$TOP'，應為 '${NAME}_${VERSION}'"; exit 1; }
  echo "zip 結構檢查通過（最外層資料夾 = $TOP）"

  # 上面只驗證了資料夾名稱，沒驗證裡面的內容真的是「現在的」src/ —— 一份用
  # 舊版 src 打包出來、檔名和版本號卻恰好沒變的 zip 不會被上面那個檢查攔下來，
  # 而發布一份跟目前 src/ 不一致的舊 build，正是這個 mod 剛花一整波修過的
  # 「文案跟現實不符」問題的另一種樣子：發布的不是剛剛看過、審過的東西。
  # 把 zip 展開後跟 src/ 逐檔比對內容，發現任何差異就中止，請人重新跑
  # ./package.sh 再重新上傳 —— 不要自己猜測或略過差異。
  DIFFDIR=$(mktemp -d)
  trap 'rm -rf "$DIFFDIR"' EXIT
  unzip -q "$ZIP" -d "$DIFFDIR"
  if ! diff -rq "$DIFFDIR/$TOP" src; then
    echo "!! zip 內容跟目前的 src/ 不一致（差異見上面）—— 請重新執行 ./package.sh 再重新上傳"
    exit 1
  fi
  echo "zip 內容檢查通過（與 src/ 完全一致）"
fi

if [ "$CONFIRM" != "1" ]; then
  echo
  echo "── 這是預覽，沒有送出任何請求。確認以上資訊無誤後加上 --yes 再執行。──"
  exit 0
fi

# API key 優先用環境變數；沒有的話自動讀專案根目錄的 .env（不印出內容）
if [ -z "${FACTORIO_MOD_API_KEY:-}" ] && [ -f ../.env ]; then
  set -a; . ../.env; set +a
  [ -n "${FACTORIO_MOD_API_KEY:-}" ] && echo "已從 ../.env 讀到 API key"
fi
if [ -z "${FACTORIO_MOD_API_KEY:-}" ]; then
  echo "找不到 API key。二選一："
  echo "  1. 在專案根目錄的 .env 填 FACTORIO_MOD_API_KEY=（範本見 .env.example）"
  echo "  2. export FACTORIO_MOD_API_KEY=..."
  exit 1
fi
AUTH="Authorization: Bearer $FACTORIO_MOD_API_KEY"
API=https://mods.factorio.com/api/v2/mods

# 從回應中取欄位；同時把錯誤訊息印出來（不會印到 key）
jqf () { python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get(sys.argv[1],''))" "$1"; }

case "$MODE" in
  init|release)
    if [ "$MODE" = init ]; then
      INIT_URL="$API/init_publish"
    else
      INIT_URL="$API/releases/init_upload"
    fi
    echo "1/2 呼叫 $INIT_URL ..."
    RESP=$(curl -sS -X POST -H "$AUTH" -F "mod=$NAME" "$INIT_URL")
    UPLOAD_URL=$(printf '%s' "$RESP" | jqf upload_url)
    if [ -z "$UPLOAD_URL" ]; then
      echo "失敗：$RESP"
      echo
      echo "常見原因：ModAlreadyExists（名稱已被佔用）／Forbidden（API key 沒勾對應 usage）"
      echo "         InvalidModRelease（info.json 有問題）／InvalidApiKey"
      exit 1
    fi
    echo "    取得上傳網址"

    echo "2/2 上傳 $ZIP ..."
    ARGS=(-F "file=@$ZIP")
    if [ "$MODE" = init ]; then
      # 只有首次發佈可以在這一步帶入 description / category / license / source_url
      [ -f "$DESCRIPTION_FILE" ] && ARGS+=(-F "description=<$DESCRIPTION_FILE")
      ARGS+=(-F "category=$CATEGORY" -F "license=$LICENSE")
      [ -n "$SOURCE_URL" ] && ARGS+=(-F "source_url=$SOURCE_URL")
    fi
    RESP=$(curl -sS -X POST "${ARGS[@]}" "$UPLOAD_URL")
    if [ "$(printf '%s' "$RESP" | jqf success)" = "True" ]; then
      echo "完成：https://mods.factorio.com/mod/$NAME"
    else
      echo "失敗：$RESP"; exit 1
    fi
    ;;

  details)
    echo "呼叫 $API/edit_details ..."
    # 不要送空的 tags —— API 會回 InvalidRequest / "Tag does not exist."
    # 真要設 tag 就填實際值，例如 TAGS=("logistics" "utilities")
    ARGS=(-F "mod=$NAME" -F "title=$TITLE" -F "summary=$SUMMARY"
          -F "category=$CATEGORY" -F "license=$LICENSE")
    for t in "${TAGS[@]:-}"; do
      [ -n "$t" ] && ARGS+=(-F "tags=$t")
    done
    [ -f "$DESCRIPTION_FILE" ] && ARGS+=(-F "description=<$DESCRIPTION_FILE")
    [ -n "$SOURCE_URL" ] && ARGS+=(-F "source_url=$SOURCE_URL")
    RESP=$(curl -sS -X POST -H "$AUTH" "${ARGS[@]}" "$API/edit_details")
    if [ "$(printf '%s' "$RESP" | jqf success)" = "True" ]; then
      echo "完成：https://mods.factorio.com/mod/$NAME"
    else
      echo "失敗：$RESP"; exit 1
    fi
    ;;
esac
