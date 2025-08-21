# server-rag/api/responses.py
"""
Ollama API 호환 응답 생성 유틸리티
"""
import time
from typing import Dict, Any

def create_chat_response(model: str, content: str, done: bool = True) -> Dict[str, Any]:
    """Ollama 채팅 응답 생성"""
    return {
        "model": model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "message": {
            "role": "assistant",
            "content": content
        },
        "done": done,
        "total_duration": 1000000000,
        "load_duration": 100000000,
        "prompt_eval_count": 10,
        "prompt_eval_duration": 200000000,
        "eval_count": len(content.split()),
        "eval_duration": 500000000
    }

def create_generate_response(model: str, content: str, done: bool = True) -> Dict[str, Any]:
    """Ollama 생성 응답 생성"""
    return {
        "model": model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "response": content,
        "done": done,
        "context": [],
        "total_duration": 1000000000,
        "load_duration": 100000000,
        "prompt_eval_count": 10,
        "prompt_eval_duration": 200000000,
        "eval_count": len(content.split()),
        "eval_duration": 500000000
    }

def create_chat_error_response(model: str, error: str) -> Dict[str, Any]:
    """채팅 에러 응답"""
    return {
        "model": model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "message": {
            "role": "assistant",
            "content": f"Error: {error}"
        },
        "done": True
    }

def create_generate_error_response(model: str, error: str) -> Dict[str, Any]:
    """생성 에러 응답"""
    return {
        "model": model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "response": f"Error: {error}",
        "done": True
    }