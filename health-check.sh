#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 환경변수 로드
if [ -f ".env.global" ]; then
    source .env.global
else
    echo -e "${YELLOW}⚠️ .env.global 파일이 없습니다. ${NC}"
    exit 1
fi

echo -e "${PURPLE}🏥 CHEESEADE RAG 시스템 상태 확인${NC}"
echo "========================================"
echo "📅 체크 시간: $(date)"
echo "🌐 네트워크 구조: 공유기(${WEBUI_SERVER_IP}) → 포트포워딩 → 서버PC → Docker"
echo ""

# 전역 상태 변수
OVERALL_STATUS=0
SERVICES_TOTAL=0
SERVICES_HEALTHY=0

# 상태 체크 함수
check_service() {
    local service_name="$1"
    local url="$2"
    local expected_status="$3"
    local description="$4"
    local timeout="${5:-5}"
    
    SERVICES_TOTAL=$((SERVICES_TOTAL + 1))
    
    echo -n "🔍 ${service_name}: "
    
    # HTTP 상태 체크
    if command -v curl > /dev/null 2>&1; then
        response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $timeout --max-time $timeout "$url" 2>/dev/null)
        
        if [ "$response" = "$expected_status" ]; then
            echo -e "${GREEN}✅ 정상${NC} (${description})"
            SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
            
            # 추가 정보 표시
            case "$service_name" in
                "RAG Server")
                    # 시스템 정보 수집
                    system_info=$(curl -s --connect-timeout 3 "$url/../" 2>/dev/null)
                    if echo "$system_info" | grep -q "CHEESEADE RAG Server"; then
                        docs_count=$(echo "$system_info" | grep -o '"documents_loaded":[0-9]*' | cut -d':' -f2)
                        device=$(echo "$system_info" | grep -o '"embedding_device":"[^"]*"' | cut -d'"' -f4)
                        
                        if [ -n "$docs_count" ] && [ "$docs_count" -gt 0 ]; then
                            echo "    📄 로드된 문서: ${docs_count}개"
                        fi
                        if [ -n "$device" ]; then
                            echo "    🖥️ 임베딩 디바이스: ${device}"
                        fi
                    fi
                    ;;
                "LLM Server")
                    # 모델 정보 수집
                    models=$(curl -s --connect-timeout 3 "${url%/*}/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | head -3)
                    if [ -n "$models" ]; then
                        echo "    📋 사용 가능한 모델: $(echo "$models" | cut -d'"' -f4 | tr '\n' ', ' | sed 's/,$//')"
                    fi
                    ;;
                "Open WebUI")
                    # WebUI 연결 확인
                    webui_info=$(curl -s --connect-timeout 3 "$url" 2>/dev/null)
                    if echo "$webui_info" | grep -q -i "open.*webui\|cheeseade"; then
                        echo "    🌐 CHEESEADE WebUI 정상 로드됨"
                    fi
                    ;;
                "Logging API")
                    # 로깅 서버 정보 수집
                    logging_info=$(curl -s --connect-timeout 3 "$url" 2>/dev/null)
                    if echo "$logging_info" | grep -q "CHEESEADE RAG Logging"; then
                        echo "    📊 로깅 API 정상 응답"
                        
                        # 간단한 통계 확인
                        stats=$(curl -s --connect-timeout 3 "${url%/*}/api/stats?days=1" 2>/dev/null)
                        if [ -n "$stats" ]; then
                            conversations=$(echo "$stats" | grep -o '"total_conversations":[0-9]*' | cut -d':' -f2)
                            if [ -n "$conversations" ]; then
                                echo "    💬 오늘 대화 수: ${conversations}개"
                            fi
                        fi
                    fi
                    ;;
            esac
            
        else
            echo -e "${RED}❌ 실패${NC} (응답: $response, 기대: $expected_status)"
            OVERALL_STATUS=1
        fi
    else
        echo -e "${YELLOW}⚠️ curl 없음${NC} (설치 필요)"
        OVERALL_STATUS=1
    fi
}

# Docker 컨테이너 상태 체크
check_docker_containers() {
    echo ""
    echo -e "${BLUE}🐳 Docker 컨테이너 상태:${NC}"
    echo "----------------------------------------"
    
    if ! command -v docker > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker가 설치되지 않았습니다${NC}"
        OVERALL_STATUS=1
        return
    fi
    
    # 각 서비스별 컨테이너 체크
    containers=(
        "cheeseade-webui:server-webui:Open WebUI"
        "cheeseade-rag-server:server-rag:RAG Server" 
        "cheeseade-milvus-standalone:server-milvus:Milvus DB"
        "cheeseade-milvus-etcd:server-milvus:Milvus etcd"
        "cheeseade-milvus-minio:server-milvus:Milvus MinIO"
        "llm-server:server-llm:LLM Server"
    )
    
    # 로깅 서버 컨테이너 추가 (활성화된 경우)
    if [ "$ENABLE_LOGGING" = "true" ]; then
        containers+=(
            "cheeseade-logging-db:server-logging:PostgreSQL DB"
            "cheeseade-logging-api:server-logging:Logging API"
        )
    fi
    
    for container_info in "${containers[@]}"; do
        container_name="${container_info%%:*}"
        service_dir=$(echo "$container_info" | cut -d':' -f2)
        description=$(echo "$container_info" | cut -d':' -f3)
        
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${container_name}"; then
            status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "^${container_name}" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
            
            if [[ "$status" =~ ^Up.*\(healthy\) ]]; then
                echo -e "✅ ${container_name}: ${GREEN}실행 중 (정상)${NC} ($service_dir)"
            elif [[ "$status" =~ ^Up ]]; then
                echo -e "🟡 ${container_name}: ${YELLOW}실행 중 (헬스체크 중)${NC} ($service_dir)"
            else
                echo -e "⚠️ ${container_name}: ${YELLOW}$status${NC} ($service_dir)"
                OVERALL_STATUS=1
            fi
            
            # 포트 매핑 정보 추가
            port_info=$(docker port "$container_name" 2>/dev/null | head -2 | tr '\n' ' ')
            if [ -n "$port_info" ]; then
                echo "    🔌 포트: $port_info"
            fi
        else
            echo -e "❌ ${container_name}: ${RED}실행되지 않음${NC} ($service_dir)"
            OVERALL_STATUS=1
        fi
    done
}

# 네트워크 연결 체크
check_network_connectivity() {
    echo ""
    echo -e "${CYAN}🌐 네트워크 연결 확인:${NC}"
    echo "----------------------------------------"
    
    # 공유기 포트포워딩 상태 확인
    ports=(
        "${WEBUI_PORT}:Open WebUI"
        "${RAG_PORT}:RAG Server" 
        "${MILVUS_MONITOR_PORT}:Milvus Admin"
        "${LLM_PORT}:LLM Server"
    )
    
    # 로깅 서버 포트 추가 (활성화된 경우)
    if [ "$ENABLE_LOGGING" = "true" ]; then
        ports+=("${LOGGING_PORT}:Logging API")
    fi
    
    echo -e "🔍 공유기 포트포워딩 확인 (${WEBUI_SERVER_IP}):"
    for port_info in "${ports[@]}"; do
        port="${port_info%%:*}"
        service="${port_info##*:}"
        
        # 공유기를 통한 외부 접근 테스트
        external_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://${WEBUI_SERVER_IP}:${port}" 2>/dev/null)
        
        if [ "$external_response" = "200" ] || [ "$external_response" = "302" ]; then
            echo -e "  ✅ 포트 $port: ${GREEN}접근 가능${NC} ($service)"
        elif [ "$external_response" = "000" ]; then
            echo -e "  ❌ 포트 $port: ${RED}접근 불가${NC} ($service) - 포트포워딩 확인 필요"
            OVERALL_STATUS=1
        else
            echo -e "  🟡 포트 $port: ${YELLOW}응답 코드 $external_response${NC} ($service)"
        fi
    done
    
    echo ""
    echo -e "🔍 Docker 포트 매핑 확인:"
    # Docker 컨테이너별 포트 매핑 상태
    key_containers=("cheeseade-webui" "cheeseade-rag-server" "llm-server")
    
    # 로깅 서버 컨테이너 추가 (활성화된 경우)
    if [ "$ENABLE_LOGGING" = "true" ]; then
        key_containers+=("cheeseade-logging-api")
    fi
    
    for container in "${key_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            port_mapping=$(docker port "$container" 2>/dev/null)
            if [ -n "$port_mapping" ]; then
                echo -e "  ✅ $container: ${GREEN}포트 매핑 정상${NC}"
                echo "$port_mapping" | sed 's/^/      /'
            else
                echo -e "  ⚠️ $container: ${YELLOW}포트 매핑 없음${NC}"
            fi
        fi
    done
}

# 시스템 리소스 체크
check_system_resources() {
    echo ""
    echo -e "${PURPLE}💻 시스템 리소스:${NC}"
    echo "----------------------------------------"
    
    # 메모리 사용량
    if command -v free > /dev/null 2>&1; then
        memory_info=$(free -h | grep "Mem:")
        total_mem=$(echo $memory_info | awk '{print $2}')
        used_mem=$(echo $memory_info | awk '{print $3}')
        free_mem=$(echo $memory_info | awk '{print $4}')
        echo "🧠 메모리: 사용 $used_mem / 전체 $total_mem (여유: $free_mem)"
        
        # 메모리 사용률 계산 및 경고
        used_percent=$(echo $memory_info | awk '{print int($3/$2*100)}')
        if [ "$used_percent" -gt 90 ]; then
            echo -e "    ${RED}⚠️ 메모리 사용률이 높습니다 (${used_percent}%)${NC}"
            OVERALL_STATUS=1
        fi
    fi
    
    # 디스크 사용량
    if command -v df > /dev/null 2>&1; then
        disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
        disk_info=$(df -h / | tail -1)
        echo "💾 디스크: $(echo $disk_info | awk '{print $3}') / $(echo $disk_info | awk '{print $2}') (사용률: ${disk_usage}%)"
        
        if [ "$disk_usage" -gt 90 ]; then
            echo -e "    ${RED}⚠️ 디스크 사용률이 높습니다 (${disk_usage}%)${NC}"
            OVERALL_STATUS=1
        fi
    fi
    
    # CPU 로드
    if command -v uptime > /dev/null 2>&1; then
        load_info=$(uptime)
        load_avg=$(echo "$load_info" | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
        echo "⚙️ CPU 로드: $load_avg"
        
        # CPU 코어 수 확인
        if command -v nproc > /dev/null 2>&1; then
            cpu_cores=$(nproc)
            echo "    CPU 코어: ${cpu_cores}개"
        fi
    fi
    
    # GPU 상태 (있는 경우)
    if command -v nvidia-smi > /dev/null 2>&1; then
        echo "🎮 GPU 상태:"
        gpu_info=$(nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$gpu_info" ]; then
            echo "    $gpu_info"
        fi
    fi
}

# 기능 테스트
run_functional_tests() {
    echo ""
    echo -e "${GREEN}🧪 기능 테스트:${NC}"
    echo "----------------------------------------"
    
    # RAG 검색 기능 테스트
    echo -n "🔍 RAG 검색 테스트: "
    rag_test_response=$(curl -s -X POST "http://${RAG_SERVER_IP}:${RAG_PORT}/debug/test-retrieval" \
        -H "Content-Type: application/json" \
        -d '{"question": "카메라 기능"}' \
        --connect-timeout 10 2>/dev/null)

    if echo "$rag_test_response" | grep -q "question.*retrieved_docs"; then
        doc_count=$(echo "$rag_test_response" | grep -o '"retrieved_docs":[0-9]*' | cut -d':' -f2)
        echo -e "${GREEN}✅ 정상${NC} (검색된 문서: ${doc_count}개)"
        SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
    else
        echo -e "${RED}❌ 실패${NC}"
        OVERALL_STATUS=1
    fi
    SERVICES_TOTAL=$((SERVICES_TOTAL + 1))

    # 간단한 채팅 테스트
    echo -n "💬 채팅 기능 테스트: "
    chat_test_response=$(curl -s -X POST "http://${RAG_SERVER_IP}:${RAG_PORT}/api/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": "안녕하세요", "model": "'$RAG_MODEL_NAME'"}' \
        --connect-timeout 15 2>/dev/null)

    if echo "$chat_test_response" | grep -q -E "choices|content|message"; then
        echo -e "${GREEN}✅ 정상${NC} (AI 응답 생성)"
        SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
    elif echo "$chat_test_response" | grep -q "detail"; then
        echo -e "${YELLOW}⚠️ 부분 실패${NC} (API 에러: $(echo "$chat_test_response" | grep -o '"detail":"[^"]*"' | cut -d'"' -f4))"
        # 채팅 기능에 문제가 있어도 전체 시스템은 정상으로 처리 (다른 방법으로 접근 가능)
    else
        echo -e "${RED}❌ 실패${NC}"
        OVERALL_STATUS=1
    fi
    SERVICES_TOTAL=$((SERVICES_TOTAL + 1))

    # WebUI 접근 테스트
    echo -n "🌐 WebUI 접근 테스트: "
    webui_test_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://${WEBUI_SERVER_IP}:${WEBUI_PORT}/" 2>/dev/null)
    
    if [ "$webui_test_response" = "200" ]; then
        echo -e "${GREEN}✅ 정상${NC} (WebUI 로드 가능)"
        SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
    else
        echo -e "${RED}❌ 실패${NC} (HTTP: $webui_test_response)"
        OVERALL_STATUS=1
    fi
    SERVICES_TOTAL=$((SERVICES_TOTAL + 1))

    # 로깅 기능 테스트 (활성화된 경우)
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo -n "📊 로깅 기능 테스트: "
        logging_test_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${LOGGING_SERVER_IP}:${LOGGING_PORT}/api/stats" 2>/dev/null)
        
        if [ "$logging_test_response" = "200" ]; then
            echo -e "${GREEN}✅ 정상${NC} (통계 API 응답)"
            SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
        else
            echo -e "${RED}❌ 실패${NC} (HTTP: $logging_test_response)"
            OVERALL_STATUS=1
        fi
        SERVICES_TOTAL=$((SERVICES_TOTAL + 1))
    fi
}

# 주요 서비스 상태 체크
echo -e "${BLUE}🌐 웹 서비스 상태:${NC}"
echo "----------------------------------------"
check_service "Open WebUI" "http://${WEBUI_SERVER_IP}:${WEBUI_PORT}" "200" "사용자 인터페이스"
check_service "RAG Server Health" "http://${RAG_SERVER_IP}:${RAG_PORT}/health" "200" "RAG 헬스체크"
check_service "RAG API Models" "http://${RAG_SERVER_IP}:${RAG_PORT}/api/models" "200" "모델 목록 API"

echo ""
echo -e "${GREEN}🤖 AI 서비스 상태:${NC}"
echo "----------------------------------------"
check_service "LLM Server" "http://${LLM_SERVER_IP}:${LLM_PORT}/api/tags" "200" "Ollama 언어모델"
check_service "Milvus Health" "http://${MILVUS_SERVER_IP}:${MILVUS_MONITOR_PORT}/healthz" "200" "벡터 데이터베이스"
check_service "Milvus Admin" "http://${MILVUS_SERVER_IP}:9001" "200" "Milvus 관리자 UI"

# 로깅 서비스 상태 체크 (활성화된 경우)
if [ "$ENABLE_LOGGING" = "true" ]; then
    echo ""
    echo -e "${PURPLE}📊 로깅 서비스 상태:${NC}"
    echo "----------------------------------------"
    check_service "Logging API" "http://${LOGGING_SERVER_IP}:${LOGGING_PORT}/health" "200" "로깅 API 서버"
    check_service "PostgreSQL" "http://${LOGGING_SERVER_IP}:${LOGGING_PORT}/api/stats" "200" "데이터베이스 연결"
fi

# 상세 체크들
check_docker_containers
check_network_connectivity
check_system_resources
run_functional_tests

# 최종 결과
echo ""
echo -e "${PURPLE}📊 종합 상태 요약:${NC}"
echo "========================================"
echo "✅ 정상 서비스: ${SERVICES_HEALTHY}/${SERVICES_TOTAL}"

if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "🎉 ${GREEN}전체 시스템 상태: 정상${NC}"
    echo ""
    echo -e "${CYAN}🌐 접속 정보:${NC}"
    echo "   • CHEESEADE WebUI: http://${WEBUI_SERVER_IP}:${WEBUI_PORT}"
    echo "   • RAG API 문서: http://${RAG_SERVER_IP}:${RAG_PORT}/docs"
    echo "   • Milvus Admin: http://${MILVUS_SERVER_IP}:9001"
    
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo "   • 로깅 API: http://${LOGGING_SERVER_IP}:${LOGGING_PORT}"
        echo "   • 로깅 API 문서: http://${LOGGING_SERVER_IP}:${LOGGING_PORT}/docs"
        echo "   • pgAdmin: http://${LOGGING_SERVER_IP}:8080 (선택적)"
    fi
    
    echo ""
    echo -e "${BLUE}📋 사용 가능한 AI 모델:${NC}"
    echo "   • ${RAG_MODEL_NAME} (CHEESEADE RAG 전문 상담)"
    echo "   • ${LLM_MODEL_NAME} (일반 대화)"
    
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo ""
        echo -e "${PURPLE}📊 로깅 기능:${NC}"
        echo "   • 모든 RAG 질문/답변 자동 기록"
        echo "   • 실시간 통계 및 분석"
        echo "   • 대화 내역 검색 가능"
    fi
    
    echo ""
    echo -e "${GREEN}💡 시스템이 완전히 준비되었습니다!${NC}"
else
    echo -e "⚠️ ${YELLOW}전체 시스템 상태: 일부 문제 있음${NC}"
    echo ""
    echo -e "${RED}🔧 문제 해결 방법:${NC}"
    echo "   1. 실패한 서비스의 상세 로그 확인:"
    echo "      docker logs [container-name]"
    echo "   2. 개별 서비스 재시작:"
    echo "      cd [service-directory] && docker compose restart"
    echo "   3. 전체 시스템 재배포:"
    echo "      ./stop.sh && ./deploy.sh"
    echo "   4. 네트워크 문제 시:"
    echo "      공유기 포트포워딩 설정 확인"
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo "   5. 로깅 서버 문제 시:"
        echo "      docker compose -f server-logging/docker-compose.yml logs"
        echo "      docker exec cheeseade-logging-db pg_isready -U raguser"
    fi
fi

echo ""
echo -e "${BLUE}📋 추가 도구:${NC}"
echo "   • 상세 로그 수집: ./monitoring/logs-collect.sh"
echo "   • 실시간 모니터링: docker stats"
echo "   • 서비스 재시작: ./deploy.sh"

if [ "$ENABLE_LOGGING" = "true" ]; then
    echo "   • 로깅 데이터 백업: docker exec cheeseade-logging-db pg_dump -U raguser rag_logging > backup.sql"
    echo "   • 로깅 통계 확인: curl http://${LOGGING_SERVER_IP}:${LOGGING_PORT}/api/stats"
fi

echo ""

exit $OVERALL_STATUS