# server-rag/api/proxy.py
"""
LLM 서버 프록시 처리
"""
import requests
from .models import OllamaChatRequest, OllamaGenerateRequest
from .responses import create_chat_error_response, create_generate_error_response

async def proxy_chat_to_ollama(chat_handler, request: OllamaChatRequest):
    """채팅을 LLM 서버로 프록시"""
    try:
        response = requests.post(
            f"{chat_handler.llm_server_url}/api/chat",
            json=request.dict(),
            timeout=120
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            return create_chat_error_response(request.model, f"LLM server error: {response.status_code}")
            
    except requests.exceptions.Timeout:
        return create_chat_error_response(request.model, "Request timeout")
    except requests.exceptions.ConnectionError:
        return create_chat_error_response(request.model, "Connection error")
    except Exception as e:
        return create_chat_error_response(request.model, f"Proxy error: {str(e)}")

async def proxy_generate_to_ollama(chat_handler, request: OllamaGenerateRequest):
    """생성을 LLM 서버로 프록시"""
    try:
        response = requests.post(
            f"{chat_handler.llm_server_url}/api/generate",
            json=request.dict(),
            timeout=120
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            return create_generate_error_response(request.model, f"LLM server error: {response.status_code}")
            
    except requests.exceptions.Timeout:
        return create_generate_error_response(request.model, "Request timeout")
    except requests.exceptions.ConnectionError:
        return create_generate_error_response(request.model, "Connection error") 
    except Exception as e:
        return create_generate_error_response(request.model, f"Proxy error: {str(e)}")