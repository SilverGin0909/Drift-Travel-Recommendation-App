import logging
from langchain_core.messages import HumanMessage, AIMessage
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent
from langchain.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_community.tools import DuckDuckGoSearchRun
import cohere
from datetime import datetime

from concurrent.futures import ThreadPoolExecutor

from config import config
from utilities.chat_history import get_session_history

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
    
@tool
def kl_accommodations_search(query: str, cost_tier: str = None, sub_category: str = None) -> str:
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
    logger.info(f"ACCOMMODATION ROUTER - Executing query: '{query}' | Tier: {cost_tier} | Sub: {sub_category}")
    
    try:
        query_vector = config.embeddings.embed_query(query)
        
        rpc_args = {
            "query_text": query,
            "query_embedding": query_vector,
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
                "user_lat": float(user_lat),
                "user_lng": float(user_lng),
                "radius_meters": 12000.0,
                "category_filter": category if category != "General" else None,
                "cost_tier_filter": extracted_cost_tier,
            }


        res = config.supabase.rpc(rpc_function, rpc_args).execute()

        docs = res.data

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

        if not docs or len(docs) == 0:
            logger.info(f"DATABASE MISS for '{query}'. Executing code-enforced DuckDuckGo fallback...")
            
            batch_queries = [
                f"best {query} recommendations in kuala lumpur selangor travel reviews",
                f"top trending viral {query} kuala lumpur blogs reviews",
                f"hidden gem secret {query} locations around kuala lumpur"
            ]
            
            try:
                web_raw_snippets = run_parallel_searches(batch_queries)
                return (
                    f"LIVE MULTI-WEB CONTEXT:\n{web_raw_snippets}\n\n"
                )
            except Exception as web_err:
                logger.error(f"DuckDuckGo concurrent fallback failed: {str(web_err)}") #
                return "No matching database metrics found, and fallback live search nodes are overloaded." #
        
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

        # 4. Run Cloud-Based Multilingual Cross-Encoder Reranking
        logger.info(f"[VERIFICATION - STEP 5] Sending document array to Cohere 'rerank-v3.5' cross-encoder...")
        rerank_response = cohere_client.rerank(
            model="rerank-v3.5",
            query=f"best {sub_category or 'places'} in or near {query} with {extracted_cost_tier or 'Moderate'} budget options",
            documents=documents_for_rerank,
            top_n=3
        )

        formatted_results = []

        # 5. Extract re-ordered results based on relevance index
        logger.info("[VERIFICATION - STEP 6] Cohere sorting complete. Mapping final relevance scores:")
        for rank_item in rerank_response.results:
            idx = rank_item.index
            matched_doc = docs[idx]
            relevance_confidence = round(rank_item.relevance_score * 100, 1)

            if rank_item.relevance_score < 0.45:
                logger.info(f"Low Cohere confidence match ({relevance_confidence}%). Intercepting with Multi-Threaded Fallback.") #
                
                low_conf_queries = [
                    f"best {query} kuala lumpur travel choices and reviews",
                    f"is {matched_doc.get('name')} in kuala lumpur worth visiting reviews"
                ]

                web_raw_snippets = run_parallel_searches(low_conf_queries)
                backup_rerank = cohere_client.rerank(
                    model="rerank-v3.5",
                    query=query,
                    documents=web_raw_snippets,
                    top_n=3
                )

                curated_backup = [f"-[Match: {round(r.relevance_score*100)}%] {web_raw_snippets[r.index]}" for r in backup_rerank.results]
                return f"SYSTEM LOG: Internal data lacked direct relevance. Curated multi-perspective web search results for '{query}':\n\n" + "\n\n".join(curated_backup)
            
            logger.info(f"Rerank Score Adjustment: '{matched_doc.get('name')}' consolidated to {relevance_confidence}%")

            place_info = (
                f"Destination Name: {matched_doc.get('name', 'Unknown')}\n"
                f"Vibe: {matched_doc.get('introduction', 'Excellent option matching user profile indices.')}\n"
                f"Location: {matched_doc.get('address', 'Information Missing')}\n"
                f"Metrics: {matched_doc.get('reviews_average', 0)} stars ({matched_doc.get('reviews_count', 0)} reviews) | Price Tier: {matched_doc.get('cost_tier', 'Moderate')}\n"
                f"System Relevance Confidence: {relevance_confidence}%"
            )
            formatted_results.append(place_info)

        logger.info(f"[VERIFICATION - COMPLETE] Successfully formatted top 3 contexts to yield to agent prompt context.")
        return "\n\n---\n\n".join(formatted_results)
    
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
    history_manager = await get_session_history(session_id)
    old_messages = await history_manager.aget_messages()
    logger.info(f"Successfully compiled conversation log. Loaded previous messages count: {len(old_messages)}")

    full_response = ""
    
    tools = [kl_destinations_search, get_restaurant_reviews, kl_events_and_festivals_search, kl_accommodations_search]

    system_prompt_content = (
        "You are Drift, a helpful and expert AI travel assistant specializing ONLY in Kuala Lumpur, Selangor, and wider Malaysia.\n\n"
        "CRITICAL POSTGIS MANDATORY PARAMETER RULES\n"
        f"The user is currently positioned at active coordinates: Latitude: {user_lat}, Longitude: {user_lng}.\n"
        "When calling 'kl_destinations_search', you MUST always pass these exact numbers down into the "
        f"user_lat ({user_lat}) and user_lng ({user_lng}) parameters without exception.\n\n"
        "TOOL SELECTION RESTRICTIONS:\n"
        "- Trigger 'kl_destinations_search' for all daytime sightseeing, cafes, dinner spots, spas, and malls.\n"
        "- Trigger 'kl_accommodations_search' if a user asks for an overnight hotel, lodging, or place to sleep.\n"
        "- Immediately after retrieving the destinations, use each destination's name to perform a web search "
        f"using the 'get_restaurant_reviews' tool for reviews and recommendations.\n"
        "PERSONALIZATION LOGIC:\n"
        f"Tailor descriptions around these active user preferences:\n{prefs_context}\n\n"
        "CRITICAL OUTPUT FORMATTING STYLE:\n"
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