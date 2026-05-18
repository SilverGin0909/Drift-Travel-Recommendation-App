import os
from langchain_postgres import PostgresChatMessageHistory
from psycopg_pool import AsyncConnectionPool

DB_URL = os.getenv("SUPABASE_DB_URL")

pool = AsyncConnectionPool(
    conninfo=DB_URL, 
    max_size=20,
    kwargs={
        "prepare_threshold": None
    }
)

async def get_session_history(session_id: str):
    async with pool.connection() as conn:
        return PostgresChatMessageHistory(
            "chat_history",
            session_id,
            async_connection=conn,
        )