#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

if [ -f ".env.global" ]; then
    source .env.global
    echo "✅ 전역 환경변수 로드됨"
else
    echo "⚠️ .env.global 파일이 없습니다."
    exit 1
fi

echo -e "${PURPLE}🛑 WK RAG 시스템 전체 중지${NC}"
echo "========================================"
echo "📅 중지 시간: $(date)"
echo ""

# 전역 상태 변수
TOTAL_SERVICES=0
STOPPED_SERVICES=0
ERRORS=0

# Docker 명령어 확인
check_docker() {
    if ! command -v docker > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker가 설치되지 않았습니다${NC}"
        return 1
    fi
    
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker 데몬이 실행되지 않았습니다${NC}"
        return 1
    fi
    
    return 0
}

# 서비스 중지 함수
stop_service() {
    local service_dir="$1"
    local service_name="$2"
    
    TOTAL_SERVICES=$((TOTAL_SERVICES + 1))
    
    echo -e "${BLUE}🔄 $service_name 중지 중...${NC}"
    
    if [ ! -d "$service_dir" ]; then
        echo -e "${YELLOW}  ⚠️ 디렉토리 없음: $service_dir${NC}"
        return 1
    fi
    
    cd "$service_dir" || {
        echo -e "${RED}  ❌ 디렉토리 접근 실패: $service_dir${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    }
    
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${YELLOW}  ⚠️ docker-compose.yml 없음${NC}"
        cd - > /dev/null
        return 1
    fi
    
    # Docker Compose 중지
    echo "  📦 컨테이너 중지 중..."
    if docker compose down --timeout 30 > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ $service_name 중지 완료${NC}"
        STOPPED_SERVICES=$((STOPPED_SERVICES + 1))
    else
        echo -e "${RED}  ❌ $service_name 중지 실패${NC}"
        ERRORS=$((ERRORS + 1))
        
        # 강제 중지 시도
        echo "  🔧 강제 중지 시도 중..."
        if docker compose kill > /dev/null 2>&1; then
            docker compose rm -f > /dev/null 2>&1
            echo -e "${YELLOW}  ⚠️ 강제 중지됨${NC}"
            STOPPED_SERVICES=$((STOPPED_SERVICES + 1))
        else
            echo -e "${RED}  ❌ 강제 중지도 실패${NC}"
        fi
    fi
    
    cd - > /dev/null
    echo ""
}


# 시스템 상태 확인
check_system_status() {
    echo -e "${BLUE}📊 시스템 상태 확인...${NC}"
    
    # 실행 중인 WK RAG 컨테이너
    running_containers=$(docker ps --format "{{.Names}}" | grep -E "wk" | wc -l)
    echo "  🏃 실행 중인 컨테이너: $running_containers 개"
    
    # 중지된 WK RAG 컨테이너
    stopped_containers=$(docker ps -a --format "{{.Names}}" | grep -E "wk" | wc -l)
    total_containers=$((stopped_containers - running_containers))
    echo "  🛑 중지된 컨테이너: $total_containers 개"
    
    # 포트 사용 상태
    echo "  🔌 포트 상태 확인:"
    ports=("3100" "8100" "19630" "9191")
    for port in "${ports[@]}"; do
        if command -v netstat > /dev/null 2>&1; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo "    ⚠️ 포트 $port: 여전히 사용 중"
            else
                echo "    ✅ 포트 $port: 해제됨"
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tuln 2>/dev/null | grep -q ":$port "; then
                echo "    ⚠️ 포트 $port: 여전히 사용 중"
            else
                echo "    ✅ 포트 $port: 해제됨"
            fi
        fi
    done
    
    echo ""
}

# 메인 중지 함수
main_stop() {
    
    echo -e "${CYAN}🚀 시스템 중지 시작...${NC}"
    echo ""
    
    # Docker 확인
    if ! check_docker; then
        echo -e "${RED}❌ Docker 확인 실패.${NC}"
        return 1
    fi
    
    # 역순으로 서비스 중지 (의존성 고려)
    echo -e "${BLUE}📋 서비스 중지 순서 (역순):${NC}"
    echo "  3 → 2 → 1"
    echo ""
    
    # Open WebUI 중지 
    stop_service "server-webui" "Open WebUI"
    
    # RAG Server 중지 
    stop_service "server-rag" "RAG Server"
    
    # Milvus Server 중지 
    stop_service "server-milvus" "Milvus Server"
    
    # 최종 상태 확인
    check_system_status
}

# 메인 중지 실행
main_stop

# 최종 요약
echo "🏁 중지 작업 완료 요약:"
echo "========================================"
echo "✅ 중지된 서비스: $STOPPED_SERVICES/$TOTAL_SERVICES"

if [ "$ERRORS" -gt 0 ]; then
    echo -e "❌ 오류 발생: ${RED}$ERRORS${NC} 개"
    echo "   일부 서비스가 완전히 중지되지 않았을 수 있습니다."
else
    echo -e "🎉 ${GREEN}모든 서비스가 성공적으로 중지되었습니다!${NC}"
fi

echo "⏱️ 중지 완료 시간: $(date)"
echo ""
echo ""
echo "🔄 재시작 방법:"
echo "   ./deploy.sh"
echo ""
echo -e "${GREEN}✅ WK RAG 시스템 중지 완료${NC}"

