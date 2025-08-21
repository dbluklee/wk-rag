#!/bin/bash

echo "🚀 RAG 서버 시작"

# 필수 환경변수 체크
if [ -z "$LLM_SERVER_URL" ] || [ -z "$MILVUS_SERVER_URL" ]; then
    echo "❌ 필수 환경변수 누락: LLM_SERVER_URL, MILVUS_SERVER_URL"
    exit 1
fi

echo "환경설정:"
echo "- LLM: $LLM_SERVER_URL"
echo "- Milvus: $MILVUS_SERVER_URL"

# Milvus 연결 체크 (필수)
echo "⏳ Milvus 연결 확인..."
for i in {1..10}; do
    if curl -s --connect-timeout 3 "http://$MILVUS_SERVER_IP:$MILVUS_MONITOR_PORT/healthz" >/dev/null 2>&1; then
        echo "✅ Milvus 연결 성공"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "❌ Milvus 연결 실패"
        exit 1
    fi
    echo "재시도 중... ($i/10)"
    sleep 5
done

# LLM 연결 체크 (필수)
echo "⏳ LLM 연결 확인..."
for i in {1..10}; do
    if curl -s --connect-timeout 3 "$LLM_SERVER_URL/api/tags" >/dev/null 2>&1; then
        echo "✅ LLM 연결 성공"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "❌ LLM 연결 실패"
        exit 1
    fi
    echo "재시도 중... ($i/10)"
    sleep 5
done


# 서버 시작
echo ""
echo "🚀 FastAPI 서버 시작..."
echo "접속: http://0.0.0.0:8000"
echo ""

exec uvicorn server:app \
    --host 0.0.0.0 \
    --port 8000 \
    --log-level info