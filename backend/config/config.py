import os
from dotenv import load_dotenv
from supabase.client import create_client
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
COHERE_API_KEY = os.getenv("COHERE_API_KEY")
QUERY_FUNCTION = "search_nearby_places_hybrid"

if not all([SUPABASE_URL, SUPABASE_KEY, GOOGLE_API_KEY, COHERE_API_KEY]):
    raise ValueError("Missing required environment variables. Check your .env file.")

# Initialize Clients
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
embeddings = GoogleGenerativeAIEmbeddings(
    model="models/gemini-embedding-2", 
    google_api_key=GOOGLE_API_KEY,
    output_dimensionality=768
)
llm = ChatGoogleGenerativeAI(
    model="gemini-3.1-flash-lite", 
    google_api_key=GOOGLE_API_KEY,
    temperature=0
)