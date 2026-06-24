import logging
from langchain_core.messages import HumanMessage, AIMessage
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent
from langchain.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_community.tools import DuckDuckGoSearchRun
import cohere
from datetime import datetime

from concurrent.futures import ThreadPoolExecutor
from contextvars import ContextVar

from config import config
from utilities.chat_history import get_session_history
from utilities.geospatial import get_closest_neighborhood
from langchain_google_genai import ChatGoogleGenerativeAI

# Async-safe context variables to hold the true user coordinates
actual_user_lat: ContextVar[float] = ContextVar("actual_user_lat")
actual_user_lng: ContextVar[float] = ContextVar("actual_user_lng")

# Initialize helper LLM for subtasks/classifications to prevent callback stream pollution
helper_llm = ChatGoogleGenerativeAI(
    model="gemini-3.1-flash-lite", 
    google_api_key=config.GOOGLE_API_KEY,
    temperature=0
)

# 1. Logging to watch the agent's internal thought process
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
cohere_client = None

CATEGORY_RPC_MAPPING = {
    "Accommodation": "search_accommodations_hybrid",
    "Food": "search_nearby_places_hybrid",
    "Cultural": "search_nearby_places_hybrid",
    "Natural": "search_nearby_places_hybrid",
    "Shopping": "search_nearby_places_hybrid",
    "Theme": "search_nearby_places_hybrid",
    "Wellness": "search_nearby_places_hybrid"
}

@tool
def get_restaurant_reviews(restaurant_name: str):
    """
    Finds food recommendations and reviews for a specific restaurant.
    Uses TripAdvisor snippets to find what people recommend ordering.
    """
    logger.info(f"TOOL TRIGGERED: get_restaurant_reviews for target: '{restaurant_name}'")
    search = DuckDuckGoSearchRun()
    query = f"site:tripadvisor.com.my Food recommend at {restaurant_name}"

    try:
        result = search.run(query)
        logger.info(f"TripAdvisor scrap completion. Yielded context byte length: {len(result)}")
        return result
    except Exception as e:
        logger.error(f"TripAdvisor scrap anomaly: {str(e)}")
        return "Could not retrieve live web reviews."
    
def is_query_location_specific(query: str) -> bool:
    """
    Checks if the query specifically mentions a neighborhood, city, area, landmark,
    or place name in Malaysia (e.g. 'Cyberjaya', 'Bukit Bintang', 'Petaling Jaya').
    Calls config.llm to do the classification.
    """
    logger.info(f"Location specificity classification for query: '{query}'")
    prompt = (
        "You are a helpful travel assistant. Classify whether the user's travel query specifically mentions "
        "a specific area, town, neighborhood, city, landmark, or region name in Malaysia (for example: "
        "'Cyberjaya', 'Bukit Bintang', 'Batu Caves', 'Petaling Jaya', 'KLCC', 'Malacca', 'KLIA', etc.).\n"
        "If a specific place name/area/neighborhood is mentioned, respond with exactly 'YES'.\n"
        "If the query is generic (e.g., 'hotel room', 'good food', 'recommend a cafe near me', 'sightseeing around here', 'bars', 'places to stay') "
        "without specifying a distinct named geographical location in Malaysia, respond with exactly 'NO'.\n"
        "Do not include any other text or explanation. Only respond with YES or NO.\n\n"
        f"Query: \"{query}\"\n"
        "Response:"
    )
    try:
        response = helper_llm.invoke(prompt, config={"callbacks": []})
        content = response.content
        if isinstance(content, list):
            text_content = ""
            for item in content:
                if isinstance(item, dict) and "text" in item:
                    text_content += item["text"]
                elif isinstance(item, str):
                    text_content += item
        else:
            text_content = str(content)
        text = text_content.strip().upper()
        logger.info(f"Location specificity classification output: '{text}'")
        return "YES" in text
    except Exception as e:
        logger.error(f"Error classifying query location specificity: {str(e)}")
        # Fallback checks
        known_places = ["cyberjaya", "bukit bintang", "batu caves", "petaling jaya", "pj", "klcc", "malacca", "melaka", "sepang", "klia", "puchong", "sri petaling", "chow kit", "damansara", "hartamas", "kuchai", "pudu", "subang", "shah alam", "bangsar", "cheras", "gombak", "rawang", "kajang", "ampang", "kl"]
        query_lower = query.lower()
        if any(place in query_lower for place in known_places):
            return True
        return False

def is_query_continuance(query: str, history_context: str) -> bool:
    """
    Classifies if the new query is a continuance or follow-up of the previous conversation context.
    If the topic, category, or location changes completely, returns False.
    """
    if not history_context:
        return False
        
    prompt = (
        "You are an expert conversation analyst.\n"
        "Determine if the user's new message is a continuance, follow-up, or refers to the context of the previous conversation history.\n\n"
        "Conversation History:\n"
        f"{history_context}\n\n"
        f"New Message: \"{query}\"\n\n"
        "Rules:\n"
        "- Respond with exactly 'YES' if the new message is a direct follow-up, refers to a place/topic from the history, or uses pronouns referring to items in the history (e.g. 'what about reviews?', 'is it near there?', 'give me more options', 'recommend more parks').\n"
        "- Respond with exactly 'NO' if the new message switches to an entirely different topic, location, or recommendation category (e.g. they asked about restaurants before, and now ask about parks or hotels, or they ask about a completely different city/neighborhood, or start a new thread topic).\n"
        "Do not include any other text or explanation. Only respond with YES or NO.\n"
        "Response:"
    )
    try:
        response = helper_llm.invoke(prompt, config={"callbacks": []})
        content = response.content
        if isinstance(content, list):
            text_content = ""
            for item in content:
                if isinstance(item, dict) and "text" in item:
                    text_content += item["text"]
                elif isinstance(item, str):
                    text_content += item
        else:
            text_content = str(content)
        result = text_content.strip().upper()
        logger.info(f"Query continuance classification output: '{result}'")
        return "YES" in result
    except Exception as e:
        logger.error(f"Error classifying query continuance: {str(e)}")
        return True # Default to True to avoid losing history context on error

@tool
def kl_accommodations_search(query: str, user_lat: float, user_lng: float, cost_tier: str = None, sub_category: str = None) -> str:
    """
    Search strictly for places to stay overnight, lodging, and hospitality venues in Malaysia.
    
    CRITICAL APPLICATION: Use this tool ONLY when the user is explicitly looking to book a room, 
    find a hotel, a backpacker hostel, homestay, resort, or overnight lodging.
    
    CLASSIFICATION WARNING: DO NOT use this tool for restaurants, cafes, food, malls, or daytime activities.
    
    PARAMETERS:
    - query (str): Specific area name or lodging keyword (e.g., 'hostels in Petaling Jaya', 'stay in Cyberjaya').
    - cost_tier (str): Optional budget flag. Pass strictly: 'budget', 'moderate', or 'luxury' if inferred.
    - sub_category (str): Optional specific type. Pass strictly: 'Hostel', 'Hotel', or 'Service apartment'.
    """
    logger.info(f"ACCOMMODATION ROUTER - Executing query: '{query}' | Lat: {user_lat} | Lng: {user_lng} | Tier: {cost_tier} | Sub: {sub_category}")
    
    try:
        query_vector = config.embeddings.embed_query(query)
        
        try:
            true_lat = actual_user_lat.get()
            true_lng = actual_user_lng.get()
            logger.info(f"ACCOMMODATION SEARCH - Enforced true coordinates from context: ({true_lat}, {true_lng})")
        except LookupError:
            true_lat = user_lat
            true_lng = user_lng

        is_specific = is_query_location_specific(query)
        radius = 150000.0 if is_specific else 12000.0
        logger.info(f"ACCOMMODATION SEARCH - Specific location detected: {is_specific}. Using radius: {radius} meters")

        rpc_args = {
            "query_text": query,
            "query_embedding": query_vector,
            "user_lat": float(true_lat),
            "user_lng": float(true_lng),
            "radius_meters": radius,
            "cost_tier_filter": cost_tier if cost_tier else None,
            "subcategory_filter": sub_category if sub_category else None,
            "match_count": 10
        }
        
        res = config.supabase.rpc("search_accommodations_hybrid", rpc_args).execute()
        docs = res.data
        
        if not docs:
            return "No matching hotels, hostels, or accommodation choices found in this target region area."
            
        formatted_accommodation = []
        for d in docs:
            info = (
                f"Accommodation Option: {d.get('name', 'Unknown')}\n"
                f"Type: {d.get('sub_category', 'General')} | Price Bracket: {d.get('cost_tier', 'Moderate')}\n"
                f"Location / Address: {d.get('address', 'Information Missing')}\n"
                f"Rating Summary: {d.get('reviews_average', 0)} stars ({d.get('reviews_count', 0)} reviews)\n"
                f"Description Context: {d.get('introduction', 'No description available.')}"
            )
            formatted_accommodation.append(info)
            
        return "\n\n---\n\n".join(formatted_accommodation)
        
    except Exception as e:
        logger.error(f"Accommodations database query layer failure: {str(e)}", exc_info=True)
        return "Accommodation databases are currently undergoing system resets. Re-route user to general advice."

@tool
def kl_destinations_search(query: str, user_lat: float, user_lng: float, category: str = "General", sub_category: str = None, prefs_context: str = ""):
    """
    Search for permanent local daytime activities, sightseeing attractions, and food spots across Malaysia.
    
    CRITICAL APPLICATION: Use this ONLY for day-trip venues, cafes, restaurants, dining, shopping malls, 
    spas, landmarks, parks, and general sightseeing. 
    
    CLASSIFICATION WARNING: DO NOT use this tool if the user is looking for a place to stay, hotels, or overnight lodging.

    PARAMETERS:
    - query (str): Complete descriptive search terms or target destination area strings (e.g., 'massage', 'malls in Bukit Bintang', 'Cyberjaya cafes').
    
    - category (str): You MUST choose from one of these exact strings if applicable:
                      'Food'
                      'Shopping mall'
                      'Natural attraction'
                      'Theme park'
                      'Cultural and historical landmark'
                      'Wellness'
                      Use 'General' only if the user's request does not fit any of these categories.
    - sub_category (str): Optional specific filter keys (e.g., 'Cafe', 'Italian restaurant', 'Spa', 'Massage').
    - prefs_context (str): Active user profile preferences passed to refine database lookups.
    """
    global cohere_client

    rpc_function = CATEGORY_RPC_MAPPING.get(category, config.QUERY_FUNCTION)
    logger.info(f"SCALABLE ROUTER - Routing query to DB RPC: '{rpc_function}' | Category Flag: '{category}' | Query: '{query}'")

    def run_parallel_searches(search_queries):
        search_tool = DuckDuckGoSearchRun()
        results = []
        
        with ThreadPoolExecutor(max_workers=len(search_queries)) as executor:
            futures = {executor.submit(search_tool.run, q): q for q in search_queries}
            for future in futures:
                q = futures[future]
                try:
                    data = future.result()
                    if data and isinstance(data, str):
                        for snippet in data.split("\n\n"):
                            clean_snippet = snippet.strip()
                            if len(clean_snippet) > 40 and "Error" not in clean_snippet:
                                results.append(clean_snippet)
                except Exception as err:
                    logger.error(f"Batch search fragment failed for '{q}': {str(err)}")
        return results if len(results) > 0 else ["No real-time web results available for this query location boundary context."]

    try:
        if cohere_client is None:
            logger.info("First tool run detected. Initializing persistent Cohere ClientV2 instance...")
            cohere_client = cohere.ClientV2(api_key=config.COHERE_API_KEY)

        extracted_cost_tier = None
        if prefs_context and prefs_context.strip() != "":
            normalized_prefs = prefs_context.lower()
            if "budget: budget" in normalized_prefs:
                extracted_cost_tier = "Budget"
            elif "budget: moderate" in normalized_prefs:
                extracted_cost_tier = "Moderate"
            elif "budget: luxury" in normalized_prefs:
                extracted_cost_tier = "Luxury"
        
        logger.info(f"[VERIFICATION - STEP 2] Generating asymmetric embedding text mapping via gemini-embedding-2...")
        query_vector = config.embeddings.embed_query(query)

        logger.info(f"Successfully generated vector. Dimension output shape size: {len(query_vector)}")

        try:
            true_lat = actual_user_lat.get()
            true_lng = actual_user_lng.get()
            logger.info(f"DESTINATION SEARCH - Enforced true coordinates from context: ({true_lat}, {true_lng})")
        except LookupError:
            true_lat = user_lat
            true_lng = user_lng

        is_specific = is_query_location_specific(query)
        radius = 150000.0 if is_specific else 12000.0
        logger.info(f"DESTINATION SEARCH - Specific location detected: {is_specific}. Using radius: {radius} meters")

        if rpc_function == "search_accommodations_hybrid":
            rpc_args = {
                "query_text": query,
                "query_embedding": query_vector,
                "cost_tier_filter": extracted_cost_tier,
                "subcategory_filter": sub_category,
            }
        else:
            rpc_args = {
                "query_text": query,
                "query_embedding": query_vector,
                "user_lat": float(true_lat),
                "user_lng": float(true_lng),
                "radius_meters": radius,
                "category_filter": category if category != "General" else None,
                "cost_tier_filter": extracted_cost_tier,
            }

        res = config.supabase.rpc(rpc_function, rpc_args).execute()
        docs = res.data or []

        valid_db_results = []
        if docs and len(docs) > 0:
            logger.info(f"Retrieved {len(docs)} raw entries from database. Transferring to Cohere Rerank...")

            documents_for_rerank = []
            for d in docs:
                intro_chunk = f" Context: {d.get('introduction')}." if d.get('introduction') else ""
                cost_val = d.get('cost_tier', 'N/A')
                cost_chunk = f" Cost Category: {cost_val}."

                chunk = (
                    f"Target Location Match: Located in or near {query}. "
                    f"Name: {d.get('name', 'Unknown')}. "
                    f"Type: {d.get('primary_category', 'N/A')} - {d.get('sub_category', 'General')}. "
                    f"Address: {d.get('address', 'Kuala Lumpur, Malaysia')}. "
                    f"{intro_chunk}"
                    f"{cost_chunk}"
                    f"Community Score: {d.get('reviews_average', 0)}/5 stars across {d.get('reviews_count', 0)} reviews."
                )
                documents_for_rerank.append(chunk)

            # Run Cloud-Based Multilingual Cross-Encoder Reranking
            logger.info(f"[VERIFICATION - STEP 5] Sending document array to Cohere 'rerank-v3.5' cross-encoder...")
            
            top_n_val = len(documents_for_rerank)
            rerank_response = cohere_client.rerank(
                model="rerank-v3.5",
                query=f"best {sub_category or 'places'} in or near {query} with {extracted_cost_tier or 'Moderate'} budget options",
                documents=documents_for_rerank,
                top_n=top_n_val
            )

            logger.info("[VERIFICATION - STEP 6] Cohere sorting complete. Filtering relevance scores >= 0.45:")
            for rank_item in rerank_response.results:
                relevance_score = rank_item.relevance_score
                if relevance_score >= 0.45:
                    idx = rank_item.index
                    matched_doc = docs[idx]
                    relevance_confidence = round(relevance_score * 100, 1)
                    
                    place_info = (
                        f"Destination Name: {matched_doc.get('name', 'Unknown')}\n"
                        f"Vibe: {matched_doc.get('introduction', 'Excellent option matching user profile indices.')}\n"
                        f"Location: {matched_doc.get('address', 'Information Missing')}\n"
                        f"Metrics: {matched_doc.get('reviews_average', 0)} stars ({matched_doc.get('reviews_count', 0)} reviews) | Price Tier: {matched_doc.get('cost_tier', 'Moderate')}\n"
                        f"System Relevance Confidence: {relevance_confidence}%"
                    )
                    valid_db_results.append(place_info)
                    if len(valid_db_results) == 4:
                        break
        
        needed = 4 - len(valid_db_results)
        extracted_web_results = []

        if needed > 0:
            logger.info(f"Database provided {len(valid_db_results)} valid recommendations. Fetching {needed} more from live web search.")
            search_queries = [
                f"best {query} recommendations in kuala lumpur selangor travel reviews",
                f"top trending viral {query} kuala lumpur blogs reviews",
                f"hidden gem secret {query} locations around kuala lumpur"
            ]
            web_raw_snippets = run_parallel_searches(search_queries)
            valid_snippets = [s for s in web_raw_snippets if s and len(s.strip()) > 30]

            if valid_snippets:
                top_snippets = []
                try:
                    web_rerank = cohere_client.rerank(
                        model="rerank-v3.5",
                        query=query,
                        documents=valid_snippets,
                        top_n=min(15, len(valid_snippets))
                    )
                    top_snippets = [valid_snippets[r.index] for r in web_rerank.results]
                except Exception as rerank_err:
                    logger.warning(f"Cohere rerank on web snippets failed: {rerank_err}. Using raw snippets.")
                    top_snippets = valid_snippets[:15]

                extraction_prompt = (
                    "You are a travel database extraction assistant.\n"
                    f"We need to find exactly {needed} travel/food recommendations matching the query: '{query}' based on these web search snippets.\n\n"
                    "Web Search Snippets:\n"
                    + "\n".join([f"- {s}" for s in top_snippets]) + "\n\n"
                    f"Identify and extract exactly {needed} distinct recommendations (places/venues/activities) matching the query. "
                    "For each, format the output EXACTLY like the template below. Do not include any other text or markdown headers outside the template:\n\n"
                    "Destination Name: [Place Name]\n"
                    "Vibe: [Brief description/introduction about the place and why it fits the query, based on the snippets]\n"
                    "Location: [Address or neighborhood, e.g. Kuala Lumpur, Bukit Bintang, etc.]\n"
                    "Metrics: [Rating or review summary, e.g., '4.5 stars (120 reviews)' or 'Highly recommended online'] | Price Tier: [Estimated cost tier, e.g., Moderate/Budget/Luxury]\n"
                    "System Relevance Confidence: [Estimate a confidence percentage, e.g. 85.0%]\n\n"
                    "Separate different places with three dashes (---)."
                )

                try:
                    response = helper_llm.invoke(extraction_prompt, config={"callbacks": []})
                    content = response.content
                    if isinstance(content, list):
                        text_content = ""
                        for item in content:
                            if isinstance(item, dict) and "text" in item:
                                text_content += item["text"]
                            elif isinstance(item, str):
                                text_content += item
                    else:
                        text_content = str(content)
                    extracted_text = text_content.strip()
                    logger.info(f"LLM web recommendation extraction result:\n{extracted_text}")

                    # Split by ---
                    parts = [p.strip() for p in extracted_text.split("---") if p.strip()]
                    for part in parts:
                        if "Destination Name:" in part:
                            extracted_web_results.append(part)

                    # If LLM extracted more than needed, limit it
                    extracted_web_results = extracted_web_results[:needed]
                except Exception as extract_err:
                    logger.error(f"Error extracting web recommendations: {extract_err}")

                # Fallback if LLM extraction fails or returns fewer than needed
                if len(valid_db_results) + len(extracted_web_results) < 4:
                    still_needed = 4 - (len(valid_db_results) + len(extracted_web_results))
                    logger.info(f"LLM extraction only provided {len(extracted_web_results)}. Need {still_needed} more. Formatting raw snippets as fallback.")
                    for i in range(min(still_needed, len(top_snippets))):
                        snippet = top_snippets[i]
                        fallback_info = (
                            f"Destination Name: Web recommendation {i+1}\n"
                            f"Vibe: {snippet}\n"
                            f"Location: Kuala Lumpur / Selangor region\n"
                            f"Metrics: Recommended online | Price Tier: Moderate\n"
                            f"System Relevance Confidence: 70.0%"
                        )
                        extracted_web_results.append(fallback_info)

        combined_results = valid_db_results + extracted_web_results
        
        if not combined_results:
            return "No matching database metrics found, and fallback live search nodes are overloaded."

        logger.info(f"[VERIFICATION - COMPLETE] Successfully formatted {len(combined_results)} contexts to yield to agent prompt context.")
        return "\n\n---\n\n".join(combined_results)

    except Exception as e:
        logger.error(f"Critical execution failure inside kl_destinations_search: {str(e)}", exc_info=True)
        return "DATABASE AND SEARCH CHANNELS TEMPORARILY OFFLINE. Assist user via fallback knowledge bases."
    
@tool
def kl_events_and_festivals_search(query: str) -> str:
    """
    Search for upcoming concerts, live sports matches, festivals, and community events 
    happening in Kuala Lumpur, Selangor, and greater Malaysia.
    """
    logger.info(f"TOOL TRIGGERED: kl_events_and_festivals_search | Query: '{query}'")
    
    cleaned_query = query.lower().replace("events in", "").replace("activities in", "").replace("things to do in", "").strip()
    is_generic = cleaned_query in ["kuala lumpur", "selangor", "malaysia", "events", ""]

    try:
        logger.info("[EVENTS RETRIEVAL] Computing search query vector dimensions...")
        embed_text = query if query.strip() else "concert festival sports match exhibition"
        query_vector = config.embeddings.embed_query(embed_text)
        
        rpc_args = {
            "query_text": None if is_generic else cleaned_query,
            "query_embedding": query_vector,
        }
        
        res = config.supabase.rpc("search_upcoming_events_hybrid", rpc_args).execute()
        docs = res.data
        
        if not docs or len(docs) == 0:
            logger.info(f"No current or future events found matching query tokens: '{query}'")
            return "No matching live upcoming events, concerts, or festivals discovered in our local calendar schedule."

        formatted_events = []
        for d in docs:
            venue = f" (Venue: {d.get('venue_name')})" if d.get('venue_name') else ""
            event_info = (
                f"Event Title: {d.get('title', 'Unknown')}\n"
                f"Type: {d.get('category')} - Labels: {d.get('phq_labels', 'N/A')}\n"
                f"Venue: Located{venue} around area of {d.get('locality', 'Kuala Lumpur')}\n"
                f"Schedule: From {d.get('start_time')} until {d.get('end_time')}\n"
                f"Database Matching Confidence Score: {round(d.get('semantic_score', 0) * 100, 1)}%"
            )
            formatted_events.append(event_info)
            
        logger.info(f"Successfully retrieved and structured {len(docs)} upcoming event context nodes.")
        return "\n\n---\n\n".join(formatted_events)

    except Exception as e:
        logger.error(f"Execution boundary crash inside events search tool layer: {str(e)}", exc_info=True)
        return "Events tracking systems are experiencing connection line delays. Advise user to check back shortly."

async def agent_with_manual_history(user_message: str, session_id: str, prefs_context: str, user_lat: float, user_lng: float):
    # Set actual user coordinates in async-safe context
    actual_user_lat.set(user_lat)
    actual_user_lng.set(user_lng)
    
    history_manager = await get_session_history(session_id)
    old_messages = await history_manager.aget_messages()
    logger.info(f"Successfully compiled conversation log. Loaded previous messages count: {len(old_messages)}")

    # Check if the new user query is a continuation of the conversation history.
    # If not, we don't pass the old messages to the LLM.
    if old_messages:
        history_chunks = []
        for msg in old_messages:
            role = "User" if msg.__class__.__name__ == "HumanMessage" else "Assistant"
            history_chunks.append(f"{role}: {msg.content}")
        history_text = "\n".join(history_chunks)
        
        if not is_query_continuance(user_message, history_text):
            logger.info("New query is NOT a continuance of the previous conversation context. Skipping chat history payload.")
            old_messages = []

    user_neighborhood = get_closest_neighborhood(user_lat, user_lng)
    full_response = ""
    
    tools = [kl_destinations_search, get_restaurant_reviews, kl_events_and_festivals_search, kl_accommodations_search]

    system_prompt_content = (
        "You are Drift, a helpful and expert AI travel assistant specializing ONLY in Kuala Lumpur, Selangor, and wider Malaysia.\n\n"
        "ITINERARY CONTEXT HANDLING RULES:\n"
        "- If you detect a JSON-formatted itinerary in the chat history (messages with role='bot' starting with JSON containing 'destination' and 'days'), you must treat it as the user's active travel plan.\n"
        "- If the user asks questions, details, advice, or packing tips related to this plan (while Itinerary Mode is OFF), answer them conversationally in clean Markdown based on the itinerary's activities.\n"
        "- DO NOT attempt to write or output raw JSON strings yourself in conversational mode. Only answer their questions using the plan's details.\n\n"
        "CONTEXT ISOLATION & TOPIC SWITCHING RULES:\n"
        "- If the user asks a new question that switches topics, changes locations, or requests a different category of recommendation (e.g. switching from food/restaurants to parks, or lodging to sightseeing), do NOT carry over, reference, or note previous recommendations or topics from the chat history. Focus strictly on answering the current prompt.\n"
        "- Do not append postscript notes, reminders, or comparisons about previous destinations or activities from the chat history unless the user explicitly requests a comparison or carryover in their new message.\n\n"
        "CRITICAL POSTGIS MANDATORY PARAMETER RULES:\n"
        f"- The user's actual current location coordinates are strictly: Latitude: {user_lat}, Longitude: {user_lng}.\n"
        f"- When calling 'kl_destinations_search' or 'kl_accommodations_search', you MUST ALWAYS pass these exact coordinates ({user_lat} and {user_lng}) into the user_lat and user_lng parameters. DO NOT modify them, even if the query mentions a specific area like Cyberjaya or Melaka.\n\n"
        "SINGLE RETRIEVAL SEARCH RULE:\n"
        "- Do NOT perform multiple database search tool calls (like 'kl_destinations_search') in a single turn. Perform exactly ONE database search tool call for the target query destination. If the user mentions a specific area, search strictly for that area in the query parameter. Do not make a separate search call for the current neighborhood.\n"
        "- You are still expected and allowed to call 'get_restaurant_reviews' for each retrieved destination to get reviews.\n\n"
        "TOOL SELECTION RESTRICTIONS:\n"
        "- Trigger 'kl_destinations_search' for all daytime sightseeing, cafes, dinner spots, spas, and malls.\n"
        "- Trigger 'kl_accommodations_search' if a user asks for an overnight hotel, lodging, or place to sleep, and pass user_lat and user_lng down.\n"
        "- Immediately after retrieving the destinations, use each destination's name to perform a web search "
        f"using the 'get_restaurant_reviews' tool for reviews and recommendations.\n"
        "PERSONALIZATION LOGIC:\n"
        f"Tailor descriptions around these active user preferences:\n{prefs_context}\n\n"
        "CRITICAL OUTPUT FORMATTING STYLE:\n"
        "You MUST provide at least 4 distinct recommendations in your final response when recommending locations, sightseeing spots, or dining options, using the information retrieved from search tools. Do not shorten or truncate the list.\n"
        "You MUST structure recommended options using clean Markdown H3 headers for titles. Follow this pattern:\n\n"
        "### 1. [Insert Place Name]\n"
        "  * **Vibe & Context:** [Synthesize description context and pricing elements]\n"
        "  * **Details & Proximity:** [Provide address details and call out the literal distance away in km from the tool output!]\n\n"
        "Ensure the place name line starts directly with '### ' followed by the number. Do not use list dashes before the '###' tag."
    )

    runtime_prompt = ChatPromptTemplate.from_messages([
        ("system", system_prompt_content),
        MessagesPlaceholder(variable_name="chat_history"),
        ("human", "{input}"),
        MessagesPlaceholder(variable_name="agent_scratchpad"),
    ])

    runtime_agent = create_tool_calling_agent(config.llm, tools, runtime_prompt)
    runtime_executor = AgentExecutor(agent=runtime_agent, tools=tools, verbose=True)

    async def execute_stream():
        nonlocal full_response
        async for event in runtime_executor.astream_events(
            {
                "input": user_message,
                "chat_history": old_messages,
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
            elif kind == "on_tool_start":
                tool_name = event["name"]
                if tool_name in [
                    "kl_destinations_search",
                    "kl_accommodations_search",
                    "kl_events_and_festivals_search",
                    "get_restaurant_reviews"
                ]:
                    yield "__STATUS:searching__"

    async def for_yield():
        async for token in execute_stream():
            yield token

    async for token in for_yield():
        yield token

    logger.info(f"[AGENT SAVE] Streaming completed. Appending human/assistant logs to database store...")
    await history_manager.aadd_messages([
        HumanMessage(content=user_message),
        AIMessage(content=full_response)
    ])
    logger.info("└── Active conversation context stored seamlessly.")