# server-rag/api/models.py
"""
Ollama API 호환 데이터 모델
"""
from typing import Optional, List, Dict, Any
from pydantic import BaseModel

class OllamaMessage(BaseModel):
    role: str  # "system", "user", "assistant"
    content: str
    images: Optional[List[str]] = None

class OllamaChatRequest(BaseModel):
    model: str
    messages: List[OllamaMessage]
    stream: Optional[bool] = False
    options: Optional[Dict[str, Any]] = None

class OllamaGenerateRequest(BaseModel):
    model: str
    prompt: str
    stream: Optional[bool] = False
    options: Optional[Dict[str, Any]] = None
    system: Optional[str] = None

class OllamaModel(BaseModel):
    name: str
    model: str
    modified_at: str
    size: int
    digest: str
    details: Dict[str, Any]

class OllamaModelList(BaseModel):
    models: List[OllamaModel]

class OllamaRunningModel(BaseModel):
    name: str
    model: str
    size: int
    digest: str
    details: Dict[str, Any]
    expires_at: str
    size_vram: int

class OllamaRunningModelList(BaseModel):
    models: List[OllamaRunningModel]