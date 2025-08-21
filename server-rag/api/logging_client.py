# server-rag/api/logging_client.py
"""
RAG 서버에서 로깅 서버로 데이터를 전송하는 클라이언트 (SQLite 호환)
"""
import os
import asyncio
import time
from typing import List, Dict, Any, Optional
from datetime import datetime
import json

try:
    import httpx
    HTTPX_AVAILABLE = True
except ImportError:
    HTTPX_AVAILABLE = False
    print("⚠️ httpx가 설치되지 않았습니다. 로깅 기능이 비활성화됩니다.")

class RAGLoggingClient:
    """RAG 로깅 클라이언트 (SQLite 호환)"""
    
    def __init__(self, logging_server_url: str = None):
        self.logging_server_url = logging_server_url or os.getenv(
            "LOGGING_SERVER_URL", 
            f"http://{os.getenv('LOGGING_SERVER_IP', 'localhost')}:{os.getenv('LOGGING_PORT', '1889')}"
        )
        self.enabled = (
            os.getenv("ENABLE_LOGGING", "true").lower() == "true" and 
            HTTPX_AVAILABLE
        )
        
        if not self.enabled:
            if not HTTPX_AVAILABLE:
                print("⚠️ RAG 로깅이 비활성화되었습니다 (httpx 미설치).")
            else:
                print("⚠️ RAG 로깅이 비활성화되었습니다 (ENABLE_LOGGING=false).")
        else:
            print(f"📝 RAG 로깅 클라이언트 초기화: {self.logging_server_url}")
    
    def _extract_session_id(self, request_info: Dict[str, str] = None) -> str:
        """요청에서 세션 ID 추출 (또는 생성)"""
        if request_info and request_info.get("session_id"):
            return request_info["session_id"]
        
        if request_info and request_info.get("user_ip"):
            # IP 기반 세션 ID 생성 (간단한 방법)
            import hashlib
            session_seed = f"{request_info['user_ip']}_{datetime.now().strftime('%Y%m%d')}"
            session_hash = hashlib.md5(session_seed.encode()).hexdigest()[:12]
            return f"ip_{session_hash}"
        
        # 임시 세션 ID 생성
        import uuid
        return f"temp_{uuid.uuid4().hex[:12]}"
    
    def _convert_contexts_to_log_format(self, contexts: List[Any]) -> List[Dict[str, Any]]:
        """LangChain Document를 로깅 형식으로 변환 (SQLite 호환)"""
        converted_contexts = []
        
        for context in contexts:
            if hasattr(context, 'page_content') and hasattr(context, 'metadata'):
                # LangChain Document 객체
                converted_context = {
                    "content": str(context.page_content)[:5000],  # 길이 제한
                    "source_document": str(context.metadata.get("source", ""))[:255],
                    "header1": str(context.metadata.get("Header 1", ""))[:255],
                    "header2": str(context.metadata.get("Header 2", ""))[:255],
                    "similarity_score": float(context.metadata.get("score", 0.0)) if context.metadata.get("score") else None,
                    "chunk_metadata": {
                        k: str(v)[:500] if isinstance(v, str) else v 
                        for k, v in context.metadata.items() 
                        if k not in ["source", "Header 1", "Header 2", "score"] and v is not None
                    }
                }
            elif isinstance(context, dict):
                # 이미 딕셔너리 형태
                converted_context = {
                    "content": str(context.get("content", ""))[:5000],
                    "source_document": str(context.get("source_document", ""))[:255],
                    "header1": str(context.get("header1", ""))[:255],
                    "header2": str(context.get("header2", ""))[:255], 
                    "similarity_score": float(context.get("similarity_score", 0.0)) if context.get("similarity_score") else None,
                    "chunk_metadata": context.get("chunk_metadata", {})
                }
            else:
                # 기타 형태는 문자열로 처리
                converted_context = {
                    "content": str(context)[:5000],
                    "source_document": "unknown",
                    "header1": "",
                    "header2": "",
                    "similarity_score": None,
                    "chunk_metadata": {}
                }
            
            # None 값들을 빈 문자열로 처리 (SQLite 호환성)
            for key in ["source_document", "header1", "header2"]:
                if converted_context[key] is None:
                    converted_context[key] = ""
            
            converted_contexts.append(converted_context)
        
        return converted_contexts
    
    async def log_conversation(
        self,
        session_id: str,
        user_question: str,
        contexts: List[Any],
        rag_response: str,
        model_used: str,
        response_time_ms: int,
        question_language: str = "ko",
        response_language: str = "ko",
        user_ip: str = None,
        user_agent: str = None
    ) -> bool:
        """RAG 대화를 로깅 서버에 전송 (SQLite 호환)"""
        
        if not self.enabled or not HTTPX_AVAILABLE:
            return False
        
        try:
            # 컨텍스트를 로깅 형식으로 변환
            converted_contexts = self._convert_contexts_to_log_format(contexts)
            
            # 로그 데이터 구성 (SQLite 테이블 구조에 맞춤)
            log_data = {
                "session_id": session_id[:255],  # 길이 제한
                "user_question": str(user_question)[:2000],  # 길이 제한
                "contexts": converted_contexts,
                "rag_response": str(rag_response)[:5000],  # 길이 제한
                "model_used": str(model_used)[:100],
                "response_time_ms": int(response_time_ms),
                "question_language": question_language[:10],
                "response_language": response_language[:10],
                "metadata": {
                    "user_ip": user_ip[:45] if user_ip else None,
                    "user_agent": user_agent[:500] if user_agent else None,
                    "contexts_count": len(converted_contexts),
                    "logged_at": datetime.now().isoformat(),
                    "rag_server": "cheeseade-rag-server"
                }
            }
            
            # 비동기로 로깅 서버에 전송
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(
                    f"{self.logging_server_url}/api/log",
                    json=log_data,
                    headers={"Content-Type": "application/json"}
                )
                
                if response.status_code == 200:
                    result = response.json()
                    conversation_id = result.get('conversation_id', 'unknown')
                    print(f"✅ 로그 전송 성공: {conversation_id} (SQLite)")
                    return True
                else:
                    print(f"❌ 로그 전송 실패: HTTP {response.status_code}")
                    try:
                        error_detail = response.json()
                        print(f"   오류 상세: {error_detail}")
                    except:
                        print(f"   응답 내용: {response.text[:200]}")
                    return False
                    
        except asyncio.TimeoutError:
            print("⏰ 로그 전송 타임아웃 (5초)")
            return False
        except Exception as e:
            print(f"❌ 로그 전송 중 오류: {str(e)}")
            return False
    
    def log_conversation_background(
        self,
        session_id: str,
        user_question: str,
        contexts: List[Any],
        rag_response: str,
        model_used: str,
        response_time_ms: int,
        **kwargs
    ):
        """백그라운드에서 로그 전송 (비블로킹)"""
        
        if not self.enabled or not HTTPX_AVAILABLE:
            return
        
        async def _background_log():
            try:
                await self.log_conversation(
                    session_id=session_id,
                    user_question=user_question,
                    contexts=contexts,
                    rag_response=rag_response,
                    model_used=model_used,
                    response_time_ms=response_time_ms,
                    **kwargs
                )
            except Exception as e:
                print(f"⚠️ 백그라운드 로깅 오류: {str(e)}")
        
        # 백그라운드 태스크로 실행
        try:
            asyncio.create_task(_background_log())
        except RuntimeError:
            # 이벤트 루프가 없는 경우 스킵
            try:
                asyncio.run(_background_log())
            except Exception as e:
                print(f"⚠️ 백그라운드 로깅 실행 실패: {str(e)}")
    
    async def health_check(self) -> bool:
        """로깅 서버 헬스체크"""
        if not HTTPX_AVAILABLE:
            return False
            
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                response = await client.get(f"{self.logging_server_url}/health")
                if response.status_code == 200:
                    health_data = response.json()
                    print(f"📊 로깅 서버 상태: {health_data.get('storage', 'unknown')} - {health_data.get('total_conversations', 0)}개 대화")
                    return True
                return False
        except:
            return False


# 전역 로깅 클라이언트 인스턴스
logging_client = None

def get_logging_client() -> RAGLoggingClient:
    """로깅 클라이언트 인스턴스 반환"""
    global logging_client
    if logging_client is None:
        logging_client = RAGLoggingClient()
    return logging_client

def init_logging_client(logging_server_url: str = None):
    """로깅 클라이언트 초기화"""
    global logging_client
    logging_client = RAGLoggingClient(logging_server_url)