#!/bin/bash
# 把 autodig-mod/src/ 打包成 Factorio 可安裝的 zip。
#
# Factorio 要求 zip 內最外層只有一個資料夾,名稱必須是 <name>_<version>,
# 且該資料夾內直接放 info.json。這裡從 info.json 讀 name/version,避免手動同步出錯。
#
#   ./package.sh              -> 產出 dist/<name>_<version>.zip
#   ./package.sh --install    -> 打包後直接裝進 ../_data/mods/(chown 845,需重啟伺服器)
#
# 打包前一定會跑單元測試和載入測試,失敗就整個中止 —— 這兩道是「不能跳過」的,
# 不是「方便的話跑一下」。
set -euo pipefail
cd "$(dirname "$0")"

NAME=$(jq -r '.name' src/info.json)
VERSION=$(jq -r '.version' src/info.json)
DIR="${NAME}_${VERSION}"
OUT="dist/${DIR}.zip"

echo "==> 單元測試"
./test/run.sh

echo "==> 組裝 $DIR"
rm -rf build dist
mkdir -p "build/$DIR" dist
# 白名單複製,不用 cp -r。locale-mod 有過把工具的暫存目錄掃進 zip 差點發布出去
# 的紀錄,所以這裡明確列出要帶什麼。
cp src/info.json src/data.lua src/settings.lua src/control.lua src/logic.lua src/gui.lua "build/$DIR/"
# LICENSE 在 repo 根目錄,不在 src/ 底下,所以另外一行複製 —— publish.sh 送出的
# license 欄位(default_gnulgplv3)只登記在 portal 頁面上,實際授權條文要跟著
# 這個 zip 一起發布,不能只存在於 repo 裡沒人下載模組時看不到的地方。
cp LICENSE "build/$DIR/"
mkdir -p "build/$DIR/locale/en" "build/$DIR/locale/zh-TW"
cp src/locale/en/*.cfg "build/$DIR/locale/en/"
cp src/locale/zh-TW/*.cfg "build/$DIR/locale/zh-TW/"

( cd build && zip -qr "../$OUT" "$DIR" )
echo "==> 產出 $OUT"

echo "==> 載入測試(headless 建一張新地圖,確認原型與依賴沒問題)"
# 注意:這只證明 data 階段和依賴解析沒問題,證明不了任何 runtime 行為 ——
# 無頭伺服器沒有角色,自動挖掘的行為只能靠實機驗證。
LOADTEST=$(mktemp -d)
# set -e 會在 docker run 失敗的當下就中止腳本,所以清理必須掛在 EXIT 上。
# 寫在 if 分支裡的 rm 在「真的失敗」時永遠跑不到 —— 那正是最需要清理的時候。
trap 'rm -rf "$LOADTEST"' EXIT
cp "$OUT" "$LOADTEST/"
for m in ../_data/mods/the-cave_*.zip; do cp "$m" "$LOADTEST/"; done
# --entrypoint 覆蓋掉映像檔預設的 /docker-entrypoint.sh。那支腳本不是「你的指令
# 取代它」,而是把我們的命令原封不動接在它自己啟動的伺服器程序後面當額外參數,
# 而且它會先用 uid 845 (factorio 使用者) chown 整個掛載目錄再開始 ——
# 於是 /mods/mod-list.json 的擁有者跟 host 掛進來的目錄對不上,直接
# Permission denied。直接指到二進位檔可以跳過那整套設置,乾淨地跑一次性的
# --create。
if ! docker run --rm --entrypoint /opt/factorio/bin/x64/factorio \
    -v "$LOADTEST:/mods" factoriotools/factorio:2.0.77 \
    --mod-directory /mods --create /tmp/loadtest.zip 2>&1 | tee "$LOADTEST/out.log"; then
    echo "!! 載入測試失敗:factorio 以非零狀態結束,看上面的輸出"
    exit 1
fi
if grep -qiE "error|failed to load" "$LOADTEST/out.log"; then
    echo "!! 載入測試失敗:輸出裡有錯誤訊息,看上面"
    exit 1
fi
echo "==> 載入測試通過"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> 安裝到 ../_data/mods/"
    docker run --rm --user 0:0 -v "$PWD/dist:/dist" -v "$PWD/../_data/mods:/mods" \
        alpine sh -c "cp /dist/${DIR}.zip /mods/ && chown 845:845 /mods/${DIR}.zip"
    echo "   裝好了,需要 ./restart.sh 才會生效"
fi
