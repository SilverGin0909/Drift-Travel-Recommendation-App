import os
import logging
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from datetime import datetime
import json
import asyncio
import uuid

from utilities.router import router_chain
from utilities.chat_history import get_session_history
from langchain_core.messages import HumanMessage, AIMessage
from database.supabase import get_user_prefs
from agent.rag import agent_with_manual_history
from models.schemas import ChatRequest
from config.config import supabase, llm

# Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def generate_smart_title(message: str, max_length: int = 30) -> str:
    """
    Cleans up the user's input message and creates a professional 
    truncated summary string to use as a database session title.
    """
    clean_message = " ".join(message.strip().split())
    
    if len(clean_message) <= max_length:
        return clean_message
        
    return f"{clean_message[:max_length].strip()}..."

app = FastAPI(title="Drift AI Backend")

# Middleware for Flutter connection[cite: 1]
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/api/chat")
async def chatbot_with_drift(request: ChatRequest):
    try:
        active_session_id = request.session_id
        if not active_session_id or active_session_id.strip() == "":
            active_session_id = str(uuid.uuid4())
            logger.info(f"Generated fresh session ID for new thread: {active_session_id}")
        
        router_task = asyncio.create_task(router_chain.ainvoke({"input": request.message}))
        route = await router_task

        if route.get("intent") in ["GREETING", "OFF_TOPIC"]:
            logger.info(f"Router identified {route.get('intent')}. Exiting early.")
            
            if route.get("intent") == "GREETING":
                reply = route.get("direct_response") or "Hi there! I'm Drift. How can I help you explore KL today?"
            else:
                reply = "I'm Drift! I specialize in KL travel. How can I help you with your trip?"
            
            session_check = supabase.table("chat_sessions").select("id").eq("id", active_session_id).execute()
            if not session_check.data:
                logger.info(f"Registering new greeting thread {active_session_id} with placeholder title...")
                supabase.table("chat_sessions").insert({
                    "id": active_session_id,
                    "user_id": request.user_id,
                    "title": "New Chat Session"
                }).execute()

            history_manager = await get_session_history(active_session_id)
            await history_manager.aadd_messages([
                HumanMessage(content=request.message),
                AIMessage(content=reply)
            ])

            async def quick_stream():
                yield f"data: {json.dumps({'text': reply, 'session_id': active_session_id})}\n\n"
                
            return StreamingResponse(quick_stream(), media_type="text/event-stream")

        logger.info("Router identified TRAVEL_QUERY. Preparing main agent...")

        raw_user_message = request.message
        logger.info(f"Processing raw user message for search layer: '{raw_user_message}'")

        history_context = ""
        try:
            history_manager = await get_session_history(active_session_id)
            past_messages = await history_manager.aget_messages()
            if past_messages:
                recent_turns = past_messages[-3:]
                history_chunks = []
                for msg in recent_turns:
                    role = "User" if msg.__class__.__name__ == "HumanMessage" else "Assistant"
                    history_chunks.append(f"{role}: {msg.content}")
                history_context = "\n".join(history_chunks)
        except Exception as hist_err:
            logger.warning(f"Could not load history for optimizer context: {str(hist_err)}")
        
        try:
            current_time_str = datetime.now().strftime("%A, %B %d, %Y (Time: %H:%M)")
            
            pure_text_llm = llm.bind(tools=[])

            optimization_prompt = (
                f"You are a search query optimizer for a Malaysian travel and food chatbot.\n"
                f"Convert the raw user message into a clean, natural English search query optimized for a vector database.\n\n"
                
                f"CRITICAL REAL-WORLD TEMPORAL CONTEXT:\n"
                f"- Today's Date is strictly: {current_time_str}\n\n"
                
                f"TEMPORAL CONTEXT RULES:\n"
                f"1. If the user asks for events 'recently', 'now', or 'today', they want things happening immediately. Clean the query tokens to focus on broad event types (e.g., 'concerts', 'festivals', 'shows') and strip out the words 'recently' or 'today'.\n"
                f"2. If the user follows up with 'what about future events', look at the Chat History to see what event types they were interested in. If they didn't specify a type, use broad keywords like 'festivals exhibitions concerts'. NEVER output the words 'future' or 'events' as search tokens.\n\n"
                
                f"GEOSPATIAL TELEMETRY CONTEXT:\n"
                f"- User Coordinates: Latitude: {request.latitude}, Longitude: {request.longitude}.\n"
                f"- If proximity is implied, resolve it to a neighborhood name (e.g., 'Bukit Bintang', 'Cyberjaya').\n\n"
                
                f"Chat History Context:\n{history_context or 'No prior history'}\n\n"
                f"New Raw User Message: {raw_user_message}\n\n"
                f"Return ONLY the final optimized English search query tokens. Do not include quotes, explanations, or markdown labels."
            )
            
            translation_response = await pure_text_llm.ainvoke(optimization_prompt)
            content = translation_response.content

            if isinstance(content, list):
                search_query = ""
                for item in content:
                    if isinstance(item, dict) and "text" in item:
                        search_query += item["text"]
                    elif isinstance(item, str):
                        search_query += item
            else:
                search_query = str(content)
            
            search_query = search_query.strip().strip('"').strip("'")

            logger.info(f"Search Alignment Success: '{raw_user_message}' -> '{search_query}'")
            processed_message = search_query

        except Exception as err:
            logger.error(f"Query optimization pipeline anomaly: {str(err)}. Falling back to raw message.")
            processed_message = raw_user_message

        if request.prefs_context and request.prefs_context.strip() != "":
            prefs_context = request.prefs_context
            logger.info(f"NATIVE PREFS CAPTURED FROM FLUTTER PAYLOAD: {prefs_context}")
        else:
            prefs_context = "Budget: Moderate, Style: General, Interests: Sightseeing"
            logger.info(f"No mobile prefs transmitted. Using default fallback: {prefs_context}")

        smart_title = generate_smart_title(request.message, max_length=30)

        session_check = supabase.table("chat_sessions").select("id").eq("id", active_session_id).execute()
        if not session_check.data:
            logger.info(f"Registering session {active_session_id} to chat_sessions table...")
            supabase.table("chat_sessions").insert({
                "id": active_session_id,
                "user_id": request.user_id,
                "title": smart_title
            }).execute()
        else:
            current_title = session_check.data[0].get("title", "")
            is_placeholder = (
                current_title.startswith("New Trip") or 
                current_title.startswith("New Chat Session") or 
                current_title in ["", None]
            )
            
            if is_placeholder:
                logger.info(f"Upgrading placeholder title for session {active_session_id} to: '{smart_title}'")
                supabase.table("chat_sessions").update({
                    "title": smart_title
                }).eq("id", active_session_id).execute()

        async def stream_wrapper():
            try:
                async for token in agent_with_manual_history(
                    user_message=processed_message, 
                    session_id=active_session_id, 
                    prefs_context=prefs_context,
                    user_lat=request.user_lat,
                    user_lng=request.user_lng
                ):
                    yield f"data: {json.dumps({'text': token, 'session_id': active_session_id})}\n\n"
            except Exception as e:
                logger.error(f"Stream interrupted: {e}")
                yield f"data: {json.dumps({'error': 'stream_interrupted'})}\n\n"

        return StreamingResponse(stream_wrapper(), media_type="text/event-stream")
    
    except Exception as e:
        print(f"Detailed Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal Server Error")

@app.get("/")
async def health_check():
    return {"status": "ok", "message": "Drift API is live."}