import logging
from langchain_core.messages import HumanMessage, AIMessage
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent
from langchain.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_community.tools import DuckDuckGoSearchRun
import cohere

from config import config
from utilities.chat_history import get_session_history

# 1. Logging to watch the agent's internal thought process
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
cohere_client = None

CATEGORY_RPC_MAPPING = {
    "Accommodation": "search_accommodations_hybrid",
    "Food": "search_nearby_places_hybrid",
    "Attraction": "search_nearby_places_hybrid"
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
def kl_destinations_search(query: str, user_lat: float, user_lng: float, category: str = "General", sub_category: str = None):
    """
    Search the centralized travel database for destinations in Kuala Lumpur, Selangor, and wider Malaysia.
    
    CRITICAL INTENT ROUTING RULES:
    1. If the user asks for hotels, hostels, serviced apartments, resorts, stays, or lodging, you MUST set category='Accommodation'.
    2. If the user asks for cafes, dining, specific food items, or restaurants, you MUST set category='Food'.
    3. If the user asks for sights, landmarks, temples, or parks, you MUST set category='Attraction'.
    
    - query: Specific search terms (e.g., 'boutique hotel', 'nasi lemak', 'Batu Caves').
    - user_lat / user_lng: The exact coordinates provided locked in system context.
    """
    global cohere_client

    rpc_function = CATEGORY_RPC_MAPPING.get(category, config.QUERY_FUNCTION)
    logger.info(f"SCALABLE ROUTER - Routing query to DB RPC: '{rpc_function}' | Category Flag: '{category}' | Query: '{query}'")

    try:
        if cohere_client is None:
            logger.info("First tool run detected. Initializing persistent Cohere ClientV2 instance...")
            cohere_client = cohere.ClientV2(api_key=config.COHERE_API_KEY)

        asymmetric_query = f"task: search result | query: {query}"
        logger.info(f"[VERIFICATION - STEP 2] Generating asymmetric embedding text mapping via gemini-embedding-2...")
        query_vector = config.embeddings.embed_query(asymmetric_query)

        logger.info(f"└── Successfully generated vector. Dimension output shape size: {len(query_vector)}")

        rpc_args = {
            "query_embedding": query_vector,
            "query_text": query,
            "user_lat": user_lat,
            "user_lng": user_lng,
            "radius_meters": 10000.0,
            "match_count": 50
        }

        if rpc_function == "search_accommodations_hybrid":
            rpc_args["sub_category_filter"] = sub_category
        else:
            rpc_args["category_filter"] = category

        res = config.supabase.rpc(rpc_function, rpc_args).execute()

        docs = res.data

        if not docs or len(docs) == 0:
            logger.info(f"DATABASE MISS for '{query}'. Executing code-enforced DuckDuckGo fallback...")
            
            search = DuckDuckGoSearchRun()
            fallback_web_query = f"best {query} recommendations in kuala lumpur selangor travel reviews"
            
            try:
                web_raw_snippets = search.run(fallback_web_query)
                return (
                    f"SYSTEM LOG: Our internal database records yielded 0 active profiles for '{query}'. "
                    f"The system successfully failed-over to live web scanning.\n\n"
                    f"LIVE WEB CONTEXT:\n{web_raw_snippets}\n\n"
                    f"INSTRUCTION: Synthesize these live web results to fulfill the user request, stating they are from live web sources."
                )
            except Exception as web_err:
                logger.error(f"DuckDuckGo fallback failed: {str(web_err)}")
                return "No matching database metrics found, and fallback live search nodes are overloaded."
        
        logger.info(f"Retrieved {len(docs)} raw entries from database. Transferring to Cohere Rerank...")

        documents_for_rerank = []
        for d in docs:
            phone = d.get('phone_number')
            contact_chunk = f" Contact: {phone}." if phone else ""

            chunk = (
                f"Name: {d.get('name', 'Unknown')}. "
                f"Type: {d.get('primary_category', 'N/A')} - {d.get('sub_category', 'General')}. "
                f"Address: {d.get('address', 'Kuala Lumpur, Malaysia')}. "
                f"{contact_chunk}"
                f"Community Score: {d.get('reviews_average', 0)}/5 stars across {d.get('reviews_count', 0)} reviews."
            )
            documents_for_rerank.append(chunk)

        # 4. Run Cloud-Based Multilingual Cross-Encoder Reranking
        logger.info(f"[VERIFICATION - STEP 5] Sending document array to Cohere 'rerank-v3.5' cross-encoder...")
        rerank_response = cohere_client.rerank(
            model="rerank-v3.5",
            query=query,
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

            # Extract phone number if exists
            phone_val = matched_doc.get('phone_number')
            contact_line = f"Contact Number: {phone_val}\n" if phone_val else ""

            if rank_item.relevance_score < 0.25 and len(formatted_results) == 0:
                logger.info(f"⚠️ Low Cohere confidence match ({relevance_confidence}%). Intercepting with Web Search Fallback.")
                search = DuckDuckGoSearchRun()
                web_raw_snippets = search.run(f"best {query} kuala lumpur travel choices and reviews")
                return f"SYSTEM LOG: Internal data lacked direct relevance. Live web search results for '{query}':\n\n{web_raw_snippets}"

            logger.info(f"Rerank Score Adjustment: '{matched_doc.get('name')}' consolidated to {relevance_confidence}%")

            place_info = (
                f"Destination Name: {matched_doc.get('name', 'Unknown')}\n"
                f"Classification: {category} ({matched_doc.get('sub_category', 'N/A')})\n"
                f"Exact Address: {matched_doc.get('address', 'Information Missing')}\n"
                f"{contact_line}"
                f"Metrics: {matched_doc.get('reviews_average', 0)} stars ({matched_doc.get('reviews_count', 0)} reviews)\n"
                f"Proximity: {round(matched_doc.get('distance_meters', 0))} meters away from user coordinates\n"
                f"System Relevance Confidence: {relevance_confidence}%"
            )
            formatted_results.append(place_info)

        logger.info(f"[VERIFICATION - COMPLETE] Successfully formatted top 3 contexts to yield to agent prompt context.")
        return "\n\n---\n\n".join(formatted_results)
    
    except Exception as e:
        logger.error(f"Critical execution failure inside kl_destinations_search: {str(e)}", exc_info=True)
        return "DATABASE AND SEARCH CHANNELS TEMPORARILY OFFLINE. Assist user via fallback knowledge bases."

async def agent_with_manual_history(user_message: str, session_id: str, prefs_context: str, user_lat: float, user_lng: float):
    history_manager = await get_session_history(session_id)
    old_messages = await history_manager.aget_messages()
    logger.info(f"├── Successfully compiled conversation log. Loaded previous messages count: {len(old_messages)}")

    full_response = ""
    
    tools = [kl_destinations_search, get_restaurant_reviews]

    system_prompt_content = (
        "You are Drift, a helpful and expert AI travel assistant specializing ONLY in Kuala Lumpur, Selangor, and wider Malaysia.\n\n"
        "CORE RETRIEVAL STRATEGY RULES:\n"
        "1. For general or specific queries about places, start by using the 'kl_destinations_search' tool to check our high-confidence local database.\n"
        "2. If 'kl_destinations_search' returns no results, or if the user asks for trending spots, viral TikTok food venues, blog articles, or real-time web reviews, "
        "you MUST immediately fallback to using the 'get_restaurant_reviews' tool to execute a web search.\n"
        "3. Do not give up if the database is empty; seamlessly transition to web search to find options for the user.\n\n"
        "CRITICAL TELEMETRY RULES:\n"
        f"- The user's CURRENT coordinates are Latitude: {user_lat}, Longitude: {user_lng}. These coordinates are locked.\n"
        "- When using kl_destinations_search, you MUST pass these exact coordinates into user_lat and user_lng parameters.\n\n"
        "PERSONALIZATION MATRIX:\n"
        f"Tailor your conversational tone and choices around these explicit user preferences:\n{prefs_context}\n\n"
        "CRITICAL OUTPUT FORMATTING STYLE:\n"
        "When listing recommended places, hotels, or serviced apartments, you MUST structure them using clean Markdown H3 headers for the main titles.\n\n"
        "DO NOT DO THIS:\n"
        "- 1. **Furama Bukit Bintang**\n\n"
        "EXCLUSIVELY USE THIS EXACT MARKDOWN PATTERN:\n"
        "### 1. [Insert Place Name Here]\n"
        "  * **Vibe:** [Insert descriptions, vibe, proximity, or amenities here]\n"
        "  * **Location:** [Insert address details here]\n\n"
        "Strictly ensure that the place name line starts directly with '### ' followed by the number (e.g., '### 1. ', '### 2. '). Do not put any list dashes (*, -, or •) before the '###' tag. Bullets are ONLY allowed for the indented attributes directly underneath the title.\n\n"
        "CONVERSATIONAL STYLE:\n"
        "- Keep responses clear, concise, and professional.\n"
        "- If a place is gathered from web search rather than the database, present it beautifully using the template above and mention it was found via live web review snippets."
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