from langchain_core.vectorstores import VectorStoreRetriever
from langchain.vectorstores.base import VectorStore
from typing import List

def get_retriever(
    vertor_db: VectorStore,
    retriever_type: str = 'top_k'
    ) -> VectorStoreRetriever:

    if retriever_type == 'top_k':
        retriever = vertor_db.as_retriever(
            search_type="similarity",
            search_kwargs={"k": 4}
            )

    elif retriever_type == 'threshold':
        retriever = vertor_db.as_retriever(
            search_type="similarity_score_threshold",
            search_kwargs={"score_threshold": 0.2}
            )

    elif retriever_type == 'mmr':
        retriever = vertor_db.as_retriever(
            search_type="mmr",
            search_kwargs={'k': 4, 'fetch_k': 20}
            )

    else:
        retriever = vector_db.as_retriever(
            search_kwargs={'k': 4}
            )

    print(f"\n✅ '{retriever_type}' 타입 retriever를 생성했습니다.\n")
    return retriever


