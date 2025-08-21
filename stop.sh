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

echo -e "${PURPLE}🛑 CHEESEADE RAG 시스템 전체 중지${NC}"
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
    local description="$3"
    
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
        echo -e "${GREEN}  ✅ $service_name 중지 완료${NC} ($description)"
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

# 개별 컨테이너 강제 중지
force_stop_containers() {
    echo -e "${YELLOW}⚡ CHEESEADE RAG 관련 컨테이너 강제 중지...${NC}"
    
    # cheeseade RAG 관련 컨테이너 찾기
    containers=$(docker ps -a --format "{{.Names}}" | grep -E "cheeseade|rag" | head -10)
    
    if [ -z "$containers" ]; then
        echo "  📋 중지할 컨테이너가 없습니다."
        return 0
    fi
    
    echo "  🔍 발견된 컨테이너들:"
    echo "$containers" | while read container; do
        echo "    - $container"
    done
    echo ""
    
    # 컨테이너 개별 중지
    echo "$containers" | while read container; do
        if [ -n "$container" ]; then
            echo -n "  🛑 $container 중지 중... "
            
            # 정상 중지 시도 (30초 타임아웃)
            if docker stop --time 30 "$container" > /dev/null 2>&1; then
                echo -e "${GREEN}✅ 중지됨${NC}"
            else
                echo -n -e "${YELLOW}강제 중지... ${NC}"
                # 강제 종료
                if docker kill "$container" > /dev/null 2>&1; then
                    echo -e "${GREEN}✅ 강제 중지됨${NC}"
                else
                    echo -e "${RED}❌ 실패${NC}"
                fi
            fi
            
            # 컨테이너 제거
            docker rm "$container" > /dev/null 2>&1
        fi
    done
    
    echo ""
}

# 네트워크 정리
cleanup_networks() {
    echo -e "${CYAN}🌐 네트워크 정리 중...${NC}"
    
    # CHEESEADE RAG 관련 네트워크 찾기
    networks=$(docker network ls --format "{{.Name}}" | grep -E "cheeseade|rag|milvus" | head -5)
    
    if [ -z "$networks" ]; then
        echo "  📋 정리할 네트워크가 없습니다."
        return 0
    fi
    
    echo "  🔍 발견된 네트워크들:"
    echo "$networks" | while read network; do
        echo "    - $network"
    done
    echo ""
    
    # 네트워크 제거
    echo "$networks" | while read network; do
        if [ -n "$network" ] && [ "$network" != "bridge" ] && [ "$network" != "host" ] && [ "$network" != "none" ]; then
            echo -n "  🗑️ $network 제거 중... "
            if docker network rm "$network" > /dev/null 2>&1; then
                echo -e "${GREEN}✅ 제거됨${NC}"
            else
                echo -e "${YELLOW}⚠️ 사용 중이거나 제거 실패${NC}"
            fi
        fi
    done
    
    echo ""
}

# 볼륨 정리 (선택적)
cleanup_volumes() {
    echo -e "${CYAN}💾 볼륨 정리 중...${NC}"
    
    # CHEESEADE RAG 관련 볼륨 찾기
    volumes=$(docker volume ls --format "{{.Name}}" | grep -E "cheeseade|rag|milvus" | head -5)
    
    if [ -z "$volumes" ]; then
        echo "  📋 정리할 볼륨이 없습니다."
        return 0
    fi
    
    echo "  🔍 발견된 볼륨들:"
    echo "$volumes" | while read volume; do
        echo "    - $volume"
    done
    echo ""
    
    # 볼륨 제거 확인
    read -p "⚠️ 볼륨을 제거하면 데이터가 영구 삭제됩니다. 계속하시겠습니까? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "$volumes" | while read volume; do
            if [ -n "$volume" ]; then
                echo -n "  🗑️ $volume 제거 중... "
                if docker volume rm "$volume" > /dev/null 2>&1; then
                    echo -e "${GREEN}✅ 제거됨${NC}"
                else
                    echo -e "${YELLOW}⚠️ 사용 중이거나 제거 실패${NC}"
                fi
            fi
        done
    else
        echo "  📋 볼륨 정리를 건너뜁니다."
    fi
    
    echo ""
}

cleanup_webui_data() {
    echo -e "${CYAN}🧹 WebUI 데이터 정리 중...${NC}"
    
    if [ -d "server-webui/data" ]; then
        echo -n "  📁 data 폴더 삭제 중... "
        rm -rf server-webui/data
        echo -e "${GREEN}✅${NC}"
    fi
    
    if [ -d "server-webui/config" ]; then
        echo -n "  📁 config 폴더 삭제 중... "
        rm -rf server-webui/config
        echo -e "${GREEN}✅${NC}"
    fi
    
    echo -e "${GREEN}✅ WebUI 데이터 정리 완료${NC}"
    echo ""
}

# 서비스별 추가 정리
cleanup_service_data() {
    local service_dir="$1"
    local cleanup_type="$2"
    
    case $cleanup_type in
        "logs")
            if [ -d "$service_dir/logs" ]; then
                echo -n "  🧹 로그 파일 정리 ($service_dir)... "
                find "$service_dir/logs" -name "*.log" -mtime +7 -delete 2>/dev/null
                echo -e "${GREEN}✅${NC}"
            fi
            ;;
        "temp")
            if [ -d "$service_dir/tmp" ]; then
                echo -n "  🧹 임시 파일 정리 ($service_dir)... "
                rm -rf "$service_dir/tmp"/* 2>/dev/null
                echo -e "${GREEN}✅${NC}"
            fi
            ;;
    esac
}

# 시스템 상태 확인
check_system_status() {
    echo -e "${BLUE}📊 시스템 상태 확인...${NC}"
    
    # 실행 중인 CHEESEADE RAG 컨테이너
    running_containers=$(docker ps --format "{{.Names}}" | grep -E "cheeseade|rag" | wc -l)
    echo "  🏃 실행 중인 컨테이너: $running_containers 개"
    
    # 중지된 CHEESEADE RAG 컨테이너
    stopped_containers=$(docker ps -a --format "{{.Names}}" | grep -E "cheeseade|rag" | wc -l)
    total_containers=$((stopped_containers - running_containers))
    echo "  🛑 중지된 컨테이너: $total_containers 개"
    
    # 포트 사용 상태
    echo "  🔌 포트 상태 확인:"
    ports=("3000" "8000" "11434" "19530" "9091")
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

# 도움말 표시
show_help() {
    echo "🛑 CHEESEADE RAG 시스템 중지 스크립트"
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  -h, --help              이 도움말 표시"
    echo "  -f, --force             강제 중지 (확인 없이 즉시 실행)"
    echo "  -q, --quiet             출력 최소화"
    echo "  --keep-volumes          볼륨 유지 (데이터 보존)"
    echo "  --keep-networks         네트워크 유지"
    echo "  --clean-logs            오래된 로그 파일 정리"
    echo "  --status-only           상태 확인만 수행"
    echo ""
    echo "예시:"
    echo "  $0                      # 대화형 중지"
    echo "  $0 -f                   # 강제 중지"
    echo "  $0 --keep-volumes       # 데이터 보존하며 중지"
    echo "  $0 --status-only        # 현재 상태만 확인"
    echo ""
    echo "중지 순서:"
    echo "  1. Open WebUI (사용자 인터페이스)"
    echo "  2. RAG Server (API 서버)"
    echo "  3. LLM Server (언어 모델)"
    echo "  4. Milvus Server (벡터 데이터베이스)"
    echo ""
}

# 중지 확인
confirm_stop() {
    local force="$1"
    
    if [ "$force" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️ CHEESEADE RAG 시스템을 중지하시겠습니까?${NC}"
    echo "다음 서비스들이 중지됩니다:"
    echo "  • Open WebUI (사용자 인터페이스)"
    echo "  • RAG Server (문서 검색 및 AI 응답)"
    echo "  • LLM Server (언어 모델 추론)"
    echo "  • Milvus Server (벡터 데이터베이스)"
    echo ""
    
    read -p "계속하시겠습니까? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "중지가 취소되었습니다."
        exit 0
    fi
    
    echo ""
}

# 메인 중지 함수
main_stop() {
    local keep_volumes="$1"
    local keep_networks="$2"
    local clean_logs="$3"
    local keep_webui_config="$4"
    
    echo -e "${CYAN}🚀 시스템 중지 시작...${NC}"
    echo ""
    
    # Docker 확인
    if ! check_docker; then
        echo -e "${RED}❌ Docker 확인 실패. 개별 컨테이너 중지를 시도합니다.${NC}"
        force_stop_containers
        return 1
    fi
    
    # 1. 역순으로 서비스 중지 (의존성 고려)
    echo -e "${BLUE}📋 서비스 중지 순서 (역순):${NC}"
    echo "  4 → 3 → 2 → 1"
    echo ""
    
    # 4. Open WebUI 중지 (제일 먼저)
    stop_service "server-webui" "Open WebUI" "사용자 인터페이스"
    
    # 3. RAG Server 중지 
    stop_service "server-rag" "RAG Server" "API 및 검색 서버"
    
    # 1. Milvus Server 중지 (제일 마지막)
    stop_service "server-milvus" "Milvus Server" "벡터 데이터베이스"
    
    # 개별 컨테이너 강제 중지 (남은 것들)
    force_stop_containers
    
    # 선택적 정리 작업
    if [ "$keep_networks" != true ]; then
        cleanup_networks
    fi
    
    if [ "$keep_volumes" != true ]; then
        cleanup_volumes
    fi
    
    if [ "$clean_logs" = true ]; then
        echo -e "${CYAN}🧹 로그 파일 정리...${NC}"
        cleanup_service_data "server-webui" "logs"
        cleanup_service_data "server-rag" "logs"
        cleanup_service_data "server-milvus" "logs"
        echo ""
    fi

    # 메인 중지 함수 실행 후 WebUI 정리 (선택적)
    if [ "keep_webui_config" != true ]; then
        cleanup_webui_data
    fi
    
    # 최종 상태 확인
    check_system_status
}

# 옵션 파싱
FORCE=false
QUIET=false
KEEP_VOLUMES=false
KEEP_NETWORKS=false
CLEAN_LOGS=false
STATUS_ONLY=false
KEEP_WEBUI_SETTING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --keep-volumes)
            KEEP_VOLUMES=true
            shift
            ;;
        --keep-networks)
            KEEP_NETWORKS=true
            shift
            ;;
        --clean-logs)
            CLEAN_LOGS=true
            shift
            ;;
        --status-only)
            STATUS_ONLY=true
            shift
            ;;
        --keep-webui-config)
            KEEP_WEBUI_SETTING=true
            shift
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "사용법: $0 --help"
            exit 1
            ;;
    esac
done

# 출력 제어
if [ "$QUIET" = true ]; then
    exec > /dev/null 2>&1
fi

# 상태 확인만 수행
if [ "$STATUS_ONLY" = true ]; then
    check_docker
    check_system_status
    exit 0
fi

# 중지 확인
confirm_stop "$FORCE"

# 메인 중지 실행
main_stop "$KEEP_VOLUMES" "$KEEP_NETWORKS" "$CLEAN_LOGS" "$KEEP_WEBUI_SETTING"

# 최종 요약
echo "🏁 중지 작업 완료 요약:"
echo "========================================"
echo "✅ 중지된 서비스: $STOPPED_SERVICES/$TOTAL_SERVICES"

if [ "$ERRORS" -gt 0 ]; then
    echo -e "❌ 오류 발생: ${RED}$ERRORS${NC} 개"
    echo "   일부 서비스가 완전히 중지되지 않았을 수 있습니다."
    echo "   './scripts/backup-all.sh'로 백업 후 시스템 재부팅을 권장합니다."
else
    echo -e "🎉 ${GREEN}모든 서비스가 성공적으로 중지되었습니다!${NC}"
fi

echo "⏱️ 중지 완료 시간: $(date)"
echo ""

if [ "$KEEP_VOLUMES" = true ]; then
    echo -e "${BLUE}💾 데이터 보존됨: 다음에 ./deploy.sh로 재시작 가능${NC}"
else
    echo -e "${YELLOW}⚠️ 일부 데이터가 삭제되었을 수 있습니다.${NC}"
fi

echo ""
echo "🔄 재시작 방법:"
echo "   ./deploy.sh"
echo ""
echo "📊 상태 확인:"
echo "   ./health-check.sh"
echo ""
echo -e "${GREEN}✅ Samsung RAG 시스템 중지 완료${NC}"

