import os
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

from database.supabase import get_user_prefs
from agent.rag import agent_with_memory
from models.schemas import ChatRequest, ChatResponse
from utilities.bouncer import bouncer_chain

load_dotenv()

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

@app.post("/api/chat", response_model=ChatResponse)
async def chatbot_with_drift(request: ChatRequest):
    try:
        logger.info("\n" + "="*40)
        logger.info("INCOMING FLUTTER REQUEST")
        logger.info("="*40)
        logger.info(f"USER ID: {request.user_id}")
        logger.info(f"MESSAGE: {request.message}")

        logger.info("Running Bouncer check...")
        intent = bouncer_chain.invoke({"input": request.message})

        if not intent.is_travel_related:
            return {
                "reply": "I'm Drift, your Kuala Lumpur travel assistent! I'd love to help you plan your trip, but I cannot assist with that topic."
            }

        logger.info("Bouncer passed. Running main agent...")
        logger.info(f"LATITUDE: {request.user_lat}")
        logger.info(f"LONGITUDE: {request.user_lng}")

        logger.info(f"Fetching user preferenes...")
        prefs = get_user_prefs(request.user_id)
        prefs_context = f"Budget: {prefs.get('budget')}, Style: {prefs.get('style')}, Interests: {prefs.get('interest')}"
        logger.info(f"PREFS LOADED: {prefs_context}")

        lat = request.user_lat
        lng = request.user_lng

        current_location = f"Latitude: {lat}, Longitude: {lng}"

        enriched_message = (
            f"User Message: {request.message}\n"
            f"(System Note: The user is currently at Lat: {lat}, Lng: {lng}. "
            f"Use these coordinates for any nearby searches.)"
        )
        
        logger.info(f"Passing to Drift Agent...")

        response = agent_with_memory.invoke(
            {
                "input": enriched_message, 
                "user_preferences": prefs_context,
            },
            config={
                "configurable": {"session_id": request.user_id}
            }
        )

        raw_output = response["output"] if isinstance(response, dict) else response

        if isinstance(raw_output, list):
            final_reply = raw_output[0].get("text", str(raw_output))
        elif isinstance(raw_output, dict):
            final_reply = raw_output.get("text", str(raw_output))
        else:
            final_reply = str(raw_output)

        logger.info(f"SENDING REPLY: {final_reply}")
        return ChatResponse(reply=final_reply)
    
    except Exception as e:
        print(f"Detailed Error: {e}")
        raise HTTPException(status_code=500, detail="Internal Server Error")

@app.get("/")
def health_check():
    return {"status": "ok", "message": "Drift API is live."}