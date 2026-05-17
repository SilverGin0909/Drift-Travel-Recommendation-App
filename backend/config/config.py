import os
from dotenv import load_dotenv
from supabase.client import create_client
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings
from langchain_community.vectorstores import SupabaseVectorStore

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

if not all([SUPABASE_URL, SUPABASE_KEY, GOOGLE_API_KEY]):
    raise ValueError("Missing required environment variables. Check your .env file.")

# Initialize Clients
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2", output_dimensionality=768)
llm = ChatGoogleGenerativeAI(model="gemini-3.1-flash-lite-preview", temperature=0)

# Initialize Vector Store
vector_store = SupabaseVectorStore(
    embedding=embeddings,
    client=supabase,
    table_name="location",
    query_name="search_nearby_places"
)