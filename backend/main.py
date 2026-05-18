import os
import logging
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
import json
import asyncio
from utilities.router import router_chain
from database.supabase import get_user_prefs
from agent.rag import agent_with_manual_history
from models.schemas import ChatRequest, ChatResponse

# Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

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
        router_task = asyncio.create_task(router_chain.ainvoke({"input": request.message}))
        prefs_task = asyncio.create_task(asyncio.to_thread(get_user_prefs, request.user_id))

        route = await router_task

        if route.get("intent") in ["GREETING", "OFF_TOPIC"]:
            logger.info(f"Router identified {route.get('intent')}. Exiting early.")
            
            if route.get("intent") == "GREETING":
                reply = route.get("direct_response") or "Hi there! I'm Drift. How can I help you explore KL today?"
            else:
                reply = "I'm Drift! I specialize in KL travel. How can I help you with your trip?"
            
            # Wrap the fast response in the SSE format Flutter expects
            async def quick_stream():
                yield f"data: {json.dumps({'text': reply})}\n\n"
                
            return StreamingResponse(quick_stream(), media_type="text/event-stream")

        logger.info("Router identified TRAVEL_QUERY. Preparing main agent...")

        prefs = await prefs_task

        prefs_context = (
            f"Budget: {prefs.get('budget', 'Moderate')}, "
            f"Style: {prefs.get('style', 'Explorer')}, "
            f"Interests: {prefs.get('interest', 'General')}"
        )
        logger.info(f"PREFS LOADED: {prefs_context}")

        enriched_message = (
            f"User Message: {request.message}\n"
            f"(System Note: The user is currently at Lat: {request.user_lat}, Lng: {request.user_lng}.)"
        )

        async def stream_wrapper():
            try:
                async for token in agent_with_manual_history(enriched_message, request.user_id, prefs_context):
                    yield f"data: {json.dumps({'text': token})}\n\n"
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