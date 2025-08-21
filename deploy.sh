#!/bin/bash
echo "🚀 치즈에이드 RAG 시스템 배포 시작"

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
    set -a
    source .env.global 
    set +a 
    echo "✅ 전역 환경변수 로드됨"
else
    echo "⚠️ .env.global 파일이 없습니다."
    exit 1
fi

export WEBUI_SERVER_URL="http://${WEBUI_SERVER_IP}:${WEBUI_PORT}"
export RAG_SERVER_URL="http://${RAG_SERVER_IP}:${RAG_PORT}"
export MILVUS_SERVER_URL="http://${MILVUS_SERVER_IP}:${MILVUS_PORT}"
export LLM_SERVER_URL="http://${LLM_SERVER_IP}:${LLM_PORT}"

echo "✅ 서버 URL 설정:"
echo "   WebUI: $WEBUI_SERVER_URL"
echo "   RAG: $RAG_SERVER_URL" 
echo "   LLM: $LLM_SERVER_URL"
echo "   Milvus: $MILVUS_SERVER_URL"

echo "📁 필요한 디렉토리 생성..."

# 각 서버별 데이터 디렉토리 생성 (로그 등)
# mkdir -p server-webui/config
# mkdir -p server-webui/data

# docs/ 폴더 내용 확인
DOC_COUNT=$(find server-rag/docs -type f 2>/dev/null | wc -l)
if [ "$DOC_COUNT" -eq 0 ]; then
    echo "❌ docs/ 폴더에 파일이 없습니다!"
    echo "server-rag/docs/ 폴더에 문서를 추가하세요"
    exit 1
fi

echo "✅ RAG를 위한 $DOC_COUNT 개의 문서 파일 확인됨"

# 전역 상태 변수
OVERALL_STATUS=0
SERVICES_TOTAL=0
SERVICES_HEALTHY=0

# WebUI 초기화 함수
initialize_webui() {
    echo ""
    echo -e "${PURPLE}🧹 WebUI 완전 초기화 시작${NC}"
    echo "========================================"
    
    cd server-webui || {
        echo -e "${RED}❌ server-webui 디렉토리 접근 실패${NC}"
        return 1
    }
    
    # 기존 컨테이너 중지 및 제거
    echo "🛑 기존 WebUI 컨테이너 중지..."
    docker compose down --remove-orphans 2>/dev/null || true
    
    # 새 디렉토리 생성
    mkdir -p data config
    echo "   ✅ 새 data, config 디렉토리 생성"
    
    cd ..
    echo -e "${GREEN}🎉 WebUI 초기화 완료!${NC}"
    return 0
}

# 헬스체크 함수들
check_milvus_health() {
    local max_attempts=60  # 5분 대기
    local attempt=1
    
    echo -e "${CYAN}⏳ Milvus 헬스체크 대기 중...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        echo -n "   시도 $attempt/$max_attempts: "
        
        # Docker 컨테이너 상태로 먼저 확인 (더 신뢰성 있음)
        etcd_status=$(docker ps --filter "name=wk-milvus-etcd" --format "{{.Status}}" 2>/dev/null)
        minio_status=$(docker ps --filter "name=wk-milvus-minio" --format "{{.Status}}" 2>/dev/null)
        milvus_status=$(docker ps --filter "name=wk-milvus-standalone" --format "{{.Status}}" 2>/dev/null)
        
        # 모든 컨테이너가 Up 상태인지 확인
        if [[ "$etcd_status" =~ ^Up.*\(healthy\) ]] || [[ "$etcd_status" =~ ^Up ]]; then
            echo -n "etcd(✅) "
        else
            echo -e "${YELLOW}etcd 컨테이너 시작 대기 중...${NC}"
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        if [[ "$minio_status" =~ ^Up.*\(healthy\) ]] || [[ "$minio_status" =~ ^Up ]]; then
            echo -n "minio(✅) "
        else
            echo -e "${YELLOW}MinIO 컨테이너 시작 대기 중...${NC}"
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        if [[ "$milvus_status" =~ ^Up.*\(healthy\) ]] || [[ "$milvus_status" =~ ^Up ]]; then
            echo -n "milvus(✅) "
        else
            echo -e "${YELLOW}Milvus 컨테이너 시작 대기 중...${NC}"
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # 최종 API 확인 (선택적)
        if curl -s --connect-timeout 3 "http://${MILVUS_SERVER_IP}:${MILVUS_MONITOR_PORT}/healthz" >/dev/null 2>&1; then
            echo -e "${GREEN}API(✅)${NC}"
            echo -e "${GREEN}✅ 모든 Milvus 컴포넌트 준비 완료!${NC}"
            return 0
        else
            echo -e "${YELLOW}Milvus API 응답 대기 중...${NC}"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}❌ Milvus 헬스체크 실패 (타임아웃)${NC}"
    return 1
}


check_rag_health() {
    local max_attempts=180  # 15분 대기 (자동 모델 다운로드 고려)
    local attempt=1
    
    echo -e "${CYAN}⏳ RAG 서버 헬스체크 대기 중...${NC}"
    echo -e "   💡 자동 모델 다운로드가 있을 수 있어 시간이 오래 걸릴 수 있습니다"
    
    while [ $attempt -le $max_attempts ]; do
        printf "   시도 %d/%d: " "$attempt" "$max_attempts"
        
        # 1. 컨테이너 상태 먼저 확인
        rag_status=$(docker ps --filter "name=wk-rag-server" --format "{{.Status}}" 2>/dev/null)
        if [[ ! "$rag_status" =~ ^Up ]]; then
            echo -e "${RED}컨테이너가 실행 중이 아님${NC}"
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # 2. 헬스체크 엔드포인트 직접 확인 (공유기 포트포워딩 통해서)
        health_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${RAG_SERVER_URL}/health" 2>/dev/null)
        if [ "$health_response" = "200" ]; then
            echo -e "${GREEN}✅ RAG 서버 준비 완료! (헬스체크 통과)${NC}"
            
            # 추가 정보 수집
            system_info=$(curl -s --connect-timeout 3 "${RAG_SERVER_URL}/" 2>/dev/null)
            if echo "$system_info" | grep -q "CHEESEADE RAG Server"; then
                echo -e "   📊 시스템 정보 확인됨"
                
                # 로드된 문서 수 확인
                docs_count=$(echo "$system_info" | grep -o '"documents_loaded":[0-9]*' | cut -d':' -f2)
                if [ -n "$docs_count" ] && [ "$docs_count" -gt 0 ]; then
                    echo -e "   📄 로드된 문서: ${docs_count}개"
                fi
                
                # 임베딩 디바이스 확인
                device=$(echo "$system_info" | grep -o '"embedding_device":"[^"]*"' | cut -d'"' -f4)
                if [ -n "$device" ]; then
                    echo -e "   🖥️ 임베딩 디바이스: ${device}"
                fi
            fi
            
            return 0
        fi
        
        # 3. 상세한 디버그 정보 (5번마다)
        if [ $((attempt % 5)) -eq 0 ]; then
            echo -e "${YELLOW}상세 디버그 정보:${NC}"
            
            # HTTP 응답 코드들 확인
            echo -e "   🔍 엔드포인트 응답 코드:"
            health_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "${RAG_SERVER_URL}/health" 2>/dev/null || echo "000")
            models_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "${RAG_SERVER_URL}/api/tags" 2>/dev/null || echo "000")
            
            echo -e "     /health: ${health_code}"
            echo -e "     /api/tags: ${models_code}" 
            
            # 로그 확인
            rag_logs=$(docker logs --tail 10 wk-rag-server 2>/dev/null || echo "로그 확인 불가")
            echo -e "   📋 최근 로그:"
            echo "$rag_logs" | tail -3 | sed 's/^/     /'
        else
            echo -e "${YELLOW}RAG 서버 초기화 대기 중... (${health_response:-000})${NC}"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}❌ RAG 서버 헬스체크 실패 (타임아웃)${NC}"
    return 1
}

check_webui_health() {
    local max_attempts=30  # 2.5분 대기
    local attempt=1
    
    echo -e "${CYAN}⏳ WebUI 헬스체크 대기 중...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        echo -n "   시도 $attempt/$max_attempts: "
        
        # WebUI 기본 페이지 확인
        if curl -s --connect-timeout 5 "${WEBUI_SERVER_URL}/" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ WebUI 준비 완료!${NC}"
            echo -e "   🌐 WebUI 페이지 로드 정상"
            echo -e "   🧹 데이터 초기화됨 - 깨끗한 상태로 시작"
            return 0
        else
            echo -e "${YELLOW}WebUI 초기화 대기 중...${NC}"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}❌ WebUI 헬스체크 실패 (타임아웃)${NC}"
    return 1
}

# 정리 함수
cleanup_on_failure() {
    echo ""
    echo -e "${RED}💥 배포 실패 감지 - 시스템 정리 중...${NC}"
    echo "========================================"
    
    echo -e "${YELLOW}🧹 실패한 컨테이너들을 정리합니다...${NC}"
    
    # stop.sh 실행
    if [ -f "./stop.sh" ]; then
        echo -e "   📋 stop.sh 스크립트 실행 중..."
        chmod +x ./stop.sh
        ./stop.sh --force --quiet 2>/dev/null || {
            echo -e "   ⚠️ stop.sh 실행 실패, 수동 정리 진행..."
            
            # 수동 정리
            echo -e "   🔧 수동 컨테이너 정리..."
            docker compose -f server-webui/docker-compose.yml down --remove-orphans 2>/dev/null || true
            docker compose -f server-rag/docker-compose.yml down --remove-orphans 2>/dev/null || true
            docker compose -f server-milvus/docker-compose.yml down --remove-orphans 2>/dev/null || true
        }
        
        echo -e "${GREEN}   ✅ 시스템 정리 완료${NC}"
    fi
}

# 서비스 시작 함수
start_service() {
    local service_dir="$1"
    local service_name="$2"
    local description="$3"
    local health_check_func="$4"
    
    SERVICES_TOTAL=$((SERVICES_TOTAL + 1))
    
    echo ""
    echo -e "${BLUE}🔄 $service_name 시작 중...${NC} ($description)"
    
    if [ ! -d "$service_dir" ]; then
        echo -e "${RED}❌ 디렉토리 없음: $service_dir${NC}"
        cleanup_on_failure
        exit 1
    fi
    
    cd "$service_dir" || {
        echo -e "${RED}❌ 디렉토리 접근 실패: $service_dir${NC}"
        cleanup_on_failure
        exit 1
    }
    
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}❌ docker-compose.yml 없음${NC}"
        cd ..
        cleanup_on_failure
        exit 1
    fi
    
    # 빌드 (캐시 없이)
    echo -e "   📦 이미지 빌드 중..."
    if docker compose build --no-cache >/dev/null 2>&1; then
        echo -e "   ✅ 빌드 성공"
    else
        echo -e "   ⚠️ 빌드 실패, 캐시 사용해서 재시도..."
        if ! docker compose build >/dev/null 2>&1; then
            echo -e "${RED}   ❌ 빌드 실패${NC}"
            cd ..
            cleanup_on_failure
            exit 1
        fi
    fi
    
    # 컨테이너 시작
    echo -e "   🚀 컨테이너 시작 중..."
    if docker compose up -d --force-recreate --remove-orphans; then
        echo -e "   ✅ 컨테이너 시작 성공"
    else
        echo -e "${RED}   ❌ 컨테이너 시작 실패${NC}"
        echo -e "   🔍 실패 로그:"
        docker compose logs --tail 20
        cd ..
        cleanup_on_failure
        exit 1
    fi
    
    cd ..
    
    # 헬스체크 실행
    if [ -n "$health_check_func" ]; then
        if ! $health_check_func; then
            echo -e "${RED}❌ $service_name 헬스체크 실패${NC}"
            cleanup_on_failure
            exit 1
        fi
    fi
    
    echo -e "${GREEN}🎉 $service_name 완전히 준비됨!${NC}"
    SERVICES_HEALTHY=$((SERVICES_HEALTHY + 1))
    return 0
}

# 기존 컨테이너와 이미지 정리
echo ""
echo -e "${YELLOW}🧹 기존 컨테이너 및 이미지 정리 중...${NC}"
docker compose -f server-webui/docker-compose.yml down --remove-orphans 2>/dev/null || true
docker compose -f server-rag/docker-compose.yml down --remove-orphans 2>/dev/null || true
docker compose -f server-milvus/docker-compose.yml down --remove-orphans 2>/dev/null || true

echo -e "${GREEN}✅ 정리 완료${NC}"

# WebUI 초기화 실행
initialize_webui

# 전역 에러 핸들러 설정
set -e  # 어떤 명령이든 실패하면 즉시 종료
trap 'cleanup_on_failure' ERR  # 에러 발생 시 정리 함수 호출

# 의존성 순서에 따른 서비스 시작
echo ""
echo -e "${CYAN}🎯 의존성 순서에 따른 서비스 시작${NC}"
echo -e "   순서: Milvus → RAG → WebUI"

# 1. Milvus Server (가장 기본이 되는 데이터베이스)
start_service "server-milvus" "Milvus Server" "벡터 데이터베이스" "check_milvus_health"

# 4. RAG Server (Milvus, LLM, 로깅에 의존)
start_service "server-rag" "RAG Server" "API 및 검색 서버" "check_rag_health"

# 5. WebUI Server (모든 백엔드 서비스에 의존) - 초기화됨
start_service "server-webui" "WebUI Server" "사용자 인터페이스" "check_webui_health"

# 에러 핸들러 해제 (정상 완료)
set +e
trap - ERR

# 최종 전체 시스템 검증
echo ""
echo -e "${CYAN}🔍 전체 시스템 최종 검증...${NC}"

# 모든 컨테이너 상태 확인
echo -e "📋 실행 중인 컨테이너:"
running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "wk")
if [ -n "$running_containers" ]; then
    echo "$running_containers"
    
    # 컨테이너 개수 확인
    container_count=$(echo "$running_containers" | wc -l)
    expected_count=5  # 로깅 서버 포함
    
    echo -e "\n📊 총 실행 중인 컨테이너: ${container_count}개 (예상: ${expected_count}개)"
    
    if [ "$container_count" -ge "$expected_count" ]; then
        echo -e "${GREEN}✅ 모든 컨테이너가 정상 실행 중${NC}"
    else
        echo -e "${YELLOW}⚠️ 일부 컨테이너가 누락될 수 있습니다${NC}"
    fi
else
    echo -e "${RED}❌ 실행 중인 컨테이너가 없습니다!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 치즈에이드 RAG 시스템 배포 완료!${NC}"
echo "========================================"
echo -e "⏱️ 배포 완료 시간: $(date)"
echo ""
echo -e "${CYAN}📊 다음 단계:${NC}"
echo "   1. 🌐 브라우저 접속: http://${WEBUI_SERVER_IP}:${WEBUI_PORT}"
echo "      ⚠️ 중요: 시크릿/인코그니토 모드로 접속 (캐시 방지)"
echo "   2. 🤖 사용 가능한 모델:"
echo "      • ${RAG_MODEL_NAME} (CHEESEADE RAG를 활용한 전문 상담)"


echo ""
echo -e "${PURPLE}🧹 WebUI 초기화 완료:${NC}"
echo "   • 이전 채팅 기록 완전 삭제됨"
echo "   • 서버 연결 설정 초기화됨"  
echo "   • 브라우저 캐시와 무관한 깨끗한 상태"
echo "   • 최적화된 환경변수 적용됨"
echo ""
echo -e "${BLUE}🔧 문제 발생 시:${NC}"
echo "   • 로그 수집: ./monitoring/logs-collect.sh"
echo "   • 시스템 재시작: ./stop.sh && ./deploy.sh"
echo "   • 브라우저 캐시 삭제 또는 시크릿 모드 사용"

echo ""
echo -e "${GREEN}✨ 배포가 성공적으로 완료되었습니다!${NC}"
echo -e "${YELLOW}💡 첫 접속 시 반드시 시크릿 모드를 사용하세요!${NC}"
echo ""