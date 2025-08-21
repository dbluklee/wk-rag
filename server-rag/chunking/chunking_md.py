from langchain_text_splitters import MarkdownHeaderTextSplitter
from typing import List
import os
import glob

def load_md_from_docs():
    """docs 폴더에서 마크다운 파일들을 찾기"""
    docs_path = "./docs"
    
    if not os.path.exists(docs_path):
        print("❌ docs 폴더가 없습니다.")
        return []
    
    md_files = glob.glob(os.path.join(docs_path, "*.md"))
    
    if len(md_files) == 0:
        print("❌ 마크다운 파일이 없습니다.")
        return []
    
    print(f"📁 발견된 마크다운 파일: {[os.path.basename(f) for f in md_files]}")
    return md_files

def save_markdown_chunks_to_file(chunks: List, output_file: str = "./chunking/chunks/markdown_chunks_output.txt"):
    """마크다운 청크를 파일로 저장"""
    if not chunks:
        print("⚠️ 저장할 청크가 없습니다.")
        return
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(f"마크다운 청킹 결과 - 총 {len(chunks)}개 청크\n")
            f.write("=" * 80 + "\n\n")
            
            for i, chunk in enumerate(chunks, 1):
                f.write(f"=== MARKDOWN CHUNK {i} ===\n")
                f.write(f"Source: {chunk.metadata.get('source', 'Unknown')}\n")
                
                # 헤더 정보 출력
                header1 = chunk.metadata.get('Header 1', '')
                header2 = chunk.metadata.get('Header 2', '')
                
                if header1:
                    f.write(f"Header 1: {header1}\n")
                if header2:
                    f.write(f"Header 2: {header2}\n")
                
                f.write("\nPAGE_CONTENT:\n")
                f.write(f"{chunk.page_content}\n")
                f.write("\n" + "=" * 80 + "\n\n")
        
        print(f"💾 마크다운 청크가 '{output_file}'에 저장되었습니다.")
        
    except Exception as e:
        print(f"❌ 파일 저장 오류: {e}")

def process_single_markdown_file(file_path: str) -> List:
    """단일 마크다운 파일을 청킹"""
    filename = os.path.basename(file_path)
    print(f"📖 마크다운 파일 처리: {filename}")
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            markdown_text = f.read()
    except FileNotFoundError:
        print(f"❌ 오류: '{file_path}' 파일을 찾을 수 없습니다.")
        return []
    except Exception as e:
        print(f"❌ 파일 읽기 오류: {e}")
        return []

    # 분할 기준이 될 헤더를 정의
    headers_to_split_on = [
        ("#", "Header 1"),
        ("##", "Header 2"),
    ]

    # MarkdownHeaderTextSplitter 초기화
    markdown_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=headers_to_split_on, 
        return_each_line=False
    )

    # 텍스트 분할 실행
    print(f"✂️ 마크다운 헤더 기준으로 분할 중...")
    initial_chunks = markdown_splitter.split_text(markdown_text)
    print(f"📊 초기 분할 결과: {len(initial_chunks)}개 청크")

    # 메타데이터 후처리
    processed_chunks = []
    for i, chunk in enumerate(initial_chunks):
        chunk.metadata['source'] = filename
        
        # Header 2가 있는 경우에만 feature 추가
        header2 = chunk.metadata.get('Header 2', '')
        if header2:
            new_page_content = f'\n---\nfeature: {header2}\n{chunk.page_content}'
        else:
            new_page_content = f'\n---\nfeature: Unknown\n{chunk.page_content}'
            
        chunk.page_content = new_page_content
        processed_chunks.append(chunk)

    print(f"✅ {filename}: {len(processed_chunks)}개 청크 처리 완료")
    return processed_chunks

def chunk_markdown_files() -> List:
    print(f"\n📁 마크다운 파일 청킹 시작...")
    
    # 마크다운 파일 찾기
    md_files = load_md_from_docs()
    
    if not md_files:
        print("❌ 처리할 마크다운 파일이 없습니다.")
        return []
    
    all_chunks = []
    
    # 각 마크다운 파일 처리
    for file_path in md_files:
        chunks = process_single_markdown_file(file_path)
        all_chunks.extend(chunks)
    
    print(f"✅ 총 {len(all_chunks)}개 마크다운 청크 처리 완료")
    
    # 파일로 저장
    if all_chunks:
        save_markdown_chunks_to_file(all_chunks)
    
    return all_chunks
