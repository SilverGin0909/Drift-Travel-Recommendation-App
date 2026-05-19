import logging
from langchain_core.messages import HumanMessage, AIMessage
from config.config import supabase

logger = logging.getLogger(__name__)

class SupabaseSessionHistoryManager:
    """
    Manages loading and saving chat context using your 
    new relational chat_messages schema in Supabase.
    """
    def __init__(self, session_id: str):
        self.session_id = session_id

    async def aget_messages(self) -> list:
        try:
            res = supabase.table("chat_messages")\
                .select("role, content")\
                .eq("session_id", self.session_id)\
                .order("created_at", desc=False)\
                .execute()
            
            langchain_history = []
            for msg in res.data:
                if msg["role"] == "user":
                    langchain_history.append(HumanMessage(content=msg["content"]))
                elif msg["role"] == "bot":
                    langchain_history.append(AIMessage(content=msg["content"]))
            return langchain_history
        except Exception as e:
            logger.error(f"Failed to fetch session history from Supabase: {e}")
            return []

    async def aadd_messages(self, messages: list):
        try:
            session_check = supabase.table("chat_sessions")\
                .select("id")\
                .eq("id", self.session_id)\
                .execute()
            
            if not session_check.data:
                logger.info(f"Session {self.session_id} not found in database. Auto-creating parent session row...")
                
                supabase.table("chat_sessions").insert({
                    "id": self.session_id,
                    "title": "New Chat Session"
                }).execute()

            payload = []
            for msg in messages:
                role = "user" if isinstance(msg, HumanMessage) else "bot"
                payload.append({
                    "session_id": self.session_id,
                    "role": role,
                    "content": msg.content
                })
            
            if payload:
                supabase.table("chat_messages").insert(payload).execute()
                logger.info("Successfully appended messages to Supabase.")
                
        except Exception as e:
            logger.error(f"Failed to append messages to Supabase: {e}")

async def get_session_history(session_id: str):
    return SupabaseSessionHistoryManager(session_id)