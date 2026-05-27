import logging
from langchain_core.messages import HumanMessage, AIMessage
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent
from langchain.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_community.tools import DuckDuckGoSearchRun
import cohere

import asyncio
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
def kl_destinations_search(query: str, category: str = "General", sub_category: str = None):
    """
    Search the travel database for destinations in Kuala Lumpur, Selangor, and wider Malaysia.
    Optimized for extracting items via textual name, area location strings, or specific categories.

    PARAMETERS:
    - query (str): Complete descriptive search terms or target destination area strings (e.g., 'massage', 'malls in Bukit Bintang', 'Cyberjaya cafes').
    
    - category (str): Broad primary row type cluster flags. You MUST choose from one of these exact strings if applicable:
                      'Food'
                      'Shopping mall'
                      'Natural attraction'
                      'Theme park'
                      'Cultural and historical landmark'
                      'Wellness'
                      Use 'General' only if the user's request does not fit any of these categories.
                      
    - sub_category (str): Optional specific filter keys (e.g., 'Cafe', 'Italian restaurant', 'Spa', 'Massage').
    """
    global cohere_client

    rpc_function = CATEGORY_RPC_MAPPING.get(category, config.QUERY_FUNCTION)
    logger.info(f"SCALABLE ROUTER - Routing query to DB RPC: '{rpc_function}' | Category Flag: '{category}' | Query: '{query}'")

    try:
        if cohere_client is None:
            logger.info("First tool run detected. Initializing persistent Cohere ClientV2 instance...")
            cohere_client = cohere.ClientV2(api_key=config.COHERE_API_KEY)

        logger.info(f"[VERIFICATION - STEP 2] Generating asymmetric embedding text mapping via gemini-embedding-2...")
        query_vector = config.embeddings.embed_query(query)

        logger.info(f"└── Successfully generated vector. Dimension output shape size: {len(query_vector)}")

        rpc_args = {
            "query_text": query,
            "query_embedding": query_vector,
            "category_filter": category if category != "General" else None,
            "subcategory_filter": sub_category
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
            phone = d.get('phone_number')
            contact_chunk = f" Contact: {phone}." if phone else ""
            intro_chunk = f" Context: {d.get('introduction')}." if d.get('introduction') else ""

            chunk = (
                f"Name: {d.get('name', 'Unknown')}. "
                f"Type: {d.get('primary_category', 'N/A')} - {d.get('sub_category', 'General')}. "
                f"Address: {d.get('address', 'Kuala Lumpur, Malaysia')}. "
                f"{contact_chunk}"
                f"{intro_chunk}"
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
        f"- The user's CURRENT numerical coordinates are Latitude: {user_lat}, Longitude: {user_lng}.\n"
        "- When the user states 'near me', 'nearby', or requests options within their local environment, use your deep geographic world knowledge "
        "to resolve what neighborhood area zone those coordinates point to (e.g., 'Bukit Bintang', 'Cyberjaya', 'Kajang', 'Puchong').\n"
        "- You MUST explicitly weave that resolved area neighborhood name string into the 'query' parameter when executing 'kl_destinations_search' "
        "(e.g., passing query='cafes in Cyberjaya' or query='shopping malls in Bukit Bintang').\n\n"
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