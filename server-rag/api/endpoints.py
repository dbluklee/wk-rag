# server-rag/api/endpoints.py
"""
API 엔드포인트 정의 - RAG 모델만 제공하도록 수정
"""
import os
import time
from typing import Dict, Any
from fastapi import HTTPException
from fastapi.responses import StreamingResponse

from .models import OllamaChatRequest, OllamaGenerateRequest
from .responses import (
    create_chat_response, create_generate_response,
    create_chat_error_response, create_generate_error_response
)
from .streaming import rag_chat_stream, rag_generate_stream

# 전역 채팅 핸들러
chat_handler = None

def set_chat_handler(handler):
    """채팅 핸들러 설정"""
    global chat_handler
    chat_handler = handler
    print(f"✅ 채팅 핸들러 설정 완료")

def get_chat_handler():
    """채팅 핸들러 가져오기"""
    if not chat_handler:
        raise HTTPException(status_code=503, detail="Chat handler not initialized")
    return chat_handler

async def handle_chat_request(request: OllamaChatRequest):
    """채팅 요청 처리 - RAG 모델만 지원하고 로깅"""
    handler = get_chat_handler()
    
    # 사용자 메시지 추출
    user_message = next((msg for msg in reversed(request.messages) if msg.role == "user"), None)
    if not user_message:
        raise HTTPException(status_code=400, detail="No user message found")
    
    question = user_message.content
    
    try:
        # RAG 모델인 경우만 RAG 처리 + 로깅
        if request.model == handler.rag_model_name:
            if request.stream:
                return StreamingResponse(
                    rag_chat_stream(handler, question, request.model),
                    media_type="application/x-ndjson"
                )
            else:
                # RAG 처리 (로깅 포함)
                response_content = await handler.process_with_rag(question)
                return create_chat_response(request.model, response_content)
        else:
            # 일반 LLM 모델인 경우: 프록시만 하고 로깅 안함
            print(f"🔄 일반 LLM 모델 프록시 (로깅 안함): {request.model}")
            
            # LLM 서버로 직접 프록시 (로깅 없음)
            import requests
            try:
                response = requests.post(
                    f"{handler.llm_server_url}/api/chat",
                    json=request.dict(),
                    timeout=120
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    return create_chat_error_response(
                        request.model, 
                        f"LLM server error: {response.status_code}"
                    )
            except Exception as e:
                return create_chat_error_response(
                    request.model, 
                    f"Proxy error: {str(e)}"
                )
            
    except Exception as e:
        print(f"❌ 채팅 처리 오류: {str(e)}")
        return create_chat_error_response(request.model, str(e))

async def handle_generate_request(request: OllamaGenerateRequest):
    """생성 요청 처리 - RAG 모델만 지원"""
    handler = get_chat_handler()
    
    try:
        # RAG 모델만 지원
        if request.model == handler.rag_model_name:
            if request.stream:
                return StreamingResponse(
                    rag_generate_stream(handler, request.prompt, request.model),
                    media_type="application/x-ndjson"
                )
            else:
                response_content = await handler.process_with_rag(request.prompt)
                return create_generate_response(request.model, response_content)
        else:
            # RAG 모델이 아닌 경우 오류 응답
            return create_generate_error_response(
                request.model,
                f"Model '{request.model}' not supported. Only '{handler.rag_model_name}' is available on this RAG server."
            )
            
    except Exception as e:
        print(f"❌ 생성 처리 오류: {str(e)}")
        return create_generate_error_response(request.model, str(e))

def get_model_list() -> Dict[str, Any]:
    """모델 목록 생성 - RAG 모델만 제공"""
    rag_model_name = os.environ.get("RAG_MODEL_NAME", "rag-cheeseade:latest")
    
    # RAG 모델만 포함
    models = [
        {
            "name": rag_model_name,
            "model": rag_model_name,
            "modified_at": "2024-12-01T00:00:00.000000000Z",
            "size": 2500000000,
            "digest": f"sha256:{abs(hash(rag_model_name)):064x}",
            "details": {
                "parent_model": "",
                "format": "gguf",
                "family": "rag-enhanced",
                "families": ["rag-enhanced"],
                "parameter_size": "RAG+27B",
                "quantization_level": "Q4_K_M"
            }
        }
    ]
    
    return {"models": models}

def get_health_status() -> Dict[str, Any]:
    """헬스체크 상태 생성"""
    handler_status = "initialized" if chat_handler else "not_initialized"
    rag_model = os.environ.get("RAG_MODEL_NAME", "unknown")
    
    return {
        "status": "healthy" if chat_handler else "degraded",
        "service": "cheeseade-rag-server",
        "timestamp": int(time.time()),
        "chat_handler": handler_status,
        "models": {
            "rag_model": rag_model,
            "supported_models": [rag_model],
            "total_models": 1
        }
    }