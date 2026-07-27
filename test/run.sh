#!/bin/bash
# 用 Docker 跑 logic.lua 的單元測試,不在主機裝 Lua 直譯器。
#
# 一定要用 Lua 5.2 —— Factorio 2.0 內建的就是 5.2.1。用 5.4 測會放過 `//`
# 整數除法、位元運算子這些 5.2 沒有的語法,那些要進遊戲才會炸。
set -euo pipefail
cd "$(dirname "$0")/.."
exec docker run --rm -v "$PWD:/w" -w /w nickblah/lua:5.2 lua test/test_logic.lua
