import csv
import os
import glob
from typing import List

class CSVChunk:
    """CSV 청크 객체 (LangChain Document와 유사한 구조)"""
    def __init__(self, page_content: str, metadata: dict):
        self.page_content = page_content
        self.metadata = metadata

def load_csv_from_docs():
    """docs 폴더에서 CSV 파일들을 로드"""
    docs_path = "./docs"
    
    if not os.path.exists(docs_path):
        print("❌ docs 폴더가 없습니다.")
        return None
    
    csv_files = glob.glob(os.path.join(docs_path, "*.csv"))
    
    if len(csv_files) == 0:
        print("❌ CSV 파일이 없습니다.")
        return None
    
    print(f"📁 발견된 CSV 파일: {[os.path.basename(f) for f in csv_files]}")
    
    all_data = []
    
    for filename in csv_files:
        data = []
        
        # UTF-8 BOM 제거를 위해 utf-8-sig 사용
        with open(filename, 'r', encoding='utf-8-sig') as file:
            reader = csv.DictReader(file)
            
            if not reader.fieldnames:
                print(f"⚠️ 경고: {filename}에 헤더가 없습니다.")
                continue
            
            for row in reader:
                # 키 이름의 BOM 및 공백 제거
                cleaned_row = {}
                for key, value in row.items():
                    cleaned_key = key.replace('\ufeff', '').strip() if key else key
                    cleaned_row[cleaned_key] = value
                
                data.append(cleaned_row)
        
        if len(data) > 0:
            all_data.append({
                'filename': os.path.basename(filename),
                'data': data,
                'rows': len(data)
            })
            print(f"📊 {os.path.basename(filename)}: {len(data)}행 로드")
    
    if len(all_data) == 0:
        print("❌ CSV 파일이 없습니다.")
        return None
    
    return all_data

def chunk_csv_files(csv_data_list: List) -> List[CSVChunk]:
    """
    CSV 데이터를 행 기준으로 청킹
    각 행을 헤더(메타데이터)와 page_content(주요 내용)로 분리
    """
    if not csv_data_list:
        print("❌ CSV 데이터가 없습니다.")
        return []
    
    chunks = []
    
    for file_data in csv_data_list:
        filename = file_data['filename']
        data = file_data['data']
        
        print(f"\n📖 CSV 파일 처리: {filename}")
        print(f"✂️ 행 기준으로 청킹 중...")
        
        processed_count = 0
        
        for idx, row in enumerate(data):
            # Space Name이 '내 업무 리스트' 또는 '이사회'인 경우 스킵
            space_name = row.get('Space Name', '')
            if space_name in ['내 업무 리스트', '이사회']:
                continue
            
            # 헤더 (메타데이터) 구성
            header_parts = []
            header_parts.append(f"Source: {filename}")
            
            task_id = row.get('Task ID', '')
            if task_id and str(task_id).strip():
                header_parts.append(f"TaskID: {task_id}")
            
            if row.get('Parent ID'):
                header_parts.append(f"ParentID: {row['Parent ID']}")
            if row.get('Tags'):
                header_parts.append(f"Tags: {row['Tags']}")
            if row.get('List Name'):
                header_parts.append(f"ListName: {row['List Name']}")
            if row.get('Folder Name'):
                header_parts.append(f"FolderName: {row['Folder Name']}")
            if row.get('Space Name'):
                header_parts.append(f"SpaceName: {row['Space Name']}")
            if row.get('Comments'):
                header_parts.append(f"Comments: {row['Comments']}")
            if row.get('Date Created Text'):
                header_parts.append(f"DateCreated: {row['Date Created Text']}")
            
            header = ", ".join(header_parts)
            
            # Page Content (주요 내용) 구성 - 헤더 정보도 포함하여 검색 가능하게 함
            content_parts = []
            
            # 1. 헤더 정보 (검색 가능하도록 page_content에 포함)
            content_parts.append("=== 작업 정보 ===")
            
            if task_id and str(task_id).strip():
                content_parts.append(f"작업ID: {task_id}")
            
            task_name = row.get('Task Name', '')
            if task_name and str(task_name).strip():
                content_parts.append(f"작업명: {task_name.strip()}")
            
            parent_id = row.get('Parent ID', '')
            if parent_id and str(parent_id).strip() and parent_id != 'null':
                content_parts.append(f"상위작업ID: {parent_id}")
            
            list_name = row.get('List Name', '')
            if list_name:
                content_parts.append(f"리스트: {list_name}")
            
            folder_name = row.get('Folder Name', '')
            if folder_name:
                content_parts.append(f"폴더: {folder_name}")
            
            space_name = row.get('Space Name', '')
            if space_name:
                content_parts.append(f"스페이스: {space_name}")
            
            tags = row.get('Tags', '')
            if tags and tags != '[]':
                content_parts.append(f"태그: {tags}")
            
            assignees = row.get('Assignees', '')
            if assignees and assignees != '[]':
                content_parts.append(f"담당자: {assignees}")
            
            date_created = row.get('Date Created Text', '')
            if date_created and str(date_created).strip():
                content_parts.append(f"생성일: {date_created}")
            
            # 2. 작업 내용
            if row.get('Task Content'):
                content_parts.append("")
                content_parts.append("=== 작업 내용 ===")
                content_parts.append(row['Task Content'])
            
            # 3. 댓글 정보
            comments = row.get('Comments', '')
            if comments and comments != '[]':
                content_parts.append("")
                content_parts.append("=== 댓글 ===")
                content_parts.append(f"댓글: {comments}")
            
            page_content = "\n".join(content_parts)
            
            # 메타데이터 구성
            metadata = {
                'source': filename,
                'chunk_id': f"{filename}_{processed_count+1}",
                'row_number': idx + 1,
                'task_id': task_id,
                'task_name': task_name.strip() if task_name else '',
                'list_name': row.get('List Name', ''),
                'folder_name': row.get('Folder Name', ''),
                'space_name': row.get('Space Name', ''),
                'date_created': row.get('Date Created Text', ''),
                'header': header
            }
            
            # CSVChunk 객체 생성
            chunk = CSVChunk(page_content=page_content, metadata=metadata)
            chunks.append(chunk)
            processed_count += 1
        
        print(f"📊 {filename}: {processed_count}개 청크 생성 (총 {len(data)}행 중 {len(data) - processed_count}행 필터링됨)")
    
    print(f"\n✅ 총 {len(chunks)}개 CSV 청크 처리 완료")
    return chunks

def save_csv_chunks_to_file(chunks: List[CSVChunk], output_file: str = "./chunking/chunks/csv_chunks_output.txt"):
    """CSV 청크를 파일로 저장"""
    if not chunks:
        print("⚠️ 저장할 청크가 없습니다.")
        return
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(f"CSV 청킹 결과 - 총 {len(chunks)}개 청크\n")
            f.write("=" * 80 + "\n\n")
            
            for i, chunk in enumerate(chunks, 1):
                f.write(f"=== CSV CHUNK {i}: {chunk.metadata['chunk_id']} ===\n")
                f.write(f"Source: {chunk.metadata['source']} (Row {chunk.metadata['row_number']})\n")
                f.write(f"Task ID: {chunk.metadata['task_id']}\n")
                f.write(f"Task Name: {chunk.metadata['task_name']}\n")
                f.write(f"List Name: {chunk.metadata['list_name']}\n")
                f.write(f"Folder Name: {chunk.metadata['folder_name']}\n")
                f.write(f"Space Name: {chunk.metadata['space_name']}\n")
                f.write(f"Date Created: {chunk.metadata['date_created']}\n\n")
                
                f.write("HEADER:\n")
                f.write(f"{chunk.metadata['header']}\n\n")
                
                f.write("PAGE_CONTENT:\n")
                f.write(f"{chunk.page_content}\n")
                f.write("\n" + "=" * 80 + "\n\n")
        
        print(f"💾 CSV 청크가 '{output_file}'에 저장되었습니다.")
        
    except Exception as e:
        print(f"❌ 파일 저장 오류: {e}")

def chunk_csv_file(file_path: str = None) -> List[CSVChunk]:
    """
    Main.py에서 호출할 수 있는 메인 함수
    """
    print(f"\n📁 CSV 파일 청킹 시작...")
    
    # CSV 파일 로드
    csv_data = load_csv_from_docs()
    
    if not csv_data:
        print("❌ CSV 데이터를 로드할 수 없습니다.")
        return []
    
    # 청킹 수행
    chunks = chunk_csv_files(csv_data)
    
    # 파일로 저장
    if chunks:
        save_csv_chunks_to_file(chunks)
    
    return chunks