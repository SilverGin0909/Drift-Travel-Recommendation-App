import logging
from langchain_core.messages import HumanMessage, AIMessage
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent
from langchain.tools import tool
from langchain_core.runnables.history import RunnableWithMessageHistory
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_community.tools import DuckDuckGoSearchRun

from config.config import llm, supabase, embeddings
from utilities.chat_history import get_session_history

# 1. Logging to watch the agent's internal thought process
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@tool
def get_restaurant_reviews(restaurant_name: str):
    """
    Finds food recommendations and reviews for a specific restaurant.
    Uses TripAdvisor snippets to find what people recommend ordering.
    """
    search = DuckDuckGoSearchRun()
    query = f"site:tripadvisor.com.my Food recommend at {restaurant_name}"
    return search.run(query)

@tool
def kl_destinations_search(query: str, user_lat: float, user_lng: float, category: str = None):
    """
    Search the travel database for destinations.
    - query: Search term (e.g., 'Arabic food').
    - You MUST provide the user_lat and user_lng values provided in the system note.
    - category: 'Food', 'Attraction', 'Wellness'.
    - When a user asks for a specific cuisine, identify similar sub-categories to provide a diverse range of options.
    """

    logger.info(f"TOOL CALL - Lat: {user_lat}, Lng: {user_lng}")

    try:
        query_vector = embeddings.embed_query(query)

        res = supabase.rpc("search_nearby_places", {
            "query_embedding": query_vector,
            "user_lat": user_lat,
            "user_lng": user_lng,
            "radius_meters": 10000,
            "category_filter": category,
            "match_count": 10
        }).execute()

        docs = res.data

        if not docs or len(docs) == 0:
            return "DATABASE SEARCH RETURNED NO RESULTS. Please inform the user that you don't have this specific data saved, but offer a recommendation based on your general knowledge of Kuala Lumpur."
        
        logger.info(f"Retrieved {len(docs)} documents from Vector Store.")

        formatted_results = []
        for d in docs:
            place_info = (
                f"Name: {d.get('name', 'Unknown')}\n"
                f"Type: {d.get('sub_category') or d.get('primary_category') or 'None'}\n"
                f"Address: {d.get('address', 'No address provided')}\n"
                f"Rating: {d.get('reviews_average', 0)} stars ({d.get('reviews_count', 0)} reviews)\n"
                f"Distance: {round(d.get('distance_meters', 0))} meters away"
            )
            formatted_results.append(place_info)

        return "\n\n---\n\n".join(formatted_results)
    
    except Exception as e:
        logger.error(f"Database Search Failed: {str(e)}")
        return "DATABASE SEARCH UNAVAILABLE. Use your own knowledge to assist the user."

tools = [kl_destinations_search, get_restaurant_reviews]

# Define the persona and logic
system_message = """
You are Drift, a KL travel assistant. Your goal is to help users plan itineraries and discover local destinations.

CRITICAL CONTEXT:
- User Current Latitude: {{user_lat}}
- User Current Longitude: {{user_lng}}

User Travel Preferences:
{user_preferences}

WORKFLOW RULES:
1. When recommending food, you MUST first search the database for locations.
2. IMMEDIATELY after finding locations, use 'get_restaurant_reviews' for the top 2-3 spots.
3. Your final response MUST include the specific dishes you found in the reviews (e.g., "People on TripAdvisor recommend the Mandi Lamb here").

CRITICAL INSTRUCTIONS & BOUNDARIES:
1. You are a specialized travel agent, NOT a general-purpose AI. 
2. You MUST strictly refuse to answer any questions that are unrelated to travel, tourism, geography, culture, or dining in Malaysia.
3. If a user asks you to write code, solve math, write essays, or discuss off-topic subjects (like politics, general trivia, or unrelated countries), you must politely decline.
4. Use this exact tone for refusals: "I'm Drift, your Kuala Lumpur travel assistant! I'd love to help you plan your trip or find a great spot for Nasi Lemak, but I can't assist with [insert their topic]."
5. Prioritize recommendations that are physically close to the user's current location.
6. When using the kl_destinations_search tool, you MUST provide the latitude and longitude listed above.
7. If the user is in a specific neighborhood (like Seri Kembangan, Cheras, or Bangsar), suggest local hidden gems, neighborhood cafes, and nearby parks BEFORE suggesting major landmarks like the Petronas Towers.
8. Always tailor your recommendations to match the user's budget and travel style.
"""

prompt = ChatPromptTemplate.from_messages([
    ("system", system_message),
    MessagesPlaceholder(variable_name="chat_history"),
    ("human", "{input}"),
    MessagesPlaceholder(variable_name="agent_scratchpad"),
])

# Create the internal agent logic
agent = create_tool_calling_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True)

async def agent_with_manual_history(user_message: str, user_id: str, prefs_context: str):
    """
    Orchestrates the Async History flow:
    1. Fetches history from Postgres.
    2. Runs Agent with history injected.
    3. Saves response back to Postgres.
    """
    full_response = ""

    history_manager = await get_session_history(user_id)
    old_messages = await history_manager.aget_messages()

    async for event in agent_executor.astream_events(
        {
            "input": user_message,
            "chat_history": old_messages,
            "user_preferences": prefs_context
        },
        version="v2"
    ):
        kind = event["event"]
        
        if kind == "on_chat_model_stream":
            content = event["data"]["chunk"].content

            token_text = ""
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and "text" in item:
                        token_text += item["text"]
            else:
                token_text = str(content)

            if token_text:
                full_response += token_text
                yield token_text

    await history_manager.aadd_messages([
        HumanMessage(content=user_message),
        AIMessage(content=full_response)
    ])