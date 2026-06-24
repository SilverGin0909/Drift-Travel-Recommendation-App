# Drift AI — Travel Recommendation Chatbot

Drift is a state-of-the-art AI-powered travel assistant and planner specializing in Kuala Lumpur, Selangor, and greater Malaysia. By combining real-time GPS coordinates, user preferences, hybrid vector search, and web-search fallbacks, Drift provides hyper-localized dining and attraction recommendations and builds editable, day-by-day travel itineraries.

---

## 🚀 Key Features

- **Dual-Mode AI Interaction**:
  - **Conversational Mode (Itinerary Mode OFF)**: Chat with Drift about local sights, packing tips, or travel details. The chatbot reads the active itinerary from the chat history and grounds its answers contextually.
  - **Structured Planner Mode (Itinerary Mode ON)**: Automatically generates a structured travel itinerary or performs incremental updates (adding, deleting, or tweaking specific days/activities) based on conversational feedback.
- **Geospatial Telemetry (Offline & Free)**:
  - Uses a high-precision **Haversine formula** implementation to resolve coordinates to their nearest neighborhood name (e.g. _Sepang, KLIA, Cyberjaya, Bukit Bintang, Pudu, Chow Kit, Puchong, Sri Petaling, Damansara, Hartamas, Kuchai_).
  - Runs entirely offline with zero latency, zero external API keys, and no rate-limit blocks (avoiding Google Maps charges and Nominatim `403` bans).
- **Hybrid Search & Reranking**:
  - Utilizes PostgreSQL `pgvector` in Supabase for vector-similarity search of local venues.
  - Re-ranks results using the cloud-based **Cohere Rerank-v3.5** model for maximal query-to-document alignment.
  - Falls back to multi-threaded **DuckDuckGo Search** query routing when database coverage is low.
- **Security & Guardrails**:
  - Structured input verification layers defending against prompt injections, SQL injections, and malicious payloads.
- **Modern Premium UI**:
  - Flutter mobile interface with breathing ambient glows, dark mode themes, automatic scroll controls, profile picture customization, and session history side drawers.

---

## 🛠️ Tech Stack

### Frontend (Mobile App)

- **Framework**: Flutter (Dart)
- **Telemetry**: Geolocator (GPS tracking & permission handler)
- **Storage**: Shared Preferences (Local caching & Auto-login flags)
- **Markdown Rendering**: `flutter_markdown_stream` for smooth text rendering of LLM responses
- **State Management**: Stateful widget lifecycle with animated physics

### Backend (API Gateway)

- **Framework**: FastAPI (Python 3.12)
- **Orchestration**: LangChain
- **AI Engine**: Gemini (`gemini-3.1-flash-lite` via Google GenAI)
- **Database & Vector Store**: Supabase (PostgreSQL with `pgvector` extension)
- **Reranking Service**: Cohere Rerank API
- **Web Search**: DuckDuckGo API integration

---

## 📂 Project Structure

```
travel_chatbot_workspace/
├── backend/
│   ├── agent/                 # Agent logic (RAG query routing, planner)
│   │   ├── planner.py         # Itinerary Pydantic models & structured LLM call
│   │   └── rag.py             # Main Conversational agent & tool definitions
│   ├── config/                # Supabase, Embeddings, LLM initializations
│   ├── database/              # Supabase API helper scripts
│   ├── models/                # Pydantic schemas (ChatRequest, UpdateRequest)
│   ├── tests/                 # Backend automated tests (security, geospatial)
│   ├── utilities/             # Helper tools (geospatial, bouncer, router)
│   │   ├── geospatial.py      # Haversine distance calculator
│   │   └── router.py          # Intent router (Greeting vs Travel Query)
│   ├── .env                   # Backend credentials (ignored by git)
│   └── main.py                # FastAPI endpoints & streaming logic
├── frontend/
│   ├── assets/                # App logos and icons
│   ├── lib/
│   │   ├── screens/           # Chat interface, login, signup, itinerary viewer
│   │   ├── services/          # API, Geolocator, User/Profile controllers
│   │   └── widgets/           # Sub-components (ambient glow, side menu, etc.)
│   ├── test/                  # Frontend widget & unit tests
│   └── .env                   # Frontend credentials (ignored by git)
├── .gitignore                 # Root gitignore protecting secrets
└── requirements.txt           # Python dependencies list
```

---

## ⚙️ Setup & Installation

### 1. Database Setup (Supabase)

Create a Supabase project and set up the following database structures:

- A `locations` table representing local sights, cafes, hotels, etc.
- A `chat_sessions` and `chat_messages` table to persist historical threads.
- Implement a PostgreSQL RPC function named `search_nearby_places_hybrid` which performs a cosine similarity calculation on `pgvector` embeddings filtered by latitude/longitude distance radius.

### 2. Backend Configuration

1. Navigate to the backend directory and create a virtual environment:
   ```bash
   cd backend
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r ../requirements.txt
   ```
2. Create a `.env` file inside `backend/` and configure your API credentials:
   ```env
   SUPABASE_URL="https://your-supabase-project.supabase.co"
   SUPABASE_SERVICE_KEY="your-supabase-service-role-key"
   GOOGLE_API_KEY="your-google-gemini-api-key"
   COHERE_API_KEY="your-cohere-rerank-api-key"
   ```
3. Start the FastAPI backend server:
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

### 3. Frontend Configuration

1. Navigate to the frontend directory:
   ```bash
   cd ../frontend
   ```
2. Create a `.env` file inside `frontend/` containing your Supabase public endpoints:
   ```env
   SUPABASE_URL="https://your-supabase-project.supabase.co"
   SUPABASE_ANON_KEY="your-supabase-anon-public-key"
   ```
3. Open `lib/services/api_service.dart` and make sure the `backendUrl` variable points to your local machine's IP address (e.g. `http://192.168.x.x:8000/api/chat`) so that your physical debug phone can access the API.
4. Get Flutter dependencies and run the application:
   ```bash
   flutter pub get
   flutter run
   ```

---

## 🧪 Running Automated Tests

### Backend Unit & Security Tests

Verify system security and geospatial boundary resolutions:

```bash
# From the project root
.venv/Scripts/python.exe backend/tests/test_geospatial.py
.venv/Scripts/python.exe backend/tests/test_security.py
```

### Frontend Widget Tests

Verify component state changes and UI layout:

```bash
cd frontend
flutter test
```
