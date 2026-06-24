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
from models.schemas import ChatRequest, UpdateItineraryRequest
from config.config import supabase, llm
from agent.planner import generate_structured_itinerary
from utilities.geospatial import get_closest_neighborhood

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

@app.post("/api/itinerary/update")
async def update_itinerary(request: UpdateItineraryRequest):
    try:
        session_id = request.session_id
        new_json = request.itinerary_json
        
        # Fetch the most recent messages in this session
        res = supabase.table("chat_messages")\
            .select("id, role, content")\
            .eq("session_id", session_id)\
            .order("created_at", desc=True)\
            .limit(5)\
            .execute()
        
        if not res.data:
            raise HTTPException(status_code=404, detail="No messages found in this session.")
        
        # Look for the last bot message
        target_message = None
        for msg in res.data:
            if msg["role"] == "bot":
                target_message = msg
                break
        
        if not target_message:
            raise HTTPException(status_code=404, detail="No bot message found to update.")
        
        # Update the message content
        supabase.table("chat_messages")\
            .update({"content": new_json})\
            .eq("id", target_message["id"])\
            .execute()
            
        logger.info(f"Successfully updated itinerary message {target_message['id']} for session {session_id}")
        return {"status": "ok", "message": "Itinerary updated successfully."}
        
    except Exception as e:
        logger.error(f"Error updating itinerary: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to update itinerary: {str(e)}")

async def update_session_title_from_response(session_id: str, ai_response: str):
    try:
        session_check = supabase.table("chat_sessions").select("title").eq("id", session_id).execute()
        if session_check.data:
            current_title = session_check.data[0].get("title", "")
            is_placeholder = (
                current_title.startswith("New Trip") or 
                current_title.startswith("New Chat Session") or 
                current_title in ["", None]
            )
            if is_placeholder:
                summary_prompt = (
                    f"You are a summarization tool. Summarize the topic of this travel agent's response in exactly 3 to 4 words. "
                    f"Examples: 'Batu Caves Tour', 'KL Cafe Guide', 'Budget Trip Planning'.\n"
                    f"Response: {ai_response[:600]}\n"
                    f"Title: "
                )
                summary_res = await llm.ainvoke(summary_prompt)
                content = summary_res.content
                if isinstance(content, list):
                    text_content = ""
                    for item in content:
                        if isinstance(item, dict) and "text" in item:
                            text_content += item["text"]
                        elif isinstance(item, str):
                            text_content += item
                else:
                    text_content = str(content)
                smart_title = text_content.strip().strip('"').strip("'").strip()
                
                # Truncate just in case
                if len(smart_title) > 40:
                    smart_title = f"{smart_title[:37]}..."
                
                supabase.table("chat_sessions").update({"title": smart_title}).eq("id", session_id).execute()
                logger.info(f"Upgraded session {session_id} title to: '{smart_title}' based on AI response.")
    except Exception as e:
        logger.error(f"Failed to auto-update session title: {e}")

@app.post("/api/chat")
async def chatbot_with_drift(request: ChatRequest):
    try:
        active_session_id = request.session_id
        if not active_session_id or active_session_id.strip() == "":
            active_session_id = str(uuid.uuid4())
            logger.info(f"Generated fresh session ID for new thread: {active_session_id}")
        
        # 1. Identify query intent before doing anything
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

        # 2. Intent is TRAVEL_QUERY. Check if structured itinerary planner mode is active.
        if request.is_itinerary_mode:
            logger.info("Explicit Itinerary Mode triggered. Running planner agent...")
            raw_user_message = request.message
            if request.prefs_context and request.prefs_context.strip() != "":
                prefs_context = request.prefs_context
            else:
                prefs_context = "Budget: Moderate, Style: General, Interests: Sightseeing"
            
            # Fetch the most recent message in this session to check for an existing itinerary (scanning up to 20 messages)
            existing_itinerary = None
            try:
                res = supabase.table("chat_messages")\
                    .select("role, content")\
                    .eq("session_id", active_session_id)\
                    .order("created_at", desc=True)\
                    .limit(20)\
                    .execute()
                
                if res.data:
                    for msg in res.data:
                        if msg["role"] == "bot" and msg["content"].strip().startswith('{"destination":'):
                            existing_itinerary = msg["content"]
                            logger.info("Found existing itinerary in session history. Passing to planner for context-aware updates...")
                            break
            except Exception as hist_err:
                logger.warning(f"Could not search chat history for existing itinerary: {hist_err}")

            # Generate or update the structured itinerary
            itinerary_data = await generate_structured_itinerary(raw_user_message, prefs_context, existing_itinerary)
            itinerary_str = json.dumps(itinerary_data)

            # Auto-create or save session
            dest = itinerary_data.get("destination", "KL")
            smart_title = f"Trip to {dest}"
            session_check = supabase.table("chat_sessions").select("id, title").eq("id", active_session_id).execute()
            if not session_check.data:
                supabase.table("chat_sessions").insert({
                    "id": active_session_id,
                    "user_id": request.user_id,
                    "title": smart_title
                }).execute()
            else:
                current_title = session_check.data[0].get("title", "")
                if current_title.startswith("New Chat") or current_title.startswith("New Trip") or current_title in ["", None]:
                    supabase.table("chat_sessions").update({"title": smart_title}).eq("id", active_session_id).execute()
            
            # Save to chat history
            history_manager = await get_session_history(active_session_id)
            await history_manager.aadd_messages([
                HumanMessage(content=raw_user_message),
                AIMessage(content=itinerary_str)
            ])

            async def itinerary_stream():
                yield f"data: {json.dumps({'type': 'itinerary', 'data': itinerary_data, 'session_id': active_session_id})}\n\n"
            
            return StreamingResponse(itinerary_stream(), media_type="text/event-stream")

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

            lat_val = request.user_lat if request.user_lat is not None else 3.1390
            lng_val = request.user_lng if request.user_lng is not None else 101.6869
            user_neighborhood = get_closest_neighborhood(lat_val, lng_val)

            optimization_prompt = (
                f"You are a search query optimizer for a Malaysian travel and food chatbot.\n"
                f"Convert the raw user message into a clean, natural English search query optimized for a vector database.\n\n"
                
                f"CRITICAL REAL-WORLD TEMPORAL CONTEXT:\n"
                f"- Today's Date is strictly: {current_time_str}\n\n"
                
                f"TEMPORAL CONTEXT RULES:\n"
                f"1. If the user asks for events 'recently', 'now', or 'today', they want things happening immediately. "
                "Clean the query tokens to focus on broad event types (e.g., 'concerts', 'festivals', 'shows') and strip out the words 'recently' or 'today'.\n"
                f"2. If the user follows up with 'what about future events', look at the Chat History to see what event types they were interested in. "
                "If they didn't specify a type, use broad keywords like 'festivals exhibitions concerts'. NEVER output the words 'future' or 'events' as search tokens.\n\n"
                
                f"GEOSPATIAL TELEMETRY CONTEXT:\n"
                f"- User Coordinates: Latitude: {lat_val}, Longitude: {lng_val}.\n"
                f"- User Location Name: {user_neighborhood}.\n"
                f"- If proximity is implied, resolve it to the user's location neighborhood name ('{user_neighborhood}').\n\n"
                
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

        session_check = supabase.table("chat_sessions").select("id").eq("id", active_session_id).execute()
        if not session_check.data:
            logger.info(f"Registering session {active_session_id} to chat_sessions table...")
            supabase.table("chat_sessions").insert({
                "id": active_session_id,
                "user_id": request.user_id,
                "title": "New Chat Session"
            }).execute()

        async def stream_wrapper():
            full_reply_chunks = []
            try:
                async for token in agent_with_manual_history(
                    user_message=processed_message, 
                    session_id=active_session_id, 
                    prefs_context=prefs_context,
                    user_lat=lat_val,
                    user_lng=lng_val
                ):
                    if token.startswith("__STATUS:"):
                        status_val = token.replace("__STATUS:", "").replace("__", "")
                        yield f"data: {json.dumps({'status': status_val, 'session_id': active_session_id})}\n\n"
                    else:
                        full_reply_chunks.append(token)
                        yield f"data: {json.dumps({'text': token, 'session_id': active_session_id})}\n\n"
                
                # Assembled full response
                full_reply = "".join(full_reply_chunks)
                if full_reply.strip():
                    asyncio.create_task(update_session_title_from_response(active_session_id, full_reply))
                    
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