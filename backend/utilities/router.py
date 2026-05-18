from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.output_parsers import JsonOutputParser
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field

# Using Flash-Lite for sub-second classification
router_llm = ChatGoogleGenerativeAI(model="gemini-3.1-flash-lite", temperature=0)

class RouteDecision(BaseModel):
    intent: str = Field(description="One of: 'GREETING', 'TRAVEL_QUERY', 'OFF_TOPIC'")
    direct_response: str = Field(description="A friendly reply if the intent is GREETING, otherwise empty.")

router_parser = JsonOutputParser(pydantic_object=RouteDecision)

# In utilities/router.py
router_prompt = ChatPromptTemplate.from_messages([
    ("system", (
        "You are a triage assistant for Drift, a KL travel AI. "
        "Classify the user input into one of these intents: 'GREETING', 'TRAVEL_QUERY', or 'OFF_TOPIC'.\n\n"
        "RULES:\n"
        "1. If intent is 'GREETING', you MUST provide a friendly 'direct_response'.\n"
        "2. If intent is 'TRAVEL_QUERY', set 'direct_response' to an empty string.\n"
        "3. If intent is 'OFF_TOPIC', set 'direct_response' to a polite refusal.\n\n"
        "Respond strictly in JSON format."
    )),
    ("human", "{input}")
])

# The Router Chain
router_chain = router_prompt | router_llm | router_parser