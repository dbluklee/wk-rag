# server-rag/api/streaming.py
"""
스트리밍 응답 처리
"""
import json
import time
import asyncio
from typing import AsyncGenerator

async def rag_chat_stream(chat_handler, question: str, model: str) -> AsyncGenerator[str, None]:
    """RAG 채팅 스트리밍"""
    try:
        response_content = await chat_handler.process_with_rag(question)
        
        # 단어별 분할 스트리밍
        words = response_content.split()
        chunk_size = 2
        
        for i in range(0, len(words), chunk_size):
            chunk_words = words[i:i+chunk_size]
            chunk = " ".join(chunk_words)
            if i + chunk_size < len(words):
                chunk += " "
            
            chunk_response = {
                "model": model,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                "message": {
                    "role": "assistant",
                    "content": chunk
                },
                "done": False
            }
            
            yield json.dumps(chunk_response) + "\n"
            await asyncio.sleep(0.03)
        
        # 종료 응답
        final_response = {
            "model": model,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "message": {
                "role": "assistant",
                "content": ""
            },
            "done": True,
            "total_duration": 1000000000,
            "load_duration": 100000000,
            "prompt_eval_count": len(question.split()),
            "prompt_eval_duration": 200000000,
            "eval_count": len(response_content.split()),
            "eval_duration": 500000000
        }
        
        yield json.dumps(final_response) + "\n"
        
    except Exception as e:
        print(f"❌ [STREAM] 오류: {str(e)}")
        error_response = {
            "model": model,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "message": {
                "role": "assistant",
                "content": f"Error: {str(e)}"
            },
            "done": True
        }
        yield json.dumps(error_response) + "\n"

async def rag_generate_stream(chat_handler, prompt: str, model: str) -> AsyncGenerator[str, None]:
    """RAG 생성 스트리밍"""
    try:
        response_content = await chat_handler.process_with_rag(prompt)
        
        words = response_content.split()
        chunk_size = 2
        
        for i in range(0, len(words), chunk_size):
            chunk_words = words[i:i+chunk_size]
            chunk = " ".join(chunk_words)
            if i + chunk_size < len(words):
                chunk += " "
            
            chunk_response = {
                "model": model,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                "response": chunk,
                "done": False
            }
            
            yield json.dumps(chunk_response) + "\n"
            await asyncio.sleep(0.03)
        
        # 종료 응답
        final_response = {
            "model": model,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "response": "",
            "done": True,
            "context": [],
            "total_duration": 1000000000,
            "load_duration": 100000000,
            "prompt_eval_count": len(prompt.split()),
            "prompt_eval_duration": 200000000,
            "eval_count": len(response_content.split()),
            "eval_duration": 500000000
        }
        
        yield json.dumps(final_response) + "\n"
        
    except Exception as e:
        print(f"❌ [STREAM] 오류: {str(e)}")
        error_response = {
            "model": model,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "response": f"Error: {str(e)}",
            "done": True
        }
        yield json.dumps(error_response) + "\n"