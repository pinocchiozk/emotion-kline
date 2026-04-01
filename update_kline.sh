#!/bin/bash

# 情绪 K 线实时追加脚本（交易时段每 5 分钟）
# 功能：更新"今日 K 线"，让它像真 K 线一样生长

set -e

CSV_FILE="/tmp/kaipanla/sentiment_data.csv"
JSON_FILE="/Users/macclaw/.openclaw/workspace/emotion-kline/emotion-data.json"
LOG_FILE="/tmp/kaipanla/kline_realtime.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查是否是交易日（周一至周五）
DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" -gt 5 ]; then
    log "周末，跳过"
    exit 0
fi

# 检查是否在交易时段（9:15-11:30, 13:00-15:00）
CURRENT_HOUR=$(date +%-H)
CURRENT_MIN=$(date +%-M)
CURRENT_TIME=$((CURRENT_HOUR * 60 + CURRENT_MIN))

OPEN_TIME=$((9 * 60 + 15))      # 9:15
MORNING_CLOSE=$((11 * 60 + 30))  # 11:30
AFTERNOON_OPEN=$((13 * 60 + 0))  # 13:00
CLOSE_TIME=$((15 * 60 + 0))      # 15:00

if [ "$CURRENT_TIME" -lt "$OPEN_TIME" ] || \
   ([ "$CURRENT_TIME" -gt "$MORNING_CLOSE" ] && [ "$CURRENT_TIME" -lt "$AFTERNOON_OPEN" ]) || \
   [ "$CURRENT_TIME" -gt "$CLOSE_TIME" ]; then
    log "非交易时段（${CURRENT_HOUR}:${CURRENT_MIN}），跳过"
    exit 0
fi

log "=== 交易时段，开始更新 ==="

# 获取最新数据
LATEST_LINE=$(tail -1 "$CSV_FILE")
if [ -z "$LATEST_LINE" ]; then
    log "❌ CSV 文件为空"
    exit 1
fi

# 解析数据
DATE=$(echo "$LATEST_LINE" | cut -d',' -f1)
TIME=$(echo "$LATEST_LINE" | cut -d',' -f2)
SCORE=$(echo "$LATEST_LINE" | cut -d',' -f3)

log "📊 最新数据：$DATE $TIME | 情绪：$SCORE 分"

# 更新或创建今日 K 线
python3 << PYEOF
import json
from datetime import datetime

# 读取现有数据
with open('$JSON_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 生成标签（去除前导零）
dt = datetime.strptime('$DATE', '%Y-%m-%d')
label = f"{dt.month}月{dt.day}日"

# 检查今天的数据是否已存在
today_index = None
for i, day in enumerate(data['days']):
    if day['date'] == '$DATE':
        today_index = i
        break

if today_index is not None:
    # 更新今日 K 线（盘中生长）
    today = data['days'][today_index]
    today['close'] = $SCORE  # 更新收盘
    if today['high'] == 0 or $SCORE > today['high']:
        today['high'] = $SCORE  # 更新最高
    if today['low'] == 0 or $SCORE < today['low']:
        today['low'] = $SCORE  # 更新最低
    print(f"✅ 更新今日 K 线：O:{today['open']} C:{today['close']} H:{today['high']} L:{today['low']}")
else:
    # 创建新 K 线（首次）
    new_day = {
        "date": "$DATE",
        "label": "$label",
        "open": $SCORE,
        "close": $SCORE,
        "high": $SCORE,
        "low": $SCORE
    }
    data['days'].append(new_day)
    print(f"✅ 创建新 K 线：$DATE 开盘$SCORE 分")

# 写回文件
with open('$JSON_FILE', 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF

if [ $? -eq 0 ]; then
    log "✅ 数据更新成功"
    
    # 推送到 GitHub
    log "🚀 推送到 GitHub..."
    cd /Users/macclaw/.openclaw/workspace/emotion-kline
    git add emotion-data.json
    git commit -m "实时更新：$DATE $TIME 情绪$SCORE 分" 2>/dev/null || {
        log "⚠️ 没有新更改或提交失败"
    }
    git push origin main 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log "✅ GitHub 推送成功"
    else
        log "❌ GitHub 推送失败"
    fi
else
    log "❌ 数据更新失败"
    exit 1
fi

log "=== 更新完成 ==="
