# server-rag/api/router.py
"""
FastAPI 라우터 정의 - OpenWebUI 호환성 개선
"""
import os
import time
from fastapi import APIRouter
from .models import OllamaChatRequest, OllamaGenerateRequest
from .endpoints import (
    handle_chat_request, handle_generate_request,
    get_model_list, get_health_status, get_chat_handler
)

router = APIRouter()

# ================================
# 핵심 채팅/생성 API
# ================================

@router.post("/api/chat")
async def chat_ollama(request: OllamaChatRequest):
    """Ollama 채팅 API"""
    return await handle_chat_request(request)

@router.post("/api/generate")
async def generate_ollama(request: OllamaGenerateRequest):
    """Ollama 생성 API"""
    return await handle_generate_request(request)

# ================================
# 모델 관리 API (OpenWebUI 필수)
# ================================

@router.get("/api/tags")
async def list_local_models():
    """로컬 모델 목록"""
    return get_model_list()

@router.get("/api/models")
async def list_models_alt():
    """모델 목록 API (/api/tags의 별칭)"""
    return get_model_list()

@router.get("/api/ps")
async def list_running_models():
    """실행 중인 모델 목록"""
    try:
        models = get_model_list()["models"]
        
        # ps용 형식으로 변환
        running_models = []
        for model in models:
            running_models.append({
                **model,
                "expires_at": "2024-12-01T23:59:59.999999999Z",
                "size_vram": 2147483648
            })
        
        return {"models": running_models}
    except Exception as e:
        print(f"❌ 실행 모델 목록 오류: {str(e)}")
        return {"models": []}

@router.get("/api/version")
async def get_version():
    """Ollama 버전 정보 API"""
    return {
        "version": "0.1.16"  # OpenWebUI가 요구하는 최소 버전
    }

@router.get("/api/show")
async def show_model(name: str = None):
    """모델 상세 정보 API (기본 프롬프트 포함)"""
    if not name:
        return {"error": "model name required"}
    
    rag_model_name = os.environ["RAG_MODEL_NAME"]
    
    if name == rag_model_name:
        # 현재 시스템 프롬프트 가져오기
        try:
            handler = get_chat_handler()
            current_system_prompt = handler.get_system_prompt()
        except:
            current_system_prompt = "You are a professional sales consultant at a Samsung store."
        
        return {
            "modelfile": f"FROM {rag_model_name}",
            "parameters": {
                "temperature": 0.7,
                "top_k": 40,
                "top_p": 0.9
            },
            "template": "{{ .System }}{{ .Prompt }}",
            "system": current_system_prompt,  # OpenWebUI에서 표시될 기본값
            "details": {
                "parent_model": "",
                "format": "gguf",
                "family": "rag-enhanced",
                "families": ["rag-enhanced"],
                "parameter_size": "RAG+27B",
                "quantization_level": "Q4_K_M"
            }
        }
    else:
        return {"error": f"model '{name}' not found. Only '{rag_model_name}' is available on this RAG server."}

# ================================
# 시스템 프롬프트 관리 API
# ================================

@router.get("/api/system-prompt")
async def get_system_prompt():
    """현재 시스템 프롬프트 조회"""
    try:
        handler = get_chat_handler()
        current_prompt = handler.get_system_prompt()
        
        return {
            "status": "success",
            "prompt": current_prompt
        }
    except Exception as e:
        return {"error": f"Failed to get system prompt: {str(e)}"}

@router.post("/api/system-prompt")
async def update_system_prompt(request: dict):
    """시스템 프롬프트 변경 (OpenWebUI 호환)"""
    try:
        new_prompt = request.get("prompt", "")
        if not new_prompt:
            return {"error": "No prompt provided"}
        
        handler = get_chat_handler()
        old_prompt = handler.get_system_prompt()
        
        # 시스템 프롬프트 업데이트
        success = handler.update_system_prompt(new_prompt)
        
        if success:
            return {
                "status": "success",
                "message": "System prompt updated successfully",
                "old_prompt": old_prompt,
                "new_prompt": new_prompt
            }
        else:
            return {"error": "Failed to update system prompt"}
        
    except Exception as e:
        return {"error": f"Failed to update system prompt: {str(e)}"}

@router.post("/api/system-prompt/reset")
async def reset_system_prompt():
    """기본 프롬프트로 리셋"""
    try:
        handler = get_chat_handler()
        old_prompt = handler.get_system_prompt()
        
        success = handler.reset_to_default()
        
        if success:
            return {
                "status": "success",
                "message": "System prompt reset to default",
                "old_prompt": old_prompt,
                "new_prompt": handler.get_system_prompt()
            }
        else:
            return {"error": "Failed to reset system prompt"}
        
    except Exception as e:
        return {"error": f"Failed to reset system prompt: {str(e)}"}

# ================================
# 상태 및 정보 API
# ================================

@router.get("/health")
async def health_check():
    """헬스체크"""
    try:
        return get_health_status()
    except Exception as e:
        return {
            "status": "unhealthy",
            "service": "cheeseade-rag-server", 
            "timestamp": int(time.time()),
            "error": str(e)
        }

@router.get("/api")
async def api_info():
    """API 정보"""
    rag_model_name = os.environ.get("RAG_MODEL_NAME", "rag-cheeseade:latest")
    
    return {
        "message": "CHEESEADE RAG Server",
        "version": "1.0.0",
        "ollama_compatible": True,
        "supported_model": rag_model_name,
        "model_count": 1,
        "endpoints": [
            "/api/tags", "/api/models", "/api/ps", "/api/version",
            "/api/show", "/api/chat", "/api/generate",
            "/api/system-prompt", "/health"
        ]
    }

@router.get("/")
async def root():
    """루트 엔드포인트"""
    return "Ollama is running"